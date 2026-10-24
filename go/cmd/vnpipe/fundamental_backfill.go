package main

import (
	"context"
	"encoding/json"
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

func runFundamentalsBackfill(args []string) error {
	f := flag.NewFlagSet("backfill-fundamentals", flag.ContinueOnError)
	active := f.Bool("active", false, "authorize account-metered requests")
	probePath := f.String("probe", "", "saved active capability report")
	statement := f.String("statement", "", "income_statement, balance_sheet, or cash_flow")
	period := f.String("period", "quarter", "quarter or year")
	mode := f.String("mode", "backfill", "backfill or observed availability basis")
	symbols := f.String("symbols", "", "comma-separated symbols, maximum 100")
	days := f.Int("days", 0, "remaining market sessions in calendar month")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || !*active || *probePath == "" || *days < 1 || *days > 31 {
		return errors.New("backfill-fundamentals requires --active --probe FILE --statement TYPE --period quarter|year --symbols LIST --days N")
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
	if err = validateFundamentalProbe(saved, time.Now(), *statement, *period); err != nil {
		return err
	}
	parts := strings.Split(*symbols, ",")
	if len(parts) == 0 || len(parts) > 100 {
		return errors.New("fundamental symbol list must contain 1..100 symbols")
	}
	jobs := make([]ingest.FundamentalJob, 0, len(parts))
	seen := map[string]bool{}
	for _, s := range parts {
		s = strings.ToUpper(strings.TrimSpace(s))
		if s == "" || seen[s] {
			return errors.New("fundamental symbols must be non-empty and unique")
		}
		seen[s] = true
		jobs = append(jobs, ingest.FundamentalJob{Symbol: s, StatementType: *statement, PeriodType: *period, Mode: *mode})
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
	if budget < len(jobs) {
		return fmt.Errorf("fresh account quota covers %d calls, need %d", budget, len(jobs))
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
	summary, err := runner.RunFundamentalsBackfill(ctx, jobs)
	fmt.Printf("Fundamentals archive: statement=%s period=%s mode=%s committed=%d skipped=%d blocked=%d\n", *statement, *period, *mode, summary.Committed, summary.Skipped, summary.Blocked)
	return err
}

func validateFundamentalProbe(raw []byte, now time.Time, statement, period string) error {
	if statement != "income_statement" && statement != "balance_sheet" && statement != "cash_flow" {
		return errors.New("unsupported fundamental statement")
	}
	if period != "quarter" && period != "year" {
		return errors.New("unsupported fundamental period")
	}
	var p struct {
		At     string `json:"at"`
		Active bool   `json:"active"`
		Routes map[string]struct {
			Count      int      `json:"count"`
			Available  bool     `json:"available"`
			Columns    []string `json:"columns"`
			Attributes struct {
				Route  string `json:"route"`
				Source string `json:"source"`
				Period string `json:"requested_period"`
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
	r, ok := p.Routes[statement]
	if !ok || !r.Available || r.Count < 1 || r.Count > 10000 || r.Attributes.Source != "vci" || r.Attributes.Route != "fundamental.equity."+statement || r.Attributes.Period != period {
		return ingest.ErrUnverified
	}
	want := map[string]bool{"period": false, "id": false, "name": false, "order": false, "level": false, "unit": false, "value": false}
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
