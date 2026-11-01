package ingest

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
)

// ErrUnverified ensures offline planning cannot be mistaken for permission to ingest.
var ErrUnverified = errors.New("backfill plan requires successful active capability probe and exact quotas")

type BackfillJob struct {
	Route  string `json:"route"`
	Symbol string `json:"symbol"`
	Source string `json:"source,omitempty"`
	Start  string `json:"start"`
	End    string `json:"end"`
	Tier   string `json:"tier"`
}
type Plan struct {
	Planned  []BackfillJob `json:"planned"`
	Deferred []BackfillJob `json:"deferred"`
	Budget   int           `json:"budget"`
	RPM      int           `json:"verified_rpm"`
}
type capability struct {
	Active bool            `json:"active"`
	Status json.RawMessage `json:"status"`
	Usage  json.RawMessage `json:"usage"`
	Routes map[string]struct {
		Available bool `json:"available"`
	} `json:"routes"`
}

// PlanBackfill produces a deterministic *offline preview* of the calls allowed
// by the last recorded active capability report. Before execution, production
// code MUST fetch fresh quotas and route every call through live.Gateway.
// The preview has no authority to execute calls or reserve real quota.
func PlanBackfill(report []byte, tradingDays int, start, end string, tierA, tierB []string) (Plan, error) {
	return PlanBackfillWithOffset(report, tradingDays, start, end, tierA, tierB, 0)
}

// PlanBackfillWithOffset keeps the normal alphabetical order unless the
// caller supplies a nonzero round-robin offset. Rotation is applied within
// each tier, so a lower tier never jumps ahead of Tier A.
func PlanBackfillWithOffset(report []byte, tradingDays int, start, end string, tierA, tierB []string, offset int) (Plan, error) {
	var p Plan
	if offset < 0 {
		return p, errors.New("backfill rotation offset must not be negative")
	}
	var cap capability
	if err := json.Unmarshal(report, &cap); err != nil || !cap.Active || !cap.Routes["equity_ohlcv"].Available {
		return p, ErrUnverified
	}
	daily, monthly, err := quota.ParseRemaining(cap.Usage)
	if err != nil {
		return p, ErrUnverified
	}
	rpm, err := quota.TierRPM(cap.Status, cap.Usage)
	if err != nil {
		return p, ErrUnverified
	}
	budget, err := quota.Budget(daily, monthly, tradingDays)
	if err != nil {
		return p, err
	}
	if start == "" || end == "" || len(start) != 10 || len(end) != 10 || start > end {
		return p, fmt.Errorf("bad backfill date range")
	}
	for _, date := range []string{start, end} {
		if _, err := parseDate(json.RawMessage(`"` + date + `"`)); err != nil {
			return p, err
		}
	}
	canonical := func(s string) (string, error) {
		s = strings.ToUpper(strings.TrimSpace(s))
		if len(s) < 1 || len(s) > 12 {
			return "", errors.New("bad symbol")
		}
		for _, c := range s {
			if !(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9') {
				return "", errors.New("bad symbol")
			}
		}
		return s, nil
	}
	seen := make(map[string]bool)
	for _, tier := range []struct {
		Name    string
		Symbols []string
	}{{"A", tierA}, {"B", tierB}} {
		names := make([]string, 0, len(tier.Symbols))
		for _, s := range tier.Symbols {
			sym, err := canonical(s)
			if err != nil {
				return Plan{}, err
			}
			if seen[sym] {
				return Plan{}, fmt.Errorf("duplicate symbol across tiers: %s", sym)
			}
			seen[sym] = true
			names = append(names, sym)
		}
		sort.Strings(names)
		if len(names) > 0 && offset > 0 {
			startAt := offset % len(names)
			rotated := make([]string, 0, len(names))
			rotated = append(rotated, names[startAt:]...)
			rotated = append(rotated, names[:startAt]...)
			names = rotated
		}
		for _, sym := range names {
			job := BackfillJob{Route: "equity_ohlcv", Symbol: sym, Start: start, End: end, Tier: tier.Name}
			if len(p.Planned) < budget {
				p.Planned = append(p.Planned, job)
			} else {
				p.Deferred = append(p.Deferred, job)
			}
		}
	}
	p.Budget = budget
	p.RPM = rpm
	return p, nil
}
