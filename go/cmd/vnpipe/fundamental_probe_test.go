package main

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
)

type fundamentalJobState struct {
	state     string
	updatedAt time.Time
}

type fundamentalCompletionSet map[string]fundamentalJobState

func (s fundamentalCompletionSet) FundamentalJobState(_ context.Context, jobID string) (string, time.Time, bool, error) {
	job, ok := s[jobID]
	return job.state, job.updatedAt, ok, nil
}

func TestFundamentalBatchPacerAdmitsCompleteSafeBatch(t *testing.T) {
	pacer, err := fundamentalBatchPacer(60, 12, 20)
	if err != nil {
		t.Fatal(err)
	}
	if got := pacer.Remaining(); got != 12 {
		t.Fatalf("pacer capacity=%d, want all 12 pending jobs", got)
	}
	if _, err := fundamentalBatchPacer(60, 12, 11); err == nil || !strings.Contains(err.Error(), "no market-data request sent") {
		t.Fatalf("underfunded batch was not rejected during preflight: %v", err)
	}
	if _, err := fundamentalBatchPacer(60, -1, 12); err != quota.ErrUnknown {
		t.Fatalf("negative pending count did not fail closed: %v", err)
	}
}

func TestPendingFundamentalJobsUsesDurableIdempotencyKeys(t *testing.T) {
	jobs := []ingest.FundamentalJob{
		{Symbol: "VIC", StatementType: "income_statement", PeriodType: "quarter", Mode: "backfill"},
		{Symbol: "VHM", StatementType: "income_statement", PeriodType: "quarter", Mode: "backfill"},
	}
	completedKey, err := ingest.FundamentalJobID(jobs[0], time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	completedAt := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	pending, err := pendingFundamentalJobs(context.Background(), fundamentalCompletionSet{completedKey: {state: "COMPLETED", updatedAt: completedAt}}, jobs, completedAt)
	if err != nil || pending != 1 {
		t.Fatalf("pending=%d err=%v, want only VHM pending", pending, err)
	}
}

func TestPendingFundamentalJobsRejectsBlockedAndActivelyLeasedJobsBeforeCalls(t *testing.T) {
	job := ingest.FundamentalJob{Symbol: "VIC", StatementType: "income_statement", PeriodType: "quarter", Mode: "backfill"}
	key, err := ingest.FundamentalJobID(job, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name string
		job  fundamentalJobState
		want string
	}{
		{name: "blocked", job: fundamentalJobState{state: "BLOCKED"}, want: "blocked"},
		{name: "active reservation", job: fundamentalJobState{state: "RESERVED", updatedAt: now.Add(-14 * time.Minute)}, want: "active lease"},
		{name: "active dispatch", job: fundamentalJobState{state: "RUNNING", updatedAt: now.Add(-14 * time.Minute)}, want: "active lease"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := pendingFundamentalJobs(context.Background(), fundamentalCompletionSet{key: tc.job}, []ingest.FundamentalJob{job}, now); err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("preflight err=%v; want %q and zero calls", err, tc.want)
			}
		})
	}
}

