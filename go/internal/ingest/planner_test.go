package ingest

import (
	"encoding/json"
	"errors"
	"testing"
)

var verified = []byte(`{"active":true,"status":{"tier":"Community","authenticated":true},"usage":{"tier":"free","authenticated":true,"limits":{"per_minute":60,"per_day":8,"per_month":100},"used":{"day":3,"month":70}},"routes":{"equity_ohlcv":{"available":true}}}`)

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

func TestPlanBackfillRotationStartsAtOffsetWithinTier(t *testing.T) {
	p, err := PlanBackfillWithOffset(verified, 10, "2018-10-01", "2026-10-16",
		[]string{"HPG", "FPT", "ACB", "VHM", "MBB"}, []string{"YEG"}, 3)
	if err != nil {
		t.Fatal(err)
	}
	if p.Budget != 2 || len(p.Planned) != 2 || p.Planned[0].Symbol != "MBB" || p.Planned[1].Symbol != "VHM" {
		t.Fatalf("unexpected rotated plan: %+v", p)
	}
	if len(p.Deferred) != 4 || p.Deferred[0].Symbol != "ACB" || p.Deferred[3].Symbol != "YEG" {
		t.Fatalf("unexpected deferred tail: %+v", p.Deferred)
	}
}

func TestPlanBackfillRotationRejectsNegativeOffset(t *testing.T) {
	_, err := PlanBackfillWithOffset(verified, 10, "2018-10-01", "2026-10-16", []string{"FPT"}, nil, -1)
	if err == nil {
		t.Fatal("negative rotation offset accepted")
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
