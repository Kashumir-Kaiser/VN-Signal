package ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
)

// Landing retains unmodified vendor JSON and its digest. Store.CommitLanding
// must atomically write raw landing, validated core rows and the completed job.
// The serving snapshot MUST NOT be updated by this component.
type Landing struct {
	JobID     string
	Source    string
	FetchedAt time.Time
	SHA256    string
	Raw       json.RawMessage
	Bars      BarsResult
}

type LandingStore interface {
	// Completed must consult durable storage, never an in-process map in production.
	Completed(context.Context, string) (bool, error)
	// CommitLanding must transactionally persist a landing, its canonical bars,
	// and mark the job complete. It must be idempotent on JobID.
	CommitLanding(context.Context, Landing) error
}

type Runner struct {
	Gateway *live.Gateway
	Store   LandingStore
	Now     func() time.Time
}

type RunSummary struct{ Skipped, Committed int }

// RunBarsBackfill accepts an ordered capped plan. Each job goes exclusively
// through live.Gateway, so every actual vnstock call must reserve quota.
// Any failure immediately aborts without advancing the durable completion marker.
func (r *Runner) RunBarsBackfill(ctx context.Context, jobs []BackfillJob, source string) (RunSummary, error) {
	var sum RunSummary
	if r == nil || r.Gateway == nil || r.Store == nil || r.Now == nil {
		return sum, errors.New("runner not configured")
	}
	if source == "" {
		return sum, errors.New("source is required")
	}
	for _, job := range jobs {
		if err := ctx.Err(); err != nil {
			return sum, err
		}
		if job.Route != "equity_ohlcv" || job.Symbol == "" || job.Start == "" || job.End == "" {
			return sum, errors.New("unsupported backfill job")
		}
		jobID := fmt.Sprintf("%s:%s:%s:%s:%s", job.Route, job.Symbol, source, job.Start, job.End)
		already, err := r.Store.Completed(ctx, jobID)
		if err != nil {
			return sum, fmt.Errorf("completion lookup (fail closed): %w", err)
		}
		if already {
			sum.Skipped++
			continue
		}
		reply, err := r.Gateway.Call(ctx, map[string]any{
			"id": jobID, "op": job.Route, "symbol": job.Symbol, "start": job.Start, "end": job.End, "source": source,
		})
		if err != nil {
			return sum, fmt.Errorf("gateway: %w", err)
		}
		if !reply.OK {
			if reply.Error == nil {
				return sum, errors.New("vendor error without type")
			}
			return sum, fmt.Errorf("vendor route failed: %s", reply.Error.Type)
		}
		bars, err := NormalizeBars(job.Symbol, reply.Data)
		if err != nil {
			return sum, err
		}
		// Reject unexpected history if the provider changes or ignores requested dates.
		if bars.FirstDate < job.Start || bars.LastDate > job.End {
			return sum, fmt.Errorf("vendor bars outside requested range for %s", job.Symbol)
		}
		sha := sha256.Sum256(reply.Data)
		landing := Landing{JobID: jobID, Source: source, FetchedAt: r.Now().UTC(), SHA256: hex.EncodeToString(sha[:]), Raw: append(json.RawMessage(nil), reply.Data...), Bars: bars}
		if err := r.Store.CommitLanding(ctx, landing); err != nil {
			return sum, fmt.Errorf("transactional landing failed: %w", err)
		}
		sum.Committed++
	}
	return sum, nil
}
