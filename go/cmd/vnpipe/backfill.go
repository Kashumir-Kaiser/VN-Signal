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

// backfill is intentionally a single-machine command. The Windows scheduled
// wrapper starts it only after a fresh active route probe and local DB check.
func runBackfill(args []string) error {
	f := flag.NewFlagSet("backfill", flag.ContinueOnError)
	approve := f.Bool("active", false, "explicitly authorize account-metered vendor calls")
	reportFile := f.String("probe", "", "active verified vnstock capability report")
	start := f.String("from", "", "earliest ISO trade date")
	end := f.String("to", "", "latest ISO trade date")
	days := f.Int("days", 0, "remaining market sessions in calendar month")
	source := f.String("source", "vci", "supported vnstock OHLCV source")
	maxCalls := f.Int("max-calls", 20, "maximum metered OHLCV calls in this run")
	rotateDaily := f.Bool("rotate-daily", false, "round-robin quota-capped symbols across daily runs")
	retryLegacy := f.Bool("retry-legacy-invalid", false, "explicitly re-request previously invalid unarchived frames")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || !*approve || *reportFile == "" || *maxCalls < 1 || *maxCalls > 100000 {
		return errors.New("backfill requires --active and --probe; candidates come only from a verified PostgreSQL listing snapshot")
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
	ignored, err := loadIgnoredSymbols()
	if err != nil {
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Hour)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	// Do not trust an arbitrary user-supplied ticker list or scan all historical
	// symbols: only the latest verified full listing is eligible. Completed jobs
	// are removed BEFORE the call budget is applied, avoiding repeat starvation.
	universe, err := ingest.LoadVerifiedBackfillUniverseWithPolicy(ctx, db, time.Now(), *start, *end, *source, *retryLegacy)
	if err != nil {
		return fmt.Errorf("verified PostgreSQL universe: %w", err)
	}
	var excluded int
	universe.Pending, excluded = filterIgnoredSymbols(universe.Pending, ignored)
	if excluded > 0 {
		fmt.Printf("Backfill: %d user-ignored tickers excluded before quota planning\n", excluded)
	}
	if universe.DeferredInvalid > 0 {
		fmt.Printf("Backfill: %d prior unarchived InvalidFrame jobs deferred (0 retry calls)\n", universe.DeferredInvalid)
	}
	if len(universe.Pending) == 0 {
		fmt.Printf("No eligible backfill jobs: snapshot=%s total=%d completed=%d partial=%d blocked=%d leased=%d\n",
			universe.AsOf, universe.Total, universe.Completed, universe.Partial, universe.Blocked, universe.Leased)
		return nil
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
	rpm, err := quota.TierRPM(cap.Status, cap.Usage)
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
	// Rebuild the plan from FRESH absolute account usage. The saved active
	// probe establishes route availability, not today's spendable allowance.
	var report map[string]json.RawMessage
	if err := json.Unmarshal(saved, &report); err != nil {
		return err
	}
	report["status"], report["usage"] = cap.Status, cap.Usage
	currentReport, err := json.Marshal(report)
	if err != nil {
		return err
	}
	rotationOffset := 0
	if *rotateDaily && len(universe.Pending) > 0 {
		runCap := fresh
		if *maxCalls < runCap {
			runCap = *maxCalls
		}
		loc := time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)
		dayIndex := time.Now().In(loc).Unix() / int64((24 * time.Hour).Seconds())
		rotationOffset = int((dayIndex * int64(runCap)) % int64(len(universe.Pending)))
		fmt.Printf("Daily refresh rotation: offset=%d candidates=%d per-run-cap=%d\n", rotationOffset, len(universe.Pending), runCap)
	}
	plan, err := ingest.PlanBackfillWithOffset(currentReport, *days, *start, *end, universe.Pending, nil, rotationOffset)
	if err != nil {
		return err
	}
	if len(plan.Planned) == 0 {
		return quota.ErrExhausted
	}
	if len(plan.Planned) > fresh {
		plan.Deferred = append(plan.Planned[fresh:], plan.Deferred...)
		plan.Planned = plan.Planned[:fresh]
	}
	plan = capBackfillCalls(plan, *maxCalls)
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
	// Long historical runs may outlive the five-minute verification window.
	// Refresh only on demand, using a new passive CLI report, before reserving
	// another market-data request. This never permits unverified capacity or
	// a different tier to silently alter the already configured pacer.
	reader := func(ctx context.Context) (ingest.QuotaSnapshot, error) {
		return observeAbsoluteQuota(ctx, *days, func(ctx context.Context, request map[string]any) (worker.Response, error) {
			return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), request)
		})
	}
	runner := ingest.Runner{
		Gateway: gateway, Store: store, Now: time.Now,
		BeforeCall: func(ctx context.Context) error {
			return ensureFreshQuota(ctx, store, rpm, reader)
		},
	}
	summary, err := runner.RunBarsBackfill(ctx, plan.Planned, *source)
	fmt.Printf("Backfill: snapshot=%s universe=%d completed_before=%d committed=%d empty_source_responses=%d partial_now=%d zero_volume_unverified_rows=%d invalid_traded_rows=%d quarantined_frames=%d skipped=%d blocked_before=%d partial_before=%d leased=%d deferred=%d quarantine_preview=%q (serving snapshot untouched)\n",
		universe.AsOf, universe.Total, universe.Completed, summary.Committed, summary.EmptyResponses, summary.Partial, summary.ZeroVolume, summary.InvalidTraded, summary.Blocked, summary.Skipped, universe.Blocked, universe.Partial, universe.Leased, len(plan.Deferred), summary.BlockedPreview)
	return err
}

// Cap actual batch calls after the verified quota plan. Preserve the
// unattempted tail in the deferred count.
func capBackfillCalls(p ingest.Plan, maxCalls int) ingest.Plan {
	if len(p.Planned) <= maxCalls {
		return p
	}
	p.Deferred = append(p.Planned[maxCalls:], p.Deferred...)
	p.Planned = p.Planned[:maxCalls]
	return p
}
