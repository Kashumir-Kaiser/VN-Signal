package main

import (
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type kbsInvalidHistoryOptions struct {
	active   bool
	start    string
	end      string
	days     int
	maxCalls int
}

func parseKBSInvalidHistoryArgs(args []string) (kbsInvalidHistoryOptions, error) {
	var out kbsInvalidHistoryOptions
	f := flag.NewFlagSet("ingest-kbs-invalid-history", flag.ContinueOnError)
	f.BoolVar(&out.active, "active", false, "explicitly authorize account-metered KBS calls")
	f.StringVar(&out.start, "from", "", "earliest history date to request")
	f.StringVar(&out.end, "to", "", "latest history date to request")
	f.IntVar(&out.days, "days", 0, "remaining trading days in calendar month")
	f.IntVar(&out.maxCalls, "max-calls", 1, "maximum metered calls (1-5000)")
	if err := f.Parse(args); err != nil {
		return out, err
	}
	if len(f.Args()) != 0 || !out.active || out.days < 1 || out.days > 31 || out.maxCalls < 1 || out.maxCalls > 5000 {
		return out, errors.New("ingest-kbs-invalid-history requires --active --from DATE --to DATE --days N; --max-calls must be 1..5000")
	}
	for _, value := range []string{out.start, out.end} {
		parsed, err := time.Parse("2006-01-02", value)
		if err != nil || parsed.Format("2006-01-02") != value {
			return out, errors.New("--from and --to must be valid ISO dates")
		}
	}
	if out.start > out.end {
		return out, errors.New("--to must be on or after --from")
	}
	return out, nil
}

func runKBSInvalidHistory(args []string) error {
	opts, err := parseKBSInvalidHistoryArgs(args)
	if err != nil {
		return err
	}
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return live.ErrDisabled
	}
	if _, err = config.Load(configPath()); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()
	quotaRead := func(ctx context.Context) (ingest.QuotaSnapshot, error) {
		return readAuthenticatedIndexQuota(ctx, opts.days)
	}
	q, err := quotaRead(ctx)
	if err != nil {
		return fmt.Errorf("authenticated absolute quota required: %w", err)
	}
	budget, err := quota.Budget(q.DailyRemaining, q.MonthlyRemaining, opts.days)
	if err != nil || budget < 1 {
		if err != nil {
			return err
		}
		return quota.ErrExhausted
	}
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	store, err := ingest.NewPostgresStore(db)
	if err != nil {
		return err
	}
	if err = store.InstallQuota(ctx, q); err != nil {
		return fmt.Errorf("quota verification not durable: %w", err)
	}
	symbols, err := loadKBSInvalidHistoryCandidates(ctx, db, opts.start, opts.end, opts.maxCalls)
	if err != nil {
		return err
	}
	if len(symbols) == 0 {
		fmt.Println("KBS invalid-history evidence: no unattempted partial VCI symbols")
		return nil
	}
	if len(symbols) > budget {
		symbols = symbols[:budget]
	}
	pacer, err := quota.NewPacer(q.VerifiedRPM, budget)
	if err != nil {
		return err
	}
	gateway, err := live.New(pacer, func(ctx context.Context, job map[string]any) (worker.Response, error) {
		return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), job)
	})
	if err != nil {
		return err
	}
	quotaReader := func(ctx context.Context) (ingest.QuotaSnapshot, error) { return quotaRead(ctx) }
	completed, failed, err := runKBSInvalidHistoryCandidates(ctx, db, gateway, store, symbols, opts.start, opts.end,
		func(ctx context.Context) error { return ensureFreshQuota(ctx, store, q.VerifiedRPM, quotaReader) })
	if err != nil {
		return err
	}
	fmt.Printf("KBS invalid-history evidence: raw landings=%d settled failures=%d requested symbols=%d range=%s..%s (no core bars written)\n",
		completed, failed, len(symbols), opts.start, opts.end)
	return nil
}

func loadKBSInvalidHistoryCandidates(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, start, end string, limit int) ([]string, error) {
	if db == nil || start == "" || end == "" || start > end || limit < 1 || limit > 5000 {
		return nil, errors.New("invalid KBS invalid-history candidate selection")
	}
	rows, err := db.QueryContext(ctx, `SELECT DISTINCT v.symbol
		FROM ops.ingest_jobs v
	JOIN ops.bar_quality_issues q USING(job_id)
	WHERE v.source='vci' AND v.route='equity_ohlcv'
	  AND v.state='PARTIAL' AND v.date_from=$1::date AND v.date_to=$2::date
	  AND q.category IN ('INVALID_OHLC','INVALID_PRICE')
	  AND NOT EXISTS (
		SELECT 1 FROM ops.ingest_jobs k
		WHERE k.source='kbs' AND k.route='equity_ohlcv' AND k.symbol=v.symbol
		  AND k.date_from=$1::date AND k.date_to=$2::date
	  )
	ORDER BY v.symbol LIMIT $3`, start, end, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var symbols []string
	for rows.Next() {
		var symbol string
		if err = rows.Scan(&symbol); err != nil {
			return nil, err
		}
		symbols = append(symbols, symbol)
	}
	return symbols, rows.Err()
}

func runKBSInvalidHistoryCandidates(ctx context.Context, db interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, gateway *live.Gateway, store *ingest.PostgresStore, symbols []string, start, end string,
	beforeCall func(context.Context) error) (completed, failed int, err error) {
	if db == nil || gateway == nil || store == nil || len(symbols) == 0 || len(symbols) > 5000 || start == "" || end == "" || start > end {
		return 0, 0, errors.New("invalid KBS invalid-history run")
	}
	for _, symbol := range symbols {
		if err = ctx.Err(); err != nil {
			return completed, failed, err
		}
		err = runKBSCrossSourceJobs(ctx, gateway, store, []string{symbol}, start, end, beforeCall)
		if err == nil {
			completed++
			if completed%25 == 0 {
				fmt.Printf("KBS invalid-history progress: raw landings=%d settled failures=%d requested=%d\n", completed, failed, completed+failed)
			}
			continue
		}
		key := fmt.Sprintf("equity_ohlcv:%s:kbs:%s:%s", symbol, start, end)
		var state, errorType string
		var attempts int
		stateErr := db.QueryRowContext(ctx, `SELECT state,attempts,coalesce(last_error_type,'')
			FROM ops.ingest_jobs WHERE idempotency_key=$1`, key).Scan(&state, &attempts, &errorType)
		if errors.Is(stateErr, sql.ErrNoRows) {
			return completed, failed, fmt.Errorf("KBS request for %s stopped before durable reservation: %w", symbol, err)
		}
		if stateErr != nil {
			return completed, failed, fmt.Errorf("inspect KBS request state for %s: %w", symbol, stateErr)
		}
		if attempts < 1 || (state != "PENDING" && state != "BLOCKED" && state != "COMPLETED") {
			return completed, failed, fmt.Errorf("KBS request for %s has unsettled audit state %s: %w", symbol, state, err)
		}
		failed++
		if errorType == "RateLimitedError" || strings.Contains(strings.ToLower(err.Error()), "rate limit") {
			return completed, failed, fmt.Errorf("KBS reported a rate limit; stop after %d raw landings and wait for the provider cooldown", completed)
		}
		if failed%25 == 0 {
			fmt.Printf("KBS invalid-history progress: raw landings=%d settled failures=%d requested=%d\n", completed, failed, completed+failed)
		}
	}
	return completed, failed, nil
}
