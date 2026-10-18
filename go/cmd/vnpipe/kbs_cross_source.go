package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type kbsCrossSourceOptions struct {
	active     bool
	start      string
	end        string
	sampleDate string
	days       int
	maxCalls   int
}

func parseKBSCrossSourceArgs(args []string) (kbsCrossSourceOptions, error) {
	var out kbsCrossSourceOptions
	f := flag.NewFlagSet("ingest-kbs-cross-source", flag.ContinueOnError)
	f.BoolVar(&out.active, "active", false, "explicitly authorize account-metered KBS calls")
	f.StringVar(&out.start, "from", "", "earliest ISO trade date")
	f.StringVar(&out.end, "to", "", "latest ISO trade date")
	f.StringVar(&out.sampleDate, "sample-date", "", "Tier A/VCI date used to select symbols (defaults to --to)")
	f.IntVar(&out.days, "days", 0, "remaining trading days in calendar month")
	f.IntVar(&out.maxCalls, "max-calls", 1, "maximum metered calls (1-30)")
	if err := f.Parse(args); err != nil {
		return out, err
	}
	if len(f.Args()) != 0 || !out.active || out.maxCalls < 1 || out.maxCalls > 30 || out.days < 1 || out.days > 31 {
		return out, errors.New("ingest-kbs-cross-source requires --active --from DATE --to DATE --days N; --max-calls must be 1..30")
	}
	from, err := time.Parse("2006-01-02", out.start)
	if err != nil || from.Format("2006-01-02") != out.start {
		return out, errors.New("--from must be an ISO date")
	}
	to, err := time.Parse("2006-01-02", out.end)
	if err != nil || to.Format("2006-01-02") != out.end || out.start > out.end {
		return out, errors.New("--to must be an ISO date on or after --from")
	}
	if out.sampleDate == "" {
		out.sampleDate = out.end
	}
	sampleDate, err := time.Parse("2006-01-02", out.sampleDate)
	if err != nil || sampleDate.Format("2006-01-02") != out.sampleDate || out.sampleDate < out.start || out.sampleDate > out.end {
		return out, errors.New("--sample-date must be a valid ISO date within --from..--to")
	}
	return out, nil
}