func TestPendingFundamentalJobsResumesExpiredLeaseAndRejectsUnknownState(t *testing.T) {
	job := ingest.FundamentalJob{Symbol: "VIC", StatementType: "income_statement", PeriodType: "quarter", Mode: "backfill"}
	key, err := ingest.FundamentalJobID(job, time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	store := fundamentalCompletionSet{key: {state: "RESERVED", updatedAt: now.Add(-15 * time.Minute)}}
	if got, err := pendingFundamentalJobs(context.Background(), store, []ingest.FundamentalJob{job}, now); err != nil || got != 1 {
		t.Fatalf("expired lease preflight=(%d,%v), want one resumable job", got, err)
	}
	store[key] = fundamentalJobState{state: "UNEXPECTED", updatedAt: now}
	if _, err := pendingFundamentalJobs(context.Background(), store, []ingest.FundamentalJob{job}, now); err == nil || !strings.Contains(err.Error(), "unknown durable state") {
		t.Fatalf("unknown state did not fail closed: %v", err)
	}
}

func TestFundamentalProbePeriodSelection(t *testing.T) {
	for _, period := range []string{"quarter", "year"} {
		requests, err := selectProbeRequests(probeRequests("2026-10-24"), "income_statement,balance_sheet,cash_flow")
		if err != nil {
			t.Fatal(err)
		}
		if err := setFundamentalProbePeriod(requests, period); err != nil {
			t.Fatal(err)
		}
		for _, request := range requests {
			if request["period"] != period {
				t.Fatal("period was not set on every selected route")
			}
		}
	}
	for _, period := range []string{"", "monthly", "YEAR"} {
		if setFundamentalProbePeriod([]map[string]any{{"op": "income_statement"}}, period) == nil {
			t.Fatal("accepted invalid period", period)
		}
	}
	if setFundamentalProbePeriod(nil, "year") == nil {
		t.Fatal("accepted empty selection")
	}
	requests := []map[string]any{{"op": "income_statement", "period": "quarter"}, {"op": "equity_ohlcv"}}
	if setFundamentalProbePeriod(requests, "year") == nil || requests[0]["period"] != "quarter" {
		t.Fatal("mixed selection accepted or partially mutated")
	}
}

func TestFundamentalProbeRequiresMatchingPeriodEvidence(t *testing.T) {
	now := time.Date(2026, 10, 24, 6, 0, 0, 0, time.UTC)
	for _, statement := range []string{"income_statement", "balance_sheet", "cash_flow"} {
		for _, period := range []string{"quarter", "year"} {
			for _, evidence := range []string{"quarter", "year", "", "month"} {
				frame := map[string]any{"at": now.Format(time.RFC3339), "active": true, "routes": map[string]any{statement: map[string]any{
					"available": true, "count": 160, "columns": []string{"period", "id", "name", "order", "level", "unit", "value"},
					"attributes": map[string]any{"source": "vci", "route": "fundamental.equity." + statement, "requested_period": evidence},
				}}}
				raw, err := json.Marshal(frame)
				if err != nil {
					t.Fatal(err)
				}
				err = validateFundamentalProbe(raw, now, statement, period)
				if (err == nil) != (period == evidence) {
					t.Fatalf("statement=%s period=%s evidence=%s err=%v", statement, period, evidence, err)
				}
			}
		}
	}
}

func TestFundamentalProbeCLIRejectsInvalidPeriodBeforeWorker(t *testing.T) {
	t.Setenv("VNPIPE_CONFIG", filepath.Join("..", "..", "..", "config", "default.toml"))
	t.Setenv("VNPIPE_WORKER", filepath.Join(t.TempDir(), "must-not-be-invoked.py"))
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"probe", "--period=year"}, "--period requires --active"},
		{[]string{"probe", "--active", "--routes=income_statement", "--period="}, "quarter or year"},
		{[]string{"probe", "--active", "--routes=income_statement", "--period=month"}, "quarter or year"},
		{[]string{"probe", "--active", "--period=year"}, "fundamental statement probes"},
	} {
		if err := run(tc.args); err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Fatalf("args=%v err=%v want %s", tc.args, err, tc.want)
		}
	}
}

func TestFundamentalProbeRejectsUnverifiedFrames(t *testing.T) {
	now := time.Date(2026, 10, 24, 6, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		name   string
		change func(map[string]any, map[string]any, map[string]any)
	}{
		{"zero rows", func(_, r, _ map[string]any) { r["count"] = 0 }},
		{"negative rows", func(_, r, _ map[string]any) { r["count"] = -1 }},
		{"oversized rows", func(_, r, _ map[string]any) { r["count"] = 10001 }},
		{"missing count", func(_, r, _ map[string]any) { delete(r, "count") }},
		{"unavailable", func(_, r, _ map[string]any) { r["available"] = false }},
		{"missing column", func(_, r, _ map[string]any) { r["columns"] = []string{"period"} }},
		{"wrong source", func(_, _, a map[string]any) { a["source"] = "other" }},
		{"wrong route", func(_, _, a map[string]any) { a["route"] = "fundamental.equity.cash_flow" }},
		{"passive", func(p, _, _ map[string]any) { p["active"] = false }},
		{"stale", func(p, _, _ map[string]any) { p["at"] = now.Add(-25 * time.Hour).Format(time.RFC3339) }},
		{"future", func(p, _, _ map[string]any) { p["at"] = now.Add(2 * time.Minute).Format(time.RFC3339) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a := map[string]any{"source": "vci", "route": "fundamental.equity.income_statement", "requested_period": "quarter"}
			r := map[string]any{"available": true, "count": 160, "columns": []string{"period", "id", "name", "order", "level", "unit", "value"}, "attributes": a}
			p := map[string]any{"at": now.Format(time.RFC3339), "active": true, "routes": map[string]any{"income_statement": r}}
			tc.change(p, r, a)
			raw, err := json.Marshal(p)
			if err != nil {
				t.Fatal(err)
			}
			if validateFundamentalProbe(raw, now, "income_statement", "quarter") == nil {
				t.Fatal("unverified capability accepted")
			}
		})
	}
}
