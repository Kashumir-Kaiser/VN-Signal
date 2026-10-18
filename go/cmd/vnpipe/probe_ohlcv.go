package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

const conservativeProbeDays = 31

var probeSymbolPattern = regexp.MustCompile(`^[A-Z0-9]{1,12}$`)

type probeOHLCVArgs struct {
	Symbol    string
	Source    string
	Start     string
	End       string
	RawPrices bool
}

type probeOHLCVReport struct {
	At                  string            `json:"at"`
	Active              bool              `json:"active"`
	Route               string            `json:"route"`
	Symbol              string            `json:"symbol"`
	Source              string            `json:"source"`
	Start               string            `json:"from"`
	End                 string            `json:"to"`
	RawPrices           bool              `json:"raw_prices"`
	Available           bool              `json:"available"`
	Count               int               `json:"count"`
	Columns             []string          `json:"columns"`
	FirstObservedDate   string            `json:"first_observed_date,omitempty"`
	LastObservedDate    string            `json:"last_observed_date,omitempty"`
	ProviderAttribution map[string]string `json:"provider_attribution,omitempty"`
	TargetDate          string            `json:"target_date"`
	TargetDateRow       map[string]any    `json:"target_date_row,omitempty"`
}

func validateProbeOHLCVArgs(active bool, a probeOHLCVArgs) error {
	if !active {
		return errors.New("probe-ohlcv requires explicit --active")
	}
	if !probeSymbolPattern.MatchString(a.Symbol) {
		return errors.New("--symbol must be an uppercase 1-12 character ticker")
	}
	if a.Source != "vci" && a.Source != "kbs" {
		return errors.New("--source must be vci or kbs")
	}
	for _, value := range []string{a.Start, a.End} {
		parsed, err := time.Parse("2006-01-02", value)
		if err != nil || parsed.Format("2006-01-02") != value {
			return errors.New("--from and --to must be ISO dates (YYYY-MM-DD)")
		}
	}
	if a.Start > a.End {
		return errors.New("--from must not be after --to")
	}
	return nil
}

func runProbeOHLCV(args []string) error {
	f := flag.NewFlagSet("probe-ohlcv", flag.ContinueOnError)
	active := f.Bool("active", false, "authorize one metered equity OHLCV request")
	symbol := f.String("symbol", "", "uppercase equity ticker")
	source := f.String("source", "", "provider source: vci or kbs")
	start := f.String("from", "", "earliest ISO date")
	end := f.String("to", "", "latest ISO date and target date for row capture")
	rawPrices := f.Bool("raw-prices", false, "request unadjusted source prices (floating=None)")
	out := f.String("out", defaultProbeOHLCVOutputDir(), "local compact report directory")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 {
		return errors.New("unexpected arguments")
	}
	activeSet := false
	f.Visit(func(fl *flag.Flag) {
		if fl.Name == "active" {
			activeSet = true
		}
	})
	if !activeSet {
		return errors.New("probe-ohlcv requires explicit --active")
	}
	request := probeOHLCVArgs{Symbol: *symbol, Source: *source, Start: *start, End: *end, RawPrices: *rawPrices}
	if err := validateProbeOHLCVArgs(*active, request); err != nil {
		return err
	}
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return live.ErrDisabled
	}
	if _, err := config.Load(configPath()); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}
	ignored, err := loadIgnoredSymbols()
	if err != nil {
		return err
	}
	if err := requireNotIgnoredSymbol(request.Symbol, ignored); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// Treat every calendar day as a remaining trading day. This is deliberately
	// more conservative than relying on an unverified market calendar.
	q, err := readAuthenticatedIndexQuota(ctx, conservativeProbeDays)
	if err != nil {
		return fmt.Errorf("fresh authenticated absolute quota required: %w", err)
	}
	budget, err := quota.Budget(q.DailyRemaining, q.MonthlyRemaining, conservativeProbeDays)
	if err != nil {
		return err
	}
	if budget < 1 {
		return quota.ErrExhausted
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
	job := map[string]any{
		"id": "probe-ohlcv-01", "op": "equity_ohlcv", "symbol": request.Symbol,
		"source": request.Source, "start": request.Start, "end": request.End,
		"raw_prices": request.RawPrices,
	}
	reply, err := gateway.Call(ctx, job)
	if err != nil {
		return err
	}
	if !reply.OK {
		cause := ""
		if reply.Error != nil {
			cause = reply.Error.Type
		}
		if cause == "" {
			cause = "AdapterError"
		}
		return fmt.Errorf("equity OHLCV probe failed: %s", cause)
	}
	report, err := extractProbeOHLCVReport(reply.Data, request, time.Now().UTC())
	if err != nil {
		return err
	}
	if err := os.MkdirAll(*out, 0700); err != nil {
		return err
	}
	name := fmt.Sprintf("%s-%s-%s.json", report.At[:10], request.Symbol, time.Now().UTC().Format("150405.000000000Z"))
	path := filepath.Join(*out, name)
	data, err := json.Marshal(report)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, append(data, '\n'), 0600); err != nil {
		return err
	}
	fmt.Printf("OHLCV probe report: %s (one metered call; target date=%s)\n", path, request.End)
	return nil
}

