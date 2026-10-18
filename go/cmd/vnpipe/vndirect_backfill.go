package main

import (
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/vndirect"
)

type vndirectBackfillOptions struct {
	active      bool
	start       string
	end         string
	symbols     string
	maxCalls    int
	pace        time.Duration
	retryFailed bool
	shardIndex  int
	shardCount  int
}

func parseVNDIRECTBackfillArgs(args []string) (vndirectBackfillOptions, error) {
	var out vndirectBackfillOptions
	f := flag.NewFlagSet("backfill-vndirect", flag.ContinueOnError)
	f.BoolVar(&out.active, "active", false, "explicitly authorize public VNDIRECT historical requests")
	f.StringVar(&out.start, "from", "", "earliest history date (YYYY-MM-DD)")
	f.StringVar(&out.end, "to", "", "latest history date (YYYY-MM-DD)")
	f.StringVar(&out.symbols, "symbols", "", "comma-separated symbols; default is every known symbol")
	f.IntVar(&out.maxCalls, "max-calls", 2000, "maximum audited requests (1-2000)")
	f.DurationVar(&out.pace, "pace", 500*time.Millisecond, "minimum delay between provider requests (100ms-10s)")
	f.BoolVar(&out.retryFailed, "retry-failed", false, "allow a fresh audited attempt for prior noncompleted jobs")
	f.IntVar(&out.shardIndex, "shard-index", 0, "zero-based deterministic universe shard")
	f.IntVar(&out.shardCount, "shard-count", 1, "number of deterministic universe shards (1-16)")
	if err := f.Parse(args); err != nil {
		return out, err
	}
	if len(f.Args()) != 0 || !out.active || out.maxCalls < 1 || out.maxCalls > 2000 ||
		out.pace < 100*time.Millisecond || out.pace > 10*time.Second ||
		out.shardCount < 1 || out.shardCount > 16 || out.shardIndex < 0 || out.shardIndex >= out.shardCount {
		return out, errors.New("backfill-vndirect requires --active --from DATE --to DATE; max-calls must be 1..2000, pace 100ms..10s, and shard-index/count must be valid")
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
	if out.symbols != "" {
		seen := map[string]bool{}
		for _, raw := range strings.Split(out.symbols, ",") {
			symbol := strings.ToUpper(strings.TrimSpace(raw))
			if !validDNSESymbol(symbol) || seen[symbol] {
				return out, errors.New("--symbols must be a comma-separated list of unique tickers")
			}
			seen[symbol] = true
		}
		if len(seen) > out.maxCalls {
			return out, errors.New("--symbols contains more entries than --max-calls")
		}
		out.symbols = strings.Join(sortedKeys(seen), ",")
	}
	return out, nil
}

func runVNDIRECTBackfill(args []string) error {
	opts, err := parseVNDIRECTBackfillArgs(args)
	if err != nil {
		return err
	}
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return live.ErrDisabled
	}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Hour)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	store, err := ingest.NewPostgresStore(db)
	if err != nil {
		return err
	}
	symbols, err := loadVNDIRECTSymbols(ctx, db, opts.symbols, opts.maxCalls)
	if err != nil {
		return err
	}
	ignored, err := loadIgnoredSymbols()
	if err != nil {
		return err
	}
	var excluded int
	symbols, excluded = filterIgnoredSymbols(symbols, ignored)
	if excluded > 0 {
		fmt.Printf("VNDIRECT historical backfill: skipped %d user-excluded tickers\n", excluded)
	}
	sharded := make([]string, 0, (len(symbols)+opts.shardCount-1)/opts.shardCount)
	for i, symbol := range symbols {
		if i%opts.shardCount == opts.shardIndex {
			sharded = append(sharded, symbol)
		}
	}
	if len(sharded) == 0 {
		fmt.Println("VNDIRECT historical backfill: no symbols selected")
		return nil
	}
	client := vndirect.NewClient()
	completed, partial, empty, failed, skipped, traded, noTrade := 0, 0, 0, 0, 0, 0, 0
	limited := false
	for i, symbol := range sharded {
		if err = ctx.Err(); err != nil {
			return err
		}
		if i > 0 {
			timer := time.NewTimer(opts.pace)
			select {
			case <-ctx.Done():
				timer.Stop()
				return ctx.Err()
			case <-timer.C:
			}
		}
		requestURL, urlErr := client.RequestURL(symbol, opts.start, opts.end)
		if urlErr != nil {
			return urlErr
		}
		call, beginErr := store.BeginExternalMarketCall(ctx, "vndirect", symbol, opts.start, opts.end, requestURL, opts.retryFailed)
		if beginErr != nil {
			if errors.Is(beginErr, ingest.ErrJobCompleted) || errors.Is(beginErr, ingest.ErrJobBlocked) || errors.Is(beginErr, ingest.ErrInFlight) || strings.Contains(beginErr.Error(), "retry requires") {
				skipped++
				continue
			}
			return fmt.Errorf("begin audited VNDIRECT call for %s: %w", symbol, beginErr)
		}
		history, fetchErr := client.FetchHistory(ctx, symbol, opts.start, opts.end)
		fetchedAt := time.Now().UTC()
		if fetchErr != nil {
			rateLimited := history.HTTPStatus == http.StatusTooManyRequests
			errorType := "ProviderFailure"
			if rateLimited {
				errorType, limited = "RateLimited", true
			} else if history.HTTPStatus >= 200 && history.HTTPStatus < 300 {
				errorType = "InvalidProviderFrame"
				fmt.Printf("VNDIRECT frame rejected: symbol=%s status=%d detail=%s\n", symbol, history.HTTPStatus, fetchErr.Error())
			}
			if failErr := store.FailExternalMarketCall(ctx, call, history.HTTPStatus, history.Raw, errorType, rateLimited); failErr != nil {
				return fmt.Errorf("persist VNDIRECT failure for %s: %w", symbol, failErr)
			}
			failed++
		} else {
			summary, commitErr := store.CommitVNDIRECTHistory(ctx, call, fetchedAt, history)
			if commitErr != nil {
				if failErr := store.FailExternalMarketCall(ctx, call, history.HTTPStatus, history.Raw, "CommitValidationFailure", false); failErr != nil {
					return fmt.Errorf("VNDIRECT commit failed (%v) and failure audit failed: %w", commitErr, failErr)
				}
				failed++
			} else {
				traded += summary.Traded
				noTrade += summary.NoTrade
				switch summary.State {
				case "COMPLETED":
					completed++
				case "PARTIAL":
					partial++
				case "BLOCKED":
					empty++
				}
			}
		}
		if (completed+partial+empty+failed)%25 == 0 {
			fmt.Printf("VNDIRECT progress: completed=%d partial=%d traded_rows=%d zero_volume_rows=%d empty=%d failed=%d skipped=%d/%d\n", completed, partial, traded, noTrade, empty, failed, skipped, len(sharded))
		}
		if limited {
			break
		}
	}
	fmt.Printf("VNDIRECT historical backfill: completed=%d partial=%d traded_rows=%d zero_volume_rows=%d empty=%d failed=%d skipped=%d selected=%d shard=%d/%d range=%s..%s source=vndirect\n",
		completed, partial, traded, noTrade, empty, failed, skipped, len(sharded), opts.shardIndex, opts.shardCount, opts.start, opts.end)
	if limited {
		return errors.New("VNDIRECT rate limit recorded; stopped the batch to honor the provider cooldown")
	}
	return nil
}

func loadVNDIRECTSymbols(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
}, requested string, limit int) ([]string, error) {
	if db == nil || limit < 1 || limit > 2000 {
		return nil, errors.New("invalid VNDIRECT symbol selection")
	}
	if requested == "" {
		rows, err := db.QueryContext(ctx, `SELECT symbol FROM core.symbols ORDER BY symbol LIMIT $1`, limit)
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
	var symbols []string
	for _, symbol := range strings.Split(requested, ",") {
		var exists bool
		if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM core.symbols WHERE symbol=$1)`, symbol).Scan(&exists); err != nil {
			return nil, err
		}
		if !exists {
			return nil, fmt.Errorf("VNDIRECT symbol %s is not in the local security master", symbol)
		}
		symbols = append(symbols, symbol)
	}
	return symbols, nil
}
