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
