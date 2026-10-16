// vnpipe is the offline-first single-user VN-Signal pipeline controller.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/migrate"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

func usage() {
	fmt.Println(`vnpipe (bootstrap) - VN-Signal
Usage:
  vnpipe probe [--active --trading-days N] [--out DIR]
  vnpipe budget --daily N --monthly N --days N --rpm N
  vnpipe validate-bars --input FILE --symbol TICKER
  vnpipe preview-backfill --probe FILE --symbols FILE --from DATE --to DATE --days N
  vnpipe import-listings --probe FILE [--min-symbols N] (offline Postgres import)
  vnpipe backfill --active --probe FILE --symbols FILE --from DATE --to DATE --days N
  vnpipe migrate [--dir sql/migrations] (Postgres-tagged build)
  vnpipe version
Active probe requires verified absolute vnstock usage and tier status.
Unknown/percentage quota readings block active requests; CI always blocks live calls.
Full market-universe ingestion, training, recommendations and the desktop app are NOT implemented.`)
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "vnpipe:", err)
		os.Exit(1)
	}
}
func configPath() string {
	if v := os.Getenv("VNPIPE_CONFIG"); v != "" {
		return v
	}
	for _, candidate := range []string{"config/default.toml", "../config/default.toml"} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return "config/default.toml"
}
func run(args []string) error {
	if len(args) == 0 {
		usage()
		return nil
	}
	switch args[0] {
	case "-h", "--help", "help":
		usage()
		return nil
	case "version":
		fmt.Println("vnpipe bootstrap 0.2.0; no model/recommendations")
		return nil
	case "probe":
		f := flag.NewFlagSet("probe", flag.ContinueOnError)
		active := f.Bool("active", false, "opt in to metered vnstock route calls")
		remainingDays := f.Int("trading-days", 0, "remaining trading days in this month, mandatory for active probe")
		out := f.String("out", filepath.Join("..", "docs", "probe"), "report directory")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) != 0 {
			return errors.New("unexpected arguments")
		}
		if _, err := config.Load(configPath()); err != nil {
			return fmt.Errorf("invalid config: %w", err)
		}
		if *active && os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
			return live.ErrDisabled
		}
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		// Passive status and usage have no market-data route; they do not consume
		// the account's quote quota. Python direct active probe is disabled.
		result, err := worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), map[string]any{"id": "local-probe", "op": "probe", "active": false})
		if err != nil {
			return err
		}
		if !result.OK {
			return fmt.Errorf("worker probe error: %+v", result.Error)
		}
		var report map[string]json.RawMessage
		if err := json.Unmarshal(result.Data, &report); err != nil {
			return err
		}
		if *active {
			if *remainingDays < 1 || *remainingDays > 31 {
				return errors.New("active probe requires 1..31 remaining trading days")
			}
			daily, monthly, e := quota.ParseRemaining(report["usage"])
			if e != nil {
				return fmt.Errorf("cannot meter live probe: %w", e)
			}
			rpm, e := quota.TierRPM(report["status"])
			if e != nil {
				return fmt.Errorf("cannot verify tier rate: %w", e)
			}
			budget, e := quota.Budget(daily, monthly, *remainingDays)
			if e != nil {
				return e
			}
			requests := []map[string]any{
				{"op": "equity_list"}, {"op": "equity_ohlcv", "symbol": "FPT", "start": "2016-01-01", "end": time.Now().Format("2006-01-02")},
				{"op": "index_ohlcv", "symbol": "VNINDEX", "start": "2016-01-01", "end": time.Now().Format("2006-01-02")},
				{"op": "income_statement", "symbol": "FPT", "period": "quarter"},
				{"op": "balance_sheet", "symbol": "FPT", "period": "quarter"},
				{"op": "cash_flow", "symbol": "FPT", "period": "quarter"}, {"op": "market_calendar"},
			}
			if budget < len(requests) {
				return fmt.Errorf("insufficient conservative budget %d for %d probe calls", budget, len(requests))
			}
			pacer, e := quota.NewPacer(rpm, budget)
			if e != nil {
				return e
			}
			gateway, e := live.New(pacer, func(ctx context.Context, job map[string]any) (worker.Response, error) {
				return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), job)
			})
			if e != nil {
				return e
			}
			summary := make(map[string]any)
			for i, job := range requests {
				op := job["op"].(string)
				job["id"] = fmt.Sprintf("probe-%02d", i)
				resp, e := gateway.Call(ctx, job)
				if e != nil {
					summary[op] = map[string]any{"available": false, "error_type": "WorkerOrGatewayError"}
					continue
				}
				if !resp.OK {
					summary[op] = map[string]any{"available": false, "error_type": resp.Error.Type}
					continue
				}
				var payload struct {
					Count      int              `json:"count"`
					Columns    []string         `json:"columns"`
					Rows       []map[string]any `json:"rows"`
					Attributes map[string]any   `json:"attributes"`
				}
				if e := json.Unmarshal(resp.Data, &payload); e != nil {
					summary[op] = map[string]any{"available": false, "error_type": "InvalidRouteFrame"}
					continue
				}
				dates := make([]string, 0, len(payload.Rows))
				for _, row := range payload.Rows {
					for _, key := range []string{"time", "date"} {
						if s, ok := row[key].(string); ok && s != "" {
							dates = append(dates, s)
							break
						}
					}
				}
				first, last := "", ""
				for _, d := range dates {
					if first == "" || d < first {
						first = d
					}
					if d > last {
						last = d
					}
				}
				// Preserve the SAME metered equity-list response for a later offline,
				// transactional import. No second vendor request is needed.
				if op == "equity_list" && payload.Count > 0 {
					report["listing_frame"] = append(json.RawMessage(nil), resp.Data...)
				}
				summary[op] = map[string]any{"available": payload.Count > 0, "count": payload.Count, "columns": payload.Columns, "first_observed_date": first, "last_observed_date": last, "attributes": payload.Attributes}
			}
			report["active"] = json.RawMessage("true")
			encoded, _ := json.Marshal(summary)
			report["routes"] = encoded
		}
		if err := os.MkdirAll(*out, 0700); err != nil {
			return err
		}
		name := filepath.Join(*out, time.Now().Format("2006-01-02")+".json")
		pretty, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			return err
		}
		if err := os.WriteFile(name, append(pretty, '\n'), 0600); err != nil {
			return err
		}
		fmt.Printf("Probe report: %s (active=%v). Does NOT certify entitlements.\n", name, *active)
		return nil
	case "migrate":
		f := flag.NewFlagSet("migrate", flag.ContinueOnError)
		dir := f.String("dir", "sql/migrations", "numbered migrations folder")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) != 0 {
			return errors.New("unexpected migration arguments")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
		if err != nil {
			return err
		}
		defer db.Close()
		count, err := migrate.Apply(ctx, db, *dir)
		if err != nil {
			return err
		}
		fmt.Printf("PostgreSQL migrations applied: %d (existing checked by SHA-256)\n", count)
		return nil
	case "import-listings":
		return runImportListings(args[1:])
	case "backfill":
		return runBackfill(args[1:])
	case "preview-backfill":
		f := flag.NewFlagSet("preview-backfill", flag.ContinueOnError)
		probeFile := f.String("probe", "", "locally recorded active probe report")
		symbolFile := f.String("symbols", "", "JSON array of current listed symbols (not a live call)")
		start := f.String("from", "", "earliest requested history YYYY-MM-DD")
		end := f.String("to", "", "latest requested history YYYY-MM-DD")
		days := f.Int("days", 0, "remaining trading sessions this month")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if *probeFile == "" || *symbolFile == "" || len(f.Args()) != 0 {
			return errors.New("--probe and --symbols are required")
		}
		if _, err := config.Load(configPath()); err != nil {
			return err
		}
		probe, err := os.ReadFile(*probeFile)
		if err != nil {
			return err
		}
		raw, err := os.ReadFile(*symbolFile)
		if err != nil {
			return err
		}
		var symbols []string
		if err := json.Unmarshal(raw, &symbols); err != nil {
			return err
		}
		p, err := ingest.PlanBackfill(probe, *days, *start, *end, symbols, nil)
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(p)
	case "validate-bars":
		f := flag.NewFlagSet("validate-bars", flag.ContinueOnError)
		input := f.String("input", "", "saved, successful Python worker data frame JSON")
		symbol := f.String("symbol", "", "ticker to bind to all parsed rows")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if *input == "" || *symbol == "" || len(f.Args()) != 0 {
			return errors.New("--input and --symbol are required")
		}
		file, err := os.Open(*input)
		if err != nil {
			return err
		}
		defer file.Close()
		raw, err := io.ReadAll(io.LimitReader(file, 10*1024*1024+1))
		if err != nil {
			return err
		}
		result, err := ingest.NormalizeBars(*symbol, raw)
		if err != nil {
			return err
		}
		// Do not print full historical price data: output only safe validation summary.
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"symbol": result.Symbol, "rows": result.Count, "first_date": result.FirstDate, "last_date": result.LastDate, "validation": "passed"})
	case "budget":
		f := flag.NewFlagSet("budget", flag.ContinueOnError)
		daily := f.Int("daily", -1, "absolute daily calls remaining")
		monthly := f.Int("monthly", -1, "absolute monthly calls remaining")
		days := f.Int("days", -1, "trading days remaining")
		rpm := f.Int("rpm", 0, "verified tier RPM")
		if err := f.Parse(args[1:]); err != nil {
			return err
		}
		if len(f.Args()) > 0 {
			return errors.New("unexpected arguments")
		}
		if _, err := config.Load(configPath()); err != nil {
			return fmt.Errorf("invalid config: %w", err)
		}
		b, err := quota.Budget(*daily, *monthly, *days)
		if err != nil {
			return err
		}
		if *rpm != 20 && *rpm != 60 {
			return errors.New("unknown free-tier RPM; expected verified 20 or 60")
		}
		if _, err := quota.NewPacer(*rpm, b); err != nil {
			return err
		}
		fmt.Printf("Maximum planned calls today: %d; pacing 85%% of %d verified req/min\n", b, *rpm)
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}
