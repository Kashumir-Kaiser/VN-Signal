package ingest

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type fundamentalMemoryStore struct{ memoryStore }

var _ FundamentalLandingStore = (*fundamentalMemoryStore)(nil)
var _ FundamentalQuarantineStore = (*fundamentalMemoryStore)(nil)

func (s *fundamentalMemoryStore) CommitFundamentalLanding(ctx context.Context, item FundamentalLanding) error {
	return s.CommitLanding(ctx, Landing{JobID: item.JobID, Source: item.Source, FetchedAt: item.FetchedAt, SHA256: item.SHA256, Raw: item.Raw})
}
func (s *fundamentalMemoryStore) QuarantineFundamentalFrame(ctx context.Context, key, source, reason string, raw json.RawMessage) error {
	return s.QuarantineFrame(ctx, key, source, reason, raw)
}

func TestFundamentalObservedRefreshIsDailyAndBackfillRemainsIdempotent(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	pacer, err := quota.NewPacer(60000, 4)
	if err != nil {
		t.Fatal(err)
	}
	calls := 0
	gateway, err := live.New(pacer, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		raw := json.RawMessage(`{"count":1,"columns":["period","id","name","order","level","unit","value"],"attributes":{"source":"vci","symbol":"FPT","route":"fundamental.equity.income_statement"},"rows":[{"period":"2024-Q1","id":"fixture","name":"Revenue","order":1,"level":1,"unit":"VND","value":2}]}`)
		return worker.Response{ID: job["id"].(string), OK: true, Data: raw}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	store := &fundamentalMemoryStore{memoryStore{done: map[string]Landing{}}}
	now := time.Date(2026, 10, 24, 16, 59, 0, 0, time.UTC)
	beforeCalls := 0
	runner := Runner{Gateway: gateway, Store: store, Now: func() time.Time { return now }, BeforeCall: func(context.Context) error { beforeCalls++; return nil }}
	job := FundamentalJob{Symbol: "FPT", StatementType: "income_statement", PeriodType: "quarter", Mode: "observed"}
	for i, step := range []struct {
		advance            time.Duration
		mode               string
		committed, skipped int
	}{
		{0, "observed", 1, 0}, {0, "observed", 0, 1},
		{time.Minute, "observed", 1, 0}, // Same UTC date, next Vietnam date.
		{time.Hour, "observed", 0, 1}, {7 * 24 * time.Hour, "observed", 1, 0},
		{0, "backfill", 1, 0}, {24 * time.Hour, "backfill", 0, 1},
	} {
		now = now.Add(step.advance)
		job.Mode = step.mode
		summary, err := runner.RunFundamentalsBackfill(context.Background(), []FundamentalJob{job})
		if err != nil || summary.Committed != step.committed || summary.Skipped != step.skipped {
			t.Fatalf("step %d: %+v err=%v", i, summary, err)
		}
	}
	if calls != 4 || beforeCalls != 4 || pacer.Remaining() != 0 || len(store.done) != 4 {
		t.Fatalf("calls=%d fresh quota checks=%d remaining=%d jobs=%d", calls, beforeCalls, pacer.Remaining(), len(store.done))
	}
}

func TestFundamentalPeriodDatabaseYearBounds(t *testing.T) {
	for _, tc := range []struct{ key, frequency, end string }{
		{"0000", "year", ""}, {"0000-Q1", "quarter", ""},
		{"0000-Q4", "quarter", ""},
		{"0001", "year", "0001-12-31"}, {"0001-Q1", "quarter", "0001-03-31"},
		{"9999", "year", "9999-12-31"}, {"9999-Q4", "quarter", "9999-12-31"},
	} {
		t.Run(tc.key, func(t *testing.T) {
			period, err := fundamentalPeriod(tc.key, tc.frequency)
			if tc.end == "" {
				if err == nil {
					t.Fatal("accepted PostgreSQL-incompatible year zero")
				}
				return
			}
			if err != nil || period.End.Format("2006-01-02") != tc.end {
				t.Fatalf("period=%+v err=%v, want %s", period, err, tc.end)
			}
		})
	}
}

func TestAnalyzeFundamentalFrameLongPeriods(t *testing.T) {
	raw := json.RawMessage(`{"count":4,"columns":["period","id","name","order","level","unit","value"],"attributes":{"source":"vci","symbol":"FPT","route":"fundamental.equity.income_statement"},"rows":[{"period":"2024-Q1","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":2},{"period":"2024-Q2","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":3},{"period":"2024-Q1","id":"2","name":"Profit","order":2,"level":1,"unit":"VND","value":null},{"period":"2024-Q2","id":"2","name":"Profit","order":2,"level":1,"unit":"VND","value":4}]}`)
	f, p, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(f.Rows) != 4 || len(p) != 2 || p[0].Key != "2024-Q1" || p[0].End.Format("2006-01-02") != "2024-03-31" {
		t.Fatalf("unexpected frame/period parse: %+v %+v", f, p)
	}
}

func TestAnalyzeFundamentalFrameRejectsUnknownPeriodAndDuplicateIDsWithinPeriod(t *testing.T) {
	base := `{"count":1,"columns":["period","id","name","order","level","unit","value"],"attributes":{"source":"vci","symbol":"FPT","route":"fundamental.equity.income_statement"},"rows":[{"period":"PERIOD","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":2}]}`
	if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(stringsReplace(base, "PERIOD", "2024Q1"))); err == nil {
		t.Fatal("accepted unknown period label")
	}
	dup := stringsReplace(stringsReplace(base, "PERIOD", "2024-Q1"), `"count":1`, `"count":2`)
	dup = stringsReplace(dup, `"rows":[{`, `"rows":[{`)
	// Two copies of the same line id in one period must fail.
	dup = stringsReplace(dup, `"value":2}]`, `"value":2},{"period":"2024-Q1","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":3}]`)
	if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(dup)); err == nil {
		t.Fatal("accepted duplicate line id")
	}
}

