// Package live is the sole authorised gateway for quota-consuming vnstock calls.
// Keep Python's _fetch behind this metered gateway in production Go code.
package live

import (
	"context"
	"errors"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type InvokeFunc func(context.Context, map[string]any) (worker.Response, error)
type Gateway struct {
	pacer  *quota.Pacer
	invoke InvokeFunc
	now    func() time.Time
	sleep  func(context.Context, time.Duration) error
}

func New(p *quota.Pacer, call InvokeFunc) (*Gateway, error) {
	if p == nil || call == nil {
		return nil, quota.ErrUnknown
	}
	return &Gateway{pacer: p, invoke: call, now: time.Now, sleep: wait}, nil
}
func wait(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

var routes = map[string]bool{"equity_list": true, "market_calendar": true, "equity_ohlcv": true, "index_ohlcv": true, "income_statement": true, "balance_sheet": true, "cash_flow": true}
var ErrDisabled = errors.New("live market calls disabled in this environment")

func (g *Gateway) Call(ctx context.Context, job map[string]any) (worker.Response, error) {
	var empty worker.Response
	if os.Getenv("VNPIPE_DISABLE_LIVE") == "1" {
		return empty, ErrDisabled
	}
	op, _ := job["op"].(string)
	if !routes[op] {
		return empty, errors.New("unsupported live route")
	}
	if err := ctx.Err(); err != nil {
		return empty, err
	}
	at, err := g.pacer.Reserve(g.now())
	if err != nil {
		return empty, err
	}
	// Reservation is irrevocable, including if context cancels, worker errors,
	// rate limits, or a transient API failure occurs.
	if err := g.sleep(ctx, time.Until(at)); err != nil {
		return empty, err
	}
	if err := ctx.Err(); err != nil {
		return empty, err
	}
	return g.invoke(ctx, job)
}
