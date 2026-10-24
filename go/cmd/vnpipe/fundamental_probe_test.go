package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

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
