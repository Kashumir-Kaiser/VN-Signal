package quota

import (
	"errors"
	"testing"
	"time"
)

func TestBudget(t *testing.T) {
	got, err := Budget(100, 600, 12)
	if err != nil || got != 40 {
		t.Fatalf("budget=%d err=%v", got, err)
	}
	if _, err := Budget(-1, 100, 2); !errors.Is(err, ErrUnknown) {
		t.Fatal("unknown quota must block")
	}
	n, _ := Budget(0, 100, 1)
	if n != 0 {
		t.Fatal("empty quota must block")
	}
}
func TestPacer(t *testing.T) {
	p, err := NewPacer(60, 2)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	a, _ := p.Reserve(now)
	b, _ := p.Reserve(now)
	if !b.After(a) {
		t.Fatal("rate limiter didn't serialize")
	}
	if _, err := p.Reserve(now); !errors.Is(err, ErrExhausted) {
		t.Fatal("over-budget call allowed")
	}
}

func TestTierParsing(t *testing.T) {
	usage := []byte(`{"tier":"free","authenticated":true,"limits":{"per_minute":30}}`)
	for _, raw := range []string{`{"tier":"Community","authenticated":true}`, `{"tier":"free","authenticated":true}`} {
		got, e := TierRPM([]byte(raw), usage)
		if e != nil || got != 30 {
			t.Fatalf("%q %d %v", raw, got, e)
		}
	}
	for _, pair := range [][2]string{
		{`{}`, string(usage)},
		{`{"tier":"guest","authenticated":false}`, `{"tier":"guest","authenticated":false,"limits":{"per_minute":10}}`},
		{`{"tier":"Sponsor","authenticated":true}`, string(usage)},
		{`{"tier":"free","authenticated":true}`, `{"tier":"free","authenticated":true,"limits":{"per_minute":0}}`},
		{`{"tier":"free","authenticated":true}`, `{"tier":"free","authenticated":true,"limits":{"per_minute":61}}`},
		{`{"tier":"community","authenticated":true}`, `{"tier":"sponsor","authenticated":true,"limits":{"per_minute":30}}`},
	} {
		if _, e := TierRPM([]byte(pair[0]), []byte(pair[1])); !errors.Is(e, ErrUnknown) {
			t.Fatalf("accepted status=%s usage=%s", pair[0], pair[1])
		}
	}
}

func TestParseRemainingFromExactUsageSnapshot(t *testing.T) {
	// This is the real v5 shape, with device identifiers omitted.
	raw := []byte(`{"tier":"guest","authenticated":false,"limits":{"per_minute":10,"per_hour":100,"per_day":300,"per_month":1000},"used":{"minute":0,"hour":0,"day":12,"month":45}}`)
	daily, monthly, err := ParseRemaining(raw)
	if err != nil || daily != 288 || monthly != 955 {
		t.Fatalf("remaining daily=%d monthly=%d err=%v", daily, monthly, err)
	}
	legacy := []byte(`{"daily_remaining":7,"monthly_remaining":19}`)
	daily, monthly, err = ParseRemaining(legacy)
	if err != nil || daily != 7 || monthly != 19 {
		t.Fatalf("legacy remaining daily=%d monthly=%d err=%v", daily, monthly, err)
	}
	for _, raw := range []string{
		`{"daily_remaining":"80%","monthly_remaining":100}`,
		`{"limits":{"per_day":10,"per_month":20},"used":{"day":11,"month":1}}`,
		`{"limits":{"per_day":10},"used":{"day":1,"month":1}}`,
		`{"limits":{"per_day":10,"per_month":20},"used":{"day":"1","month":1}}`,
	} {
		if _, _, err := ParseRemaining([]byte(raw)); !errors.Is(err, ErrUnknown) {
			t.Fatalf("accepted invalid usage %s: %v", raw, err)
		}
	}
}

func TestClockJumpAndLowRPM(t *testing.T) {
	p, err := NewPacer(1, 3)
	if err != nil {
		t.Fatal(err)
	}
	t0 := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	a, _ := p.Reserve(t0)
	b, _ := p.Reserve(t0.Add(-24 * time.Hour))
	if b.Sub(a) < time.Minute {
		t.Fatal("backward clock jump compressed pacing")
	}
	c, _ := p.Reserve(t0.Add(time.Hour))
	if c.Before(t0.Add(time.Hour)) {
		t.Fatal("forward jump produced an earlier reservation")
	}
	if p.Remaining() != 0 {
		t.Fatal("reserve did not consume 3 calls")
	}
}