// defaultProbeOHLCVOutputDir anchors reports to the repository, regardless of
// whether vnpipe was started from the repository root or via `go -C go`.
func defaultProbeOHLCVOutputDir() string {
	if cwd, err := os.Getwd(); err == nil {
		for dir := cwd; ; dir = filepath.Dir(dir) {
			if info, err := os.Stat(filepath.Join(dir, "config", "default.toml")); err == nil && !info.IsDir() {
				return filepath.Join(dir, "docs", "probe", "ohlcv")
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
		}
	}
	return filepath.Join("docs", "probe", "ohlcv")
}

func extractProbeOHLCVReport(raw []byte, request probeOHLCVArgs, at time.Time) (probeOHLCVReport, error) {
	var payload struct {
		Count      int              `json:"count"`
		Columns    []string         `json:"columns"`
		Rows       []map[string]any `json:"rows"`
		Attributes map[string]any   `json:"attributes"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return probeOHLCVReport{}, errors.New("invalid OHLCV probe frame")
	}
	if payload.Count < 0 || payload.Count != len(payload.Rows) || len(payload.Columns) > 128 {
		return probeOHLCVReport{}, errors.New("invalid OHLCV probe row accounting")
	}
	columns := make([]string, 0, len(payload.Columns))
	columnSet := make(map[string]bool, len(payload.Columns))
	for _, column := range payload.Columns {
		if column == "" || len(column) > 128 || columnSet[column] {
			return probeOHLCVReport{}, errors.New("invalid OHLCV probe columns")
		}
		columnSet[column] = true
		columns = append(columns, column)
	}
	report := probeOHLCVReport{
		At: at.Format(time.RFC3339Nano), Active: true, Route: "equity_ohlcv",
		Symbol: request.Symbol, Source: request.Source, Start: request.Start, End: request.End,
		RawPrices: request.RawPrices, Available: payload.Count > 0, Count: payload.Count,
		Columns: columns, TargetDate: request.End,
	}
	for _, key := range []string{"source", "route", "source_name", "organisation"} {
		if value, ok := payload.Attributes[key].(string); ok && strings.TrimSpace(value) != "" {
			if len(value) > 160 {
				value = value[:160]
			}
			if report.ProviderAttribution == nil {
				report.ProviderAttribution = map[string]string{}
			}
			report.ProviderAttribution[key] = value
		}
	}
	for _, row := range payload.Rows {
		date, ok := probeRowDate(row)
		if !ok {
			continue
		}
		if report.FirstObservedDate == "" || date < report.FirstObservedDate {
			report.FirstObservedDate = date
		}
		if report.LastObservedDate == "" || date > report.LastObservedDate {
			report.LastObservedDate = date
		}
		if date == request.End {
			target := make(map[string]any, len(columns))
			for _, column := range columns {
				if value, ok := row[column]; ok {
					target[column] = value
				}
			}
			report.TargetDateRow = target
		}
	}
	return report, nil
}

func probeRowDate(row map[string]any) (string, bool) {
	for _, key := range []string{"time", "date"} {
		value, ok := row[key].(string)
		if !ok || len(value) < len("2006-01-02") {
			continue
		}
		date := value[:10]
		parsed, err := time.Parse("2006-01-02", date)
		if err == nil && parsed.Format("2006-01-02") == date {
			return date, true
		}
	}
	return "", false
}