func TestAnalyzeFundamentalFrameRejectsMismatchedOrMissingSymbol(t *testing.T) {
	base := `{"count":1,"columns":["period","id","name","order","level","unit","value"],"attributes":{"source":"vci","symbol":"OTHER","route":"fundamental.equity.income_statement"},"rows":[{"period":"2024-Q1","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":2}]}`
	if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(base)); err == nil {
		t.Fatal("accepted frame attributed to a different ticker")
	}
	missing := stringsReplace(base, `"symbol":"OTHER",`, "")
	if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(missing)); err == nil {
		t.Fatal("accepted frame without ticker attribution")
	}
}

func stringsReplace(s, old, new string) string { return strings.Replace(s, old, new, 1) }

func TestAnalyzeFundamentalFrameRejectsArchiveTypeMismatches(t *testing.T) {
	base := `{"count":1,"columns":["period","id","name","order","level","unit","value"],"attributes":{"source":"vci","symbol":"FPT","route":"fundamental.equity.income_statement"},"rows":[{"period":"2024-Q1","id":"1","name":"Revenue","order":1,"level":1,"unit":"VND","value":2}]}`
	cases := []struct{ name, old, replacement string }{
		{"quoted_order", `"order":1`, `"order":"1"`},
		{"fractional_order", `"order":1`, `"order":1.5`},
		{"decimal_order_token", `"order":1`, `"order":1.0`},
		{"order_overflow", `"order":1`, `"order":2147483648`},
		{"order_underflow", `"order":1`, `"order":-2147483649`},
		{"quoted_level", `"level":1`, `"level":"1"`},
		{"quoted_value", `"value":2`, `"value":"2"`},
		{"numeric_unit", `"unit":"VND"`, `"unit":1000`},
		{"object_unit", `"unit":"VND"`, `"unit":{}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(stringsReplace(base, tc.old, tc.replacement))); err == nil {
				t.Fatal("accepted malformed archive field")
			}
		})
	}
	for _, order := range []string{"-2147483648", "0", "2147483647"} {
		if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(stringsReplace(base, `"order":1`, `"order":`+order))); err != nil {
			t.Fatalf("rejected supported integer order %s: %v", order, err)
		}
	}
	// Unknown units may be archived without claiming a verified metric mapping.
	if _, _, err := AnalyzeFundamentalFrame("FPT", "income_statement", "quarter", json.RawMessage(stringsReplace(base, `"unit":"VND"`, `"unit":null`))); err != nil {
		t.Fatalf("rejected an explicit unknown unit: %v", err)
	}
}
