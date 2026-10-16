// Package quota enforces a conservative call budget. Unknown capacity stops work.
package quota

import (
	"encoding/json"
	"errors"
	"math"
	"strings"
	"sync"
	"time"
)

var ErrUnknown = errors.New("quota capacity unknown: fail closed")
var ErrExhausted = errors.New("daily API-call budget exhausted")

// Budget requires ABSOLUTE remaining calls, not percentages. Days must be >= 1.
func Budget(dailyRemaining, monthlyRemaining, tradingDaysRemaining int) (int, error) {
	if dailyRemaining < 0 || monthlyRemaining < 0 || tradingDaysRemaining < 1 {
		return 0, ErrUnknown
	}
	perDay := float64(dailyRemaining) * .8
	perMonth := float64(monthlyRemaining) * .8 / float64(tradingDaysRemaining)
	return int(math.Floor(math.Min(perDay, perMonth))), nil
}

// Pacer is shared by every request process; it must not exceed 85% of verified tier RPM.
type Pacer struct {
	mu        sync.Mutex
	interval  time.Duration
	next      time.Time
	remaining int
}

func NewPacer(verifiedRPM, budget int) (*Pacer, error) {
	if verifiedRPM <= 0 || budget < 0 {
		return nil, ErrUnknown
	}
	effective := .85 * float64(verifiedRPM)
	return &Pacer{interval: time.Duration(float64(time.Minute) / effective), remaining: budget}, nil
}

// Reserve is a clock-friendly nonblocking reservation. Caller waits until `at`.
// Reserve consumes exactly one call even if an HTTP failure occurs.
func (p *Pacer) Reserve(now time.Time) (at time.Time, err error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.remaining == 0 {
		return time.Time{}, ErrExhausted
	}
	p.remaining--
	at = now
	if p.next.After(at) {
		at = p.next
	}
	p.next = at.Add(p.interval)
	return at, nil
}

func (p *Pacer) Remaining() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.remaining
}

// ParseRemaining accepts exact absolute remaining counts or derives them from
// vnstock's exact per-period limits and used counters. Percentages and incomplete
// or inconsistent reports fail closed.
func ParseRemaining(raw []byte) (daily, monthly int, err error) {
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return 0, 0, ErrUnknown
	}
	_, hasDaily := m["daily_remaining"]
	_, hasMonthly := m["monthly_remaining"]
	if hasDaily || hasMonthly {
		var ok bool
		daily, ok = exactNonNegativeInt(m["daily_remaining"])
		if !ok {
			return 0, 0, ErrUnknown
		}
		monthly, ok = exactNonNegativeInt(m["monthly_remaining"])
		if !ok {
			return 0, 0, ErrUnknown
		}
		return daily, monthly, nil
	}
	limits, limitsOK := objectField(m["limits"])
	used, usedOK := objectField(m["used"])
	if !limitsOK || !usedOK {
		return 0, 0, ErrUnknown
	}
	daily, err = remainingFrom(limits, used, "per_day", "day")
	if err != nil {
		return 0, 0, ErrUnknown
	}
	monthly, err = remainingFrom(limits, used, "per_month", "month")
	if err != nil {
		return 0, 0, ErrUnknown
	}
	return daily, monthly, nil
}

func exactNonNegativeInt(raw json.RawMessage) (int, bool) {
	var n int
	if len(raw) == 0 || json.Unmarshal(raw, &n) != nil || n < 0 {
		return 0, false
	}
	return n, true
}

func objectField(raw json.RawMessage) (map[string]json.RawMessage, bool) {
	var value map[string]json.RawMessage
	if len(raw) == 0 || json.Unmarshal(raw, &value) != nil || value == nil {
		return nil, false
	}
	return value, true
}

func remainingFrom(limits, used map[string]json.RawMessage, limitKey, usedKey string) (int, error) {
	limit, ok := exactNonNegativeInt(limits[limitKey])
	if !ok {
		return 0, ErrUnknown
	}
	spent, ok := exactNonNegativeInt(used[usedKey])
	if !ok || spent > limit {
		return 0, ErrUnknown
	}
	return limit - spent, nil
}

func normalizedFreeTier(tier string) string {
	switch strings.ToLower(strings.TrimSpace(tier)) {
	case "free", "community":
		return "community"
	default:
		return ""
	}
}

// TierRPM accepts only an authenticated Community/free account and obtains its
// exact minute cap from the same usage snapshot. Guest and sponsored tiers are
// outside this pipeline's registered free-tier contract.
func TierRPM(statusRaw, usageRaw []byte) (int, error) {
	var status struct {
		Tier          string `json:"tier"`
		Authenticated bool   `json:"authenticated"`
	}
	var usage struct {
		Tier          string `json:"tier"`
		Authenticated bool   `json:"authenticated"`
		Limits        struct {
			PerMinute int `json:"per_minute"`
		} `json:"limits"`
	}
	if json.Unmarshal(statusRaw, &status) != nil || json.Unmarshal(usageRaw, &usage) != nil {
		return 0, ErrUnknown
	}
	statusTier := normalizedFreeTier(status.Tier)
	usageTier := normalizedFreeTier(usage.Tier)
	if !status.Authenticated || !usage.Authenticated || statusTier == "" || statusTier != usageTier {
		return 0, ErrUnknown
	}
	if usage.Limits.PerMinute < 1 || usage.Limits.PerMinute > 60 {
		return 0, ErrUnknown
	}
	return usage.Limits.PerMinute, nil
}
