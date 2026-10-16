package ingest

import (
	"encoding/json"
	"errors"
	"testing"
)

var verified = []byte(`{"active":true,"status":{"tier":"Community"},"usage":{"daily_remaining":5,"monthly_remaining":30},"routes":{"equity_ohlcv":{"available":true}}}`)

func TestPlanBackfillBudgetAndDeterminism(t *testing.T) {
	p, e := PlanBackfill(verified, 10, "2018-10-01", "2026-10-16", []string{"HPG", "fpt", "ACB", "VHM", "MBB"}, []string{"YEG"})
	if e != nil {
		t.Fatal(e)
	}
	// floor(min(0.8*5, 0.8*30/10)) = 2
	if p.Budget != 2 || p.RPM != 60 || len(p.Planned) != 2 || len(p.Deferred) != 4 || p.Planned[0].Symbol != "ACB" || p.Planned[1].Symbol != "FPT" {
		t.Fatalf("%+v", p)
	}
	b, e := json.Marshal(p)
	if e != nil || len(b) == 0 {
		t.Fatal(e)
	}
}
func TestPlanBackfillFailsClosed(t *testing.T) {
	cases := [][]byte{[]byte(`{}`), []byte(`{"active":false}`), []byte(`{"active":true,"status":{"tier":"community"},"usage":{"daily_remaining":"80%","monthly_remaining":100},"routes":{"equity_ohlcv":{"available":true}}}`), []byte(`{"active":true,"status":{"tier":"Sponsor"},"usage":{"daily_remaining":100,"monthly_remaining":100},"routes":{"equity_ohlcv":{"available":true}}}`)}
	for _, c := range cases {
		_, e := PlanBackfill(c, 5, "2018-10-01", "2026-10-16", []string{"FPT"}, nil)
		if !errors.Is(e, ErrUnverified) {
			t.Fatalf("expected fail closed, got %v", e)
		}
	}
	_, e := PlanBackfill(verified, 10, "2018-10-01", "2026-10-16", []string{"FPT"}, []string{"fpt"})
	if e == nil {
		t.Fatal("duplicates accepted")
	}
	_, e = PlanBackfill(verified, 10, "not-a-date", "2026-10-16", []string{"FPT"}, nil)
	if e == nil {
		t.Fatal("date accepted")
	}
}
