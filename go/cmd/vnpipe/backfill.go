package main

import (
	"context"
	"encoding/json"
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

// backfill is intentionally an explicit, single-machine command. No automatic
// nightly run is enabled until the Phase-1 and Phase-6 exit tests are green.
func runBackfill(args []string) error {
	f := flag.NewFlagSet("backfill", flag.ContinueOnError)
	approve := f.Bool("active", false, "explicitly authorize account-metered vendor calls")
	reportFile := f.String("probe", "", "active verified vnstock capability report")
	symbolsFile := f.String("symbols", "", "JSON array of symbols already present in core.symbols")
	start := f.String("from", "", "earliest ISO trade date")
	end := f.String("to", "", "latest ISO trade date")
	days := f.Int("days", 0, "remaining market sessions in calendar month")
	source := f.String("source", "vci", "supported vnstock OHLCV source")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || !*approve || *reportFile == "" || *symbolsFile == "" {
		return errors.New("backfill requires --active --probe and --symbols; market calls are never implicit")
	}
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return live.ErrDisabled
	}
	if *source != "vci" {
		return errors.New("only probe-verified vci source is currently supported")
	}
	if _, err := config.Load(configPath()); err != nil {
		return err
	}
	saved, err := os.ReadFile(*reportFile)
	if err != nil {
		return err
	}
	var probe struct {
		At     string `json:"at"`
		Active bool   `json:"active"`
	}
	if err = json.Unmarshal(saved, &probe); err != nil {
		return err
	}
	stamp, err := time.Parse(time.RFC3339Nano, probe.At)
	if err != nil || !probe.Active || time.Since(stamp) > 24*time.Hour || time.Until(stamp) > time.Minute {
		return ingest.ErrUnverified
	}
	raw, err := os.ReadFile(*symbolsFile)
	if err != nil {
		return err
	}
	var symbols []string
	if err = json.Unmarshal(raw, &symbols); err != nil {
		return err
	}
	plan, err := ingest.PlanBackfill(saved, *days, *start, *end, symbols, nil)
	if err != nil {
		return err
	}
	if len(plan.Planned) == 0 {
		return errors.New("nothing budgeted for this run")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Hour)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	// No live call is permitted until all symbols have validated listing rows.
	for _, job := range plan.Planned {
		var known bool
		err = db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM core.symbols WHERE symbol=$1)`, job.Symbol).Scan(&known)
		if err != nil {
			return fmt.Errorf("PostgreSQL schema/listing preflight: %w", err)
		}
		if !known {
			return fmt.Errorf("no verified listing for %s: ingest listings before bars", job.Symbol)
		}
	}
	// Passive status/usage (no market-data route) is the only source for a new
	// quota allowance; report percentages / unknown fields block entirely.
	passive, err := worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), map[string]any{"id": "backfill-preflight", "op": "probe", "active": false})
	if err != nil {
		return err
	}
	if !passive.OK {
		return errors.New("fresh vnstock quota preflight failed")
	}
	var cap struct{ Status, Usage json.RawMessage }
	if err = json.Unmarshal(passive.Data, &cap); err != nil {
		return err
	}
	daily, monthly, err := quota.ParseRemaining(cap.Usage)
	if err != nil {
		return err
	}
	rpm, err := quota.TierRPM(cap.Status)
	if err != nil {
		return err
	}
	fresh, err := quota.Budget(daily, monthly, *days)
	if err != nil {
		return err
	}
	if fresh < 1 {
		return quota.ErrExhausted
	}
	if len(plan.Planned) > fresh {
		plan.Planned = plan.Planned[:fresh]
	}
	store, err := ingest.NewPostgresStore(db)
	if err != nil {
		return err
	}
	if err := store.InstallQuota(ctx, ingest.QuotaSnapshot{
		DailyRemaining: daily, MonthlyRemaining: monthly, TradingDaysRemaining: *days,
		VerifiedRPM: rpm, ObservedAt: time.Now().UTC().Add(-time.Millisecond),
	}); err != nil {
		return fmt.Errorf("quota verification not durable: %w", err)
	}
	pacer, err := quota.NewPacer(rpm, fresh)
	if err != nil {
		return err
	}
	gateway, err := live.New(pacer, func(ctx context.Context, job map[string]any) (worker.Response, error) {
		return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), job)
	})
	if err != nil {
		return err
	}
	runner := ingest.Runner{Gateway: gateway, Store: store, Now: time.Now}
	summary, err := runner.RunBarsBackfill(ctx, plan.Planned, *source)
	fmt.Printf("Backfill: committed=%d skipped=%d deferred=%d (latest snapshot untouched)\n", summary.Committed, summary.Skipped, len(plan.Deferred))
	return err
}
