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

// ParseRemaining accepts only exact integer absolute counts from the capability
// report. A percent, unknown field, missing key or approximate reading fails closed.
func ParseRemaining(raw []byte) (daily, monthly int, err error) {
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return 0, 0, ErrUnknown
	}
	for i, k := range []string{"daily_remaining", "monthly_remaining"} {
		v, ok := m[k]
		if !ok {
			return 0, 0, ErrUnknown
		}
		var n int
		if json.Unmarshal(v, &n) != nil || n < 0 {
			return 0, 0, ErrUnknown
		}
		if i == 0 {
			daily = n
		} else {
			monthly = n
		}
	}
	return daily, monthly, nil
}

// TierRPM returns only supported documented free-tier request rates.
// Unknown plans or unstructured CLI output never enable live ingestion.
func TierRPM(raw []byte) (int, error) {
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return 0, ErrUnknown
	}
	var tier string
	if json.Unmarshal(m["tier"], &tier) != nil {
		return 0, ErrUnknown
	}
	switch strings.ToLower(strings.TrimSpace(tier)) {
	case "guest":
		return 20, nil
	case "community":
		return 60, nil
	default:
		return 0, ErrUnknown
	}
}
