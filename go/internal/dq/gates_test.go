package dq

import (
	"errors"
	"math"
	"strings"
	"testing"
	"time"
)

func input() GateInput {
	d := time.Date(2026, 10, 15, 0, 0, 0, 0, time.UTC)
	return GateInput{Bars: []Bar{good()}, LatestBySymbol: map[string]time.Time{"FPT": d}, Expected: d, IsSession: true, HasPrevious: true, PreviousCount: 100, CurrentCount: 100}
}
func TestGateHappyAndFaults(t *testing.T) {
	if r, e := Gate(input()); e != nil {
		t.Fatalf("valid blocked %+v %v", r, e)
	}
	cases := []struct {
		name   string
		mutate func(*GateInput)
		match  string
	}{
		{"non_session", func(i *GateInput) { i.IsSession = false }, "session"},
		{"zero_expected", func(i *GateInput) { i.Expected = time.Time{} }, "session"},
		{"stale", func(i *GateInput) { i.LatestBySymbol["FPT"] = i.Expected.Add(-time.Hour) }, "stale"},
		{"duplicate", func(i *GateInput) { i.Bars = append(i.Bars, good()) }, "duplicate"},
		{"rowdrop", func(i *GateInput) { i.CurrentCount = 94 }, "row count"},
		{"crosssource", func(i *GateInput) { i.CrossSources = []SourceClose{{"FPT", "2026-10-15", 100, 100.51}} }, "cross-source"},
		{"corporate", func(i *GateInput) { i.Actions = []ActionCheck{{"FPT", "HOSE", 100, 108, false}} }, "corporate"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			i := input()
			tc.mutate(&i)
			r, e := Gate(i)
			if !errors.Is(e, ErrBlocked) || !strings.Contains(strings.Join(r.Blocking, " "), tc.match) {
				t.Fatalf("gate %+v err %v", r, e)
			}
		})
	}
}
func TestThresholdBoundaries(t *testing.T) {
	i := input()
	i.PreviousCount = 100
	i.CurrentCount = 95
	i.CrossSources = []SourceClose{{"FPT", "d", 100, 100.5}}
	i.Actions = []ActionCheck{{"FPT", "UPCoM", 100, 115, false}}
	// Exactly 5% row loss, 0.5% source mismatch and a 15% price move
	// do not breach the strict > thresholds.
	r, e := Gate(i)
	if e != nil {
		t.Fatalf("unexpected block %+v %v", r, e)
	}
	t0 := i.Expected
	latest := map[string]time.Time{}
	for j := 0; j < 100; j++ {
		latest[string(rune(1000+j))] = t0
	}
	j := 0
	for k := range latest {
		if j == 2 {
			break
		}
		latest[k] = t0.Add(-time.Second)
		j++
	}
	bad, frac, e := StaleShare(latest, t0, .02)
	if e != nil || bad || math.Abs(frac-.02) > 1e-9 {
		t.Fatalf("2 percent boundary: %v %v %v", bad, frac, e)
	}
}
func TestSuspendAndDrift(t *testing.T) {
	a := good()
	b := good()
	b.Close = 103
	a.Volume = 0
	if !math.IsNaN(DailyReturn(a, b, 0)) {
		t.Fatal("suspension treated as 0 return")
	}
	a.Volume = 10
	if !math.IsNaN(DailyReturn(a, b, 6)) {
		t.Fatal("long suspension forward filled")
	}
	i := input()
	i.Drift = []FeatureDrift{{"rsi", 0, .4, .1}}
	r, e := Gate(i)
	if e != nil || len(r.Warnings) == 0 {
		t.Fatalf("drift %+v %v", r, e)
	}
}