// runKBSCrossSource archives a small, explicitly authorized KBS comparison
// sample. Its candidates are derived only from positive-volume VCI bars in the
// requested interval; the KBS response is raw-only and never promoted to core.
func runKBSCrossSource(args []string) error {
	opts, err := parseKBSCrossSourceArgs(args)
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
	if err != nil { // authenticated absolute quota is mandatory; fail closed
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
	candidates, err := loadKBSCrossSourceCandidates(ctx, db, opts.sampleDate, opts.start, opts.end, opts.maxCalls)
	if err != nil {
		return err
	}
	if len(candidates) == 0 {
		fmt.Println("KBS cross-source: no unattempted positive-volume VCI candidates in requested range")
		return nil
	}
	if len(candidates) > budget {
		candidates = candidates[:budget]
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
	if err = runKBSCrossSourceJobs(ctx, gateway, store, candidates, opts.start, opts.end,
		func(ctx context.Context) error { return ensureFreshQuota(ctx, store, q.VerifiedRPM, quotaReader) }); err != nil {
		return err
	}
	fmt.Printf("KBS cross-source: raw landings=%d source=vci→kbs range=%s..%s (no core bars written)\n", len(candidates), opts.start, opts.end)
	return nil
}

// Candidates must have an actual positive-volume VCI observation during the
// explicit range, belong to the active security master, and have no prior KBS
// attempt for that exact range. No ticker input is accepted from the caller.
func loadKBSCrossSourceCandidates(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, sampleDate, start, end string, limit int) ([]string, error) {
	if db == nil || sampleDate == "" || start == "" || end == "" || start > sampleDate || sampleDate > end || limit < 1 || limit > 30 {
		return nil, errors.New("invalid KBS candidate selection")
	}
	rows, err := db.QueryContext(ctx, `SELECT s.symbol
		FROM ops.dq_tier_a_symbols u
		JOIN core.symbols s USING(symbol_id)
		JOIN core.bars_daily b ON b.symbol_id=s.symbol_id AND b.trade_date=$1::date
		WHERE u.trade_date=$1::date AND b.source='vci' AND b.v>0
		  AND s.active=true
		  AND NOT EXISTS (
			SELECT 1 FROM ops.ingest_jobs j
			WHERE j.source='kbs' AND j.route='equity_ohlcv' AND j.symbol=s.symbol
			  AND j.date_from=$2::date AND j.date_to=$3::date
		  )
		GROUP BY s.symbol
		ORDER BY s.symbol LIMIT $4`, sampleDate, start, end, limit)
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

func runKBSCrossSourceJobs(ctx context.Context, gateway *live.Gateway, store *ingest.PostgresStore,
	symbols []string, start, end string, beforeCall func(context.Context) error) error {
	if gateway == nil || store == nil || len(symbols) == 0 || len(symbols) > 30 || start == "" || end == "" || start > end {
		return errors.New("invalid KBS cross-source run")
	}
	for _, symbol := range symbols {
		if err := ctx.Err(); err != nil {
			return err
		}
		job := ingest.BackfillJob{Route: "equity_ohlcv", Symbol: symbol, Start: start, End: end}
		key := fmt.Sprintf("equity_ohlcv:%s:kbs:%s:%s", symbol, start, end)
		if beforeCall != nil {
			if err := beforeCall(ctx); err != nil {
				return fmt.Errorf("pre-call quota verification: %w", err)
			}
		}
		reply, err := gateway.CallRecorded(ctx, map[string]any{
			"id": key, "op": "equity_ohlcv", "symbol": symbol, "start": start, "end": end, "source": "kbs",
		}, live.CallAudit{
			Reserve: func(ctx context.Context, at time.Time) (time.Time, error) {
				return store.ReserveAttempt(ctx, job, key, "kbs", at)
			},
			Dispatch: func(ctx context.Context) error { return store.MarkDispatch(ctx, key) },
			Finish: func(ctx context.Context, outcome, reason string) error {
				return store.MarkOutcome(ctx, key, outcome, reason)
			},
		})
		if err != nil {
			return fmt.Errorf("KBS gateway for %s: %w", symbol, err)
		}
		if reply.ID != key {
			_ = store.BlockInvalid(ctx, key, "ResponseIDMismatch")
			return errors.New("KBS response ID mismatch")
		}
		if !reply.OK {
			if reply.Error == nil {
				return errors.New("KBS vendor error without type")
			}
			if reply.Error.Cause != "" {
				return fmt.Errorf("KBS route failed for %s: %s (cause: %s)", symbol, reply.Error.Type, reply.Error.Cause)
			}
			return fmt.Errorf("KBS route failed for %s: %s", symbol, reply.Error.Type)
		}
		frame, err := ingest.AnalyzeMarketBarsForSource(symbol, "kbs", reply.Data)
		if err != nil {
			_ = store.BlockInvalid(ctx, key, "InvalidKBSFrame")
			return fmt.Errorf("invalid KBS frame for %s: %w", symbol, err)
		}
		if frame.FirstDate < start || frame.LastDate > end {
			_ = store.BlockInvalid(ctx, key, "OutsideRequestedRange")
			return fmt.Errorf("KBS frame for %s outside requested range", symbol)
		}
		digest := sha256.Sum256(reply.Data)
		landing := ingest.Landing{JobID: key, Source: "kbs", FetchedAt: time.Now().UTC(),
			SHA256: hex.EncodeToString(digest[:]), Raw: append([]byte(nil), reply.Data...), Bars: frame.Bars}
		if _, err = store.CommitCrossSourceLanding(ctx, ingest.MarketLanding{Landing: landing, Frame: frame}); err != nil {
			return fmt.Errorf("KBS raw landing for %s: %w", symbol, err)
		}
	}
	return nil
}
