package live

import (
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

func TestAuditPreventsUnauditedDispatch(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	for _, broken := range []string{"missing", "reserve", "dispatch", "finish"} {
		t.Run(broken, func(t *testing.T) {
			p, _ := quota.NewPacer(60, 1)
			var called atomic.Int32
			g, _ := New(p, func(_ context.Context, _ map[string]any) (worker.Response, error) {
				called.Add(1)
				return worker.Response{OK: true}, nil
			})
			g.sleep = func(context.Context, time.Duration) error { return nil }
			reserved, dispatched, finished := 0, 0, 0
			a := CallAudit{
				Reserve: func(_ context.Context, at time.Time) (time.Time, error) {
					reserved++
					if broken == "reserve" {
						return at, errors.New("db down")
					}
					return at, nil
				},
				Dispatch: func(context.Context) error {
					dispatched++
					if broken == "dispatch" {
						return errors.New("db down")
					}
					return nil
				},
				Finish: func(_ context.Context, _, _ string) error {
					finished++
					if broken == "finish" {
						return errors.New("db down")
					}
					return nil
				},
			}
			if broken == "missing" {
				a.Reserve = nil
			}
			_, e := g.CallRecorded(context.Background(), map[string]any{"op": "equity_ohlcv"}, a)
			if e == nil {
				t.Fatal("accepted failed audit")
			}
			if broken == "missing" && (p.Remaining() != 1 || reserved != 0) {
				t.Fatal("unaudited call spent quota")
			}
			if broken == "reserve" && (called.Load() != 0 || dispatched != 0 || finished != 0 || p.Remaining() != 0) {
				t.Fatal("vendor called despite missing durable reservation")
			}
			if broken == "dispatch" && (called.Load() != 0 || reserved != 1 || dispatched != 1 || finished != 1) {
				t.Fatal("dispatch failure escaped audit")
			}
			if broken == "finish" && (called.Load() != 1 || finished != 1) {
				t.Fatal("success accepted without outcome")
			}
		})
	}
}
func TestRecordedWaitAndCanceledReservation(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60, 1)
	var called atomic.Int32
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		called.Add(1)
		return worker.Response{OK: true}, nil
	})
	var observed time.Duration
	g.sleep = func(ctx context.Context, d time.Duration) error { observed = d; return context.Canceled }
	var status string
	a := CallAudit{
		Reserve:  func(_ context.Context, at time.Time) (time.Time, error) { return at.Add(30 * time.Second), nil },
		Dispatch: func(context.Context) error { t.Fatal("dispatch after failed wait"); return nil },
		Finish:   func(_ context.Context, s, _ string) error { status = s; return nil },
	}
	_, err := g.CallRecorded(context.Background(), map[string]any{"op": "equity_ohlcv"}, a)
	if !errors.Is(err, context.Canceled) || status != "CANCELLED" || called.Load() != 0 || p.Remaining() != 0 || observed < 29*time.Second {
		t.Fatalf("err=%v status=%s calls=%d wait=%v", err, status, called.Load(), observed)
	}
}
func TestRecordedVendorErrorIsAudited(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60, 1)
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		return worker.Response{ID: "x", OK: false, Error: &struct {
			Type    string `json:"type"`
			Message string `json:"message"`
		}{Type: "RateLimitedError"}}, nil
	})
	g.sleep = func(context.Context, time.Duration) error { return nil }
	var outcome, reason string
	a := CallAudit{Reserve: func(_ context.Context, at time.Time) (time.Time, error) { return at, nil }, Dispatch: func(context.Context) error { return nil }, Finish: func(_ context.Context, s, r string) error { outcome, reason = s, r; return nil }}
	resp, err := g.CallRecorded(context.Background(), map[string]any{"op": "equity_ohlcv"}, a)
	if err != nil || resp.OK || outcome != "RATE_LIMITED" || reason != "RateLimitedError" {
		t.Fatalf("err=%v outcome=%s reason=%s", err, outcome, reason)
	}
}
func TestAuditCannotShortenRateLimit(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60, 1)
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		t.Fatal("vendor called")
		return worker.Response{}, nil
	})
	a := CallAudit{Reserve: func(_ context.Context, at time.Time) (time.Time, error) { return at.Add(-time.Minute), nil }, Dispatch: func(context.Context) error { return nil }, Finish: func(context.Context, string, string) error { return nil }}
	_, err := g.CallRecorded(context.Background(), map[string]any{"op": "equity_list"}, a)
	if err == nil {
		t.Fatal("accepted shortened database pacing")
	}
}
