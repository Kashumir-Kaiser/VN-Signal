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
	for raw, expect := range map[string]int{`{"tier":"Community"}`: 60, `{"tier":"Guest"}`: 20} {
		got, e := TierRPM([]byte(raw))
		if e != nil || got != expect {
			t.Fatalf("%q %d %v", raw, got, e)
		}
	}
	for _, raw := range []string{`{}`, `{"tier":"Sponsor"}`, `{"tier":"unknown"}`} {
		if _, e := TierRPM([]byte(raw)); !errors.Is(e, ErrUnknown) {
			t.Fatal(raw)
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
