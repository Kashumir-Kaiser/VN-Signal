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

// runIndexBackfill requires a fresh registered-device VNINDEX probe for the
// explicitly selected provider.
func runIndexBackfill(args []string) error {
	f := flag.NewFlagSet("backfill-index", flag.ContinueOnError)
	active := f.Bool("active", false, "authorize one account-metered request")
	probePath := f.String("probe", "", "saved active capability report")
	source := f.String("source", "kbs", "index data provider validated by the saved probe: kbs or vci")
	start := f.String("from", "2016-01-01", "earliest ISO trade date")
	end := f.String("to", "", "latest ISO trade date")
	days := f.Int("days", 0, "remaining market sessions in calendar month")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || !*active || *probePath == "" || *end == "" || *days < 1 || *days > 31 || (*source != "kbs" && *source != "vci") {
		return errors.New("backfill-index requires --active --probe FILE --to DATE --days N")
	}
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return live.ErrDisabled
	}
	if _, err := config.Load(configPath()); err != nil {
		return err
	}
	saved, err := os.ReadFile(*probePath)
	if err != nil {
		return err
	}
	if err = validateIndexProbe(saved, time.Now(), *source); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Minute)
	defer cancel()
	quotaRead := func(ctx context.Context) (ingest.QuotaSnapshot, error) {
		return readAuthenticatedIndexQuota(ctx, *days)
	}
	q, err := quotaRead(ctx)
	if err != nil {
		return err
	}
	budget, err := quota.Budget(q.DailyRemaining, q.MonthlyRemaining, *days)
	if err != nil {
		return err
	}
	if budget < 1 {
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
	pacer, err := quota.NewPacer(q.VerifiedRPM, 1)
	if err != nil {
		return err
	}
	gateway, err := live.New(pacer, func(ctx context.Context, job map[string]any) (worker.Response, error) {
		return worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), job)
	})
	if err != nil {
		return err
	}
	runner := ingest.Runner{Gateway: gateway, Store: store, Now: time.Now, BeforeCall: func(ctx context.Context) error { return ensureFreshQuota(ctx, store, q.VerifiedRPM, quotaRead) }}
	summary, err := runner.RunIndexBackfill(ctx, []ingest.BackfillJob{{Route: "index_ohlcv", Symbol: "VNINDEX", Source: *source, Start: *start, End: *end}})
	fmt.Printf("Index backfill: symbol=VNINDEX source=%s committed=%d skipped=%d (one-call cap)\n", *source, summary.Committed, summary.Skipped)
	return err
}

func validateIndexProbe(raw []byte, now time.Time, source string) error {
	var p struct {
		At     string `json:"at"`
		Active bool   `json:"active"`
		Routes map[string]struct {
			Available  bool     `json:"available"`
			Columns    []string `json:"columns"`
			Attributes struct {
				Route  string `json:"route"`
				Source string `json:"source"`
			} `json:"attributes"`
		} `json:"routes"`
	}
	if err := json.Unmarshal(raw, &p); err != nil {
		return err
	}
	at, err := time.Parse(time.RFC3339Nano, p.At)
	if err != nil || !p.Active || now.Sub(at) > 24*time.Hour || at.After(now.Add(time.Minute)) {
		return ingest.ErrUnverified
	}
	r, ok := p.Routes["index_ohlcv"]
	if !ok || !r.Available || r.Attributes.Route != "market.index.ohlcv" || r.Attributes.Source != source {
		return ingest.ErrUnverified
	}
	want := map[string]bool{"time": false, "open": false, "high": false, "low": false, "close": false, "volume": false}
	for _, c := range r.Columns {
		if _, ok := want[c]; ok {
			want[c] = true
		}
	}
	for _, ok := range want {
		if !ok {
			return ingest.ErrUnverified
		}
	}
	return nil
}

func readAuthenticatedIndexQuota(ctx context.Context, days int) (ingest.QuotaSnapshot, error) {
	reply, err := worker.Invoke(ctx, worker.Python(), worker.ScriptPath(), map[string]any{"id": "index-quota-preflight", "op": "probe", "active": false})
	if err != nil {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota probe worker failed: %w", err)
	}
	if !reply.OK {
		cause := "unknown worker error"
		if reply.Error != nil && reply.Error.Type != "" {
			cause = reply.Error.Type
		}
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota probe returned %s: %w", cause, quota.ErrUnknown)
	}
	var p struct {
		Status json.RawMessage `json:"status"`
		Usage  json.RawMessage `json:"usage"`
	}
	if err = json.Unmarshal(reply.Data, &p); err != nil {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota probe returned malformed data: %w", err)
	}
	var status struct {
		Authenticated bool `json:"authenticated"`
	}
	var usage struct {
		Authenticated bool   `json:"authenticated"`
		LimitSource   string `json:"limit_source"`
	}
	if json.Unmarshal(p.Status, &status) != nil || json.Unmarshal(p.Usage, &usage) != nil {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota probe status or usage is malformed: %w", quota.ErrUnknown)
	}
	if !status.Authenticated || !usage.Authenticated {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota probe is not authenticated: %w", quota.ErrUnknown)
	}
	if usage.LimitSource != "server" {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota limits are not server-reported: %w", quota.ErrUnknown)
	}
	daily, monthly, err := quota.ParseRemaining(p.Usage)
	if err != nil {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota usage has no consistent absolute counts: %w", err)
	}
	rpm, err := quota.TierRPM(p.Status, p.Usage)
	if err != nil {
		return ingest.QuotaSnapshot{}, fmt.Errorf("passive quota snapshot lacks a verified Community minute cap: %w", err)
	}
	return ingest.QuotaSnapshot{DailyRemaining: daily, MonthlyRemaining: monthly, TradingDaysRemaining: days, VerifiedRPM: rpm, ObservedAt: time.Now().UTC().Add(-time.Millisecond)}, nil
}
