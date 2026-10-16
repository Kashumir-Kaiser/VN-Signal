package dq

import (
	"strings"
	"testing"
	"time"
)

func good() Bar { return Bar{"FPT", "2026-10-15", 100, 106, 99, 102, 1000} }
func TestValidate(t *testing.T) {
	if err := Validate([]Bar{good()}); err != nil {
		t.Fatal(err)
	}
	b := good()
	b.High = 98
	if err := Validate([]Bar{b}); err == nil {
		t.Fatal("bad OHLC accepted")
	}
	b = good()
	b.Volume = -1
	if err := Validate([]Bar{b}); err == nil {
		t.Fatal("negative volume accepted")
	}
	if err := Validate([]Bar{good(), good()}); err == nil || !strings.Contains(err.Error(), "duplicate") {
		t.Fatal("duplicate accepted")
	}
	b = good()
	b.Date = "2026-02-30"
	if err := Validate([]Bar{b}); err == nil {
		t.Fatal("invalid date accepted")
	}
}
func TestStale(t *testing.T) {
	now := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	bad, frac, err := StaleShare(map[string]time.Time{"A": now, "B": now.Add(-24 * time.Hour)}, now, .02)
	if !bad || frac != .5 || err != nil {
		t.Fatalf("bad=%v fraction=%v err=%v", bad, frac, err)
	}
}
