package live

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

// CallAudit is a fail-closed, durable call boundary. Each hook MUST commit its
// update before returning. Reserve must be persisted before the vendor call and
// may return a later timestamp to enforce database-wide pacing after a restart.
// The reservation is never refunded when dispatch or invocation fails.
type CallAudit struct {
	Reserve  func(context.Context, time.Time) (time.Time, error)
	Dispatch func(context.Context) error
	Finish   func(context.Context, string, string) error
}

func (a CallAudit) valid() bool {
	return a.Reserve != nil && a.Dispatch != nil && a.Finish != nil
}

// CallRecorded is the only supported entry point for durable ingestion. A
// failed audit hook prevents dispatch, or prevents ingest completion when the
// outcome cannot be recorded. Finish is attempted even after cancellation,
// using a bounded independent context to preserve the reservation ledger.
func (g *Gateway) CallRecorded(ctx context.Context, job map[string]any, a CallAudit) (worker.Response, error) {
	var empty worker.Response
	if !a.valid() {
		return empty, errors.New("complete durable audit required")
	}
	if g == nil || g.pacer == nil || g.invoke == nil {
		return empty, errors.New("unconfigured gateway")
	}
	if err := g.preflight(ctx, job); err != nil {
		return empty, err
	}
	at, err := g.pacer.Reserve(g.now())
	if err != nil {
		return empty, err
	}
	durableAt, err := a.Reserve(ctx, at)
	if err != nil {
		// A failed storage write never authorizes an external call. The local
		// quota is still spent, conservatively.
		return empty, fmt.Errorf("reservation not durable: %w", err)
	}
	if durableAt.Before(at) {
		return empty, errors.New("database attempted to shorten pacer wait")
	}
	finish := func(status, reason string) error {
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		if e := a.Finish(cleanupCtx, status, reason); e != nil {
			return fmt.Errorf("record %s outcome: %w", status, e)
		}
		return nil
	}
	if err := g.sleep(ctx, time.Until(durableAt)); err != nil {
		if e := finish("CANCELLED", "WaitInterrupted"); e != nil {
			return empty, errors.Join(err, e)
		}
		return empty, err
	}
	if err := ctx.Err(); err != nil {
		if e := finish("CANCELLED", "ContextCancelled"); e != nil {
			return empty, errors.Join(err, e)
		}
		return empty, err
	}
	if err := a.Dispatch(ctx); err != nil {
		if e := finish("CANCELLED", "DispatchAuditFailure"); e != nil {
			return empty, errors.Join(err, e)
		}
		return empty, fmt.Errorf("dispatch not durable: %w", err)
	}
	reply, callErr := g.invoke(ctx, job)
	status, reason := "SUCCEEDED", ""
	if callErr != nil {
		status, reason = "FAILED", "WorkerFailure"
	} else if !reply.OK {
		status, reason = "FAILED", "VendorFailure"
		if reply.Error != nil {
			reason = reply.Error.Type
			if reason == "RateLimitedError" {
				status = "RATE_LIMITED"
			}
		}
	}
	if e := finish(status, reason); e != nil {
		return empty, errors.Join(callErr, e)
	}
	return reply, callErr
}
