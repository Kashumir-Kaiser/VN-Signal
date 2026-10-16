package dq

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"time"
)

var ErrBlocked = errors.New("data-quality gate blocked publication")

type SourceClose struct {
	Symbol, Date       string
	Primary, Secondary float64
}
type ActionCheck struct {
	Symbol, Exchange  string
	Previous, Current float64
	ListingDay        bool
}
type FeatureDrift struct {
	Feature                            string
	NullRateBefore, NullRateAfter, PSI float64
}

// GateInput makes the expected market session explicit. Callers must supply
// an independently checked trading calendar rather than assume weekdays.
type GateInput struct {
	Bars                        []Bar
	LatestBySymbol              map[string]time.Time
	Expected                    time.Time
	IsSession                   bool
	PreviousCount, CurrentCount int
	HasPrevious                 bool
	CrossSources                []SourceClose
	Actions                     []ActionCheck
	Drift                       []FeatureDrift
}
type GateReport struct {
	Blocking    []string `json:"blocking"`
	Warnings    []string `json:"warnings"`
	Quarantined []string `json:"quarantined"`
}

func (r GateReport) Valid() bool { return len(r.Blocking) == 0 }
func Gate(in GateInput) (GateReport, error) {
	var r GateReport
	if err := Validate(in.Bars); err != nil {
		r.Blocking = append(r.Blocking, "bars: "+err.Error())
	}
	if !in.IsSession || in.Expected.IsZero() {
		r.Blocking = append(r.Blocking, "expected date is not a verified trading session")
	} else if bad, frac, err := StaleShare(in.LatestBySymbol, in.Expected, .02); err != nil {
		r.Blocking = append(r.Blocking, "staleness: "+err.Error())
	} else if bad {
		r.Blocking = append(r.Blocking, fmt.Sprintf("stale symbols %.4f > 0.02", frac))
	}
	if in.HasPrevious {
		if in.PreviousCount <= 0 || in.CurrentCount < 0 {
			r.Blocking = append(r.Blocking, "invalid session counts")
		} else if float64(in.PreviousCount-in.CurrentCount)/float64(in.PreviousCount) > .05+1e-12 {
			r.Blocking = append(r.Blocking, "row count fell by more than 5%")
		}
	}
	for _, p := range in.CrossSources {
		if p.Primary <= 0 || p.Secondary <= 0 || math.IsNaN(p.Primary) || math.IsNaN(p.Secondary) || math.IsInf(p.Primary, 0) || math.IsInf(p.Secondary, 0) {
			r.Blocking = append(r.Blocking, "invalid cross-source quote "+p.Symbol)
			continue
		}
		if math.Abs(p.Primary-p.Secondary)/p.Primary > .005+1e-12 {
			r.Blocking = append(r.Blocking, "cross-source close mismatch "+p.Symbol+" "+p.Date)
		}
	}
	limits := map[string]float64{"HOSE": .07, "HNX": .10, "UPCOM": .15}
	for _, a := range in.Actions {
		limit, ok := limits[upperASCII(a.Exchange)]
		if !ok || a.Previous <= 0 || a.Current <= 0 {
			r.Blocking = append(r.Blocking, "invalid action comparison "+a.Symbol)
			continue
		}
		if !a.ListingDay && math.Abs(a.Current/a.Previous-1) > limit+1e-12 {
			r.Quarantined = append(r.Quarantined, a.Symbol)
			r.Blocking = append(r.Blocking, "suspected unadjusted corporate action "+a.Symbol)
		}
	}
	for _, d := range in.Drift {
		if d.NullRateBefore < 0 || d.NullRateBefore > 1 || d.NullRateAfter < 0 || d.NullRateAfter > 1 || math.IsNaN(d.PSI) {
			r.Blocking = append(r.Blocking, "invalid drift measurement "+d.Feature)
			continue
		}
		if math.Abs(d.NullRateAfter-d.NullRateBefore) > .05 || d.PSI > .2 {
			r.Warnings = append(r.Warnings, "feature distribution drift "+d.Feature)
		}
	}
	sort.Strings(r.Quarantined)
	if !r.Valid() {
		return r, ErrBlocked
	}
	return r, nil
}
func upperASCII(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'a' && c <= 'z' {
			b[i] = c - 32
		}
	}
	return string(b)
}

// DailyReturn is undefined across suspensions, including zero volume, or more
// than five missed trading sessions. NaN must NOT be forward-filled.
func DailyReturn(previous, current Bar, missingSessions int) float64 {
	if missingSessions > 5 || missingSessions < 0 || previous.Volume == 0 || current.Volume == 0 || previous.Close <= 0 || current.Close <= 0 {
		return math.NaN()
	}
	return current.Close/previous.Close - 1
}
