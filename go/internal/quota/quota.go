// Package quota enforces a conservative call budget. Unknown capacity stops work.
package quota

import (
	"errors"
	"math"
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
