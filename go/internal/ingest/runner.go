package ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
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
	// ReserveAttempt commits the allowance and job attempt BEFORE any vendor
	// call. It can return a later deadline to honor cross-process pacing.
	ReserveAttempt(context.Context, BackfillJob, string, string, time.Time) (time.Time, error)
	MarkDispatch(context.Context, string) error
	MarkOutcome(context.Context, string, string, string) error
	BlockInvalid(context.Context, string, string) error
	// QuarantineFrame atomically stores exact invalid vendor bytes and the BLOCKED
	// marker, without writing a single canonical price bar.
	QuarantineFrame(context.Context, string, string, string, json.RawMessage) error
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
	// BeforeCall refreshes a nearly expired durable quota guard from an
	// independently verified absolute usage report. Called only for unfinished
	// jobs, and always BEFORE the local pacer can reserve a call.
	BeforeCall func(context.Context) error
}

type RunSummary struct {
	Skipped, Committed, Blocked int
	BlockedPreview []string
}

// ErrExcessiveInvalidFrames is a systemic-source circuit breaker. Individual
// corrupt frames are quarantined, but a broken provider/adapter cannot
// exhaust an entire free-tier allowance by blocking the whole universe.
var ErrExcessiveInvalidFrames = errors.New("excessive invalid OHLCV frames: backfill stopped")

// RunBarsBackfill accepts an ordered capped plan. Each job goes exclusively
// through live.Gateway, so every actual vnstock call must reserve quota.
// Infrastructure, quota and vendor errors abort. Isolated invalid vendor frames
// are durably quarantined; a systemic invalid-frame pattern aborts.
func (r *Runner) RunBarsBackfill(ctx context.Context, jobs []BackfillJob, source string) (RunSummary, error) {
	var sum RunSummary
	if r == nil || r.Gateway == nil || r.Store == nil || r.Now == nil {
		return sum, errors.New("runner not configured")
	}
	if source == "" {
		return sum, errors.New("source is required")
	}
	invalidStreak := 0
	quarantine := func(jobID, symbol, reason string, raw json.RawMessage) error {
		if len(reason) > 120 {
			reason = reason[:120]
		}
		if err := r.Store.QuarantineFrame(ctx, jobID, source, reason, raw); err != nil {
			return fmt.Errorf("quarantine %s failed (stop): %w", symbol, err)
		}
		sum.Blocked++
		if len(sum.BlockedPreview) < 10 {
			sum.BlockedPreview = append(sum.BlockedPreview, symbol+": "+reason)
		}
		invalidStreak++
		examined := sum.Blocked + sum.Committed
		if invalidStreak >= 3 || (examined >= 20 && sum.Blocked*5 >= examined) {
			return fmt.Errorf("%w: blocked=%d committed=%d consecutive_invalid=%d last_symbol=%s",
				ErrExcessiveInvalidFrames, sum.Blocked, sum.Committed, invalidStreak, symbol)
		}
		return nil
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
		if r.BeforeCall != nil {
			if err := r.BeforeCall(ctx); err != nil {
				return sum, fmt.Errorf("pre-call quota verification: %w", err)
			}
		}
		reply, err := r.Gateway.CallRecorded(ctx, map[string]any{
			"id": jobID, "op": job.Route, "symbol": job.Symbol, "start": job.Start, "end": job.End, "source": source,
		}, live.CallAudit{
			Reserve: func(ctx context.Context, at time.Time) (time.Time, error) {
				return r.Store.ReserveAttempt(ctx, job, jobID, source, at)
			},
			Dispatch: func(ctx context.Context) error { return r.Store.MarkDispatch(ctx, jobID) },
			Finish: func(ctx context.Context, outcome, reason string) error {
				return r.Store.MarkOutcome(ctx, jobID, outcome, reason)
			},
		})
		if err != nil {
			return sum, fmt.Errorf("gateway: %w", err)
		}
		if reply.ID != jobID {
			if e := r.Store.BlockInvalid(ctx, jobID, "ResponseIDMismatch"); e != nil {
				return sum, errors.Join(errors.New("vendor response ID mismatch"), e)
			}
			return sum, errors.New("vendor response ID mismatch")
		}
		if !reply.OK {
			if reply.Error == nil {
				return sum, errors.New("vendor error without type")
			}
			return sum, fmt.Errorf("vendor route failed: %s", reply.Error.Type)
		}
		bars, err := NormalizeBars(job.Symbol, reply.Data)
		if err != nil {
			reason := "InvalidFrame: " + strings.TrimPrefix(err.Error(), ErrInvalidFrame.Error()+": ")
			if e := quarantine(jobID, job.Symbol, reason, reply.Data); e != nil {
				return sum, e
			}
			continue
		}
		// The provider must honor both bounds, even if its raw frame is otherwise valid.
		if bars.FirstDate < job.Start || bars.LastDate > job.End {
			reason := fmt.Sprintf("OutsideRequestedRange: first=%s last=%s", bars.FirstDate, bars.LastDate)
			if e := quarantine(jobID, job.Symbol, reason, reply.Data); e != nil {
				return sum, e
			}
			continue
		}
		sha := sha256.Sum256(reply.Data)
		landing := Landing{JobID: jobID, Source: source, FetchedAt: r.Now().UTC(), SHA256: hex.EncodeToString(sha[:]), Raw: append(json.RawMessage(nil), reply.Data...), Bars: bars}
		if err := r.Store.CommitLanding(ctx, landing); err != nil {
			return sum, fmt.Errorf("transactional landing failed: %w", err)
		}
		sum.Committed++
		invalidStreak = 0
	}
	return sum, nil
}
