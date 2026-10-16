package live

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

func TestUnknownQuotaBlocks(t *testing.T) {
	for _, tc := range [][3]int{{-1, 100, 2}, {10, -1, 2}, {10, 10, 0}} {
		b, err := quota.Budget(tc[0], tc[1], tc[2])
		if !errors.Is(err, quota.ErrUnknown) || b != 0 {
			t.Fatalf("accepted unknown %+v", tc)
		}
	}
	// The usage CLI returns percentages on some tiers. Percent-based readings are
	// never coerced into a remaining-call count; no pacer can be created.
	_, _, err := quota.ParseRemaining([]byte(`{"daily_remaining":"83%","monthly_remaining":"90%"}`))
	if !errors.Is(err, quota.ErrUnknown) {
		t.Fatal(err)
	}
}
func TestReservedAndWaitedBeforeEveryCall(t *testing.T) {
	p, _ := quota.NewPacer(60, 2)
	var calls atomic.Int32
	var waited atomic.Int32
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		calls.Add(1)
		return worker.Response{}, errors.New("rate limited")
	})
	frozen := time.Now()
	g.now = func() time.Time { return frozen }
	g.sleep = func(ctx context.Context, d time.Duration) error {
		if d > 0 {
			waited.Add(1)
		}
		return ctx.Err()
	}
	for i := 0; i < 3; i++ {
		_, _ = g.Call(context.Background(), map[string]any{"op": "equity_ohlcv", "id": "x"})
	}
	if calls.Load() != 2 || waited.Load() != 1 || p.Remaining() != 0 {
		t.Fatalf("calls %d waited %d remaining %d", calls.Load(), waited.Load(), p.Remaining())
	}
}
func TestLiveGateConcurrentReservations(t *testing.T) {
	p, _ := quota.NewPacer(60000, 25)
	var count atomic.Int32
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		count.Add(1)
		return worker.Response{}, nil
	})
	// Override for deterministic test; Reserve itself must be race-safe.
	g.sleep = func(context.Context, time.Duration) error { return nil }
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _ = g.Call(context.Background(), map[string]any{"op": "equity_list", "id": "x"})
		}()
	}
	wg.Wait()
	if count.Load() != 25 || p.Remaining() != 0 {
		t.Fatalf("calls %d remain %d", count.Load(), p.Remaining())
	}
}
func TestDisabledInCI(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	p, _ := quota.NewPacer(60, 2)
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		t.Fatal("called")
		return worker.Response{}, nil
	})
	_, err := g.Call(context.Background(), map[string]any{"op": "equity_list"})
	if !errors.Is(err, ErrDisabled) || p.Remaining() != 2 {
		t.Fatal(err)
	}
}
func TestCancellationDuringWaitConsumesCall(t *testing.T) {
	p, _ := quota.NewPacer(60, 2)
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		t.Fatal("called")
		return worker.Response{}, nil
	})
	g.now = func() time.Time { return time.Now().Add(10 * time.Second) }
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := g.Call(ctx, map[string]any{"op": "equity_list"})
	if !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}

func TestReservationWaitIsActuallyAwaited(t *testing.T) {
	p, _ := quota.NewPacer(20, 2)
	var count atomic.Int32
	release := make(chan struct{})
	started := make(chan struct{})
	g, _ := New(p, func(context.Context, map[string]any) (worker.Response, error) {
		count.Add(1)
		return worker.Response{}, nil
	})
	fixed := time.Now()
	g.now = func() time.Time { return fixed }
	g.sleep = func(ctx context.Context, d time.Duration) error {
		if d <= 0 {
			return nil
		}
		close(started)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-release:
			return nil
		}
	}
	if _, err := g.Call(context.Background(), map[string]any{"id": "one", "op": "equity_list"}); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := g.Call(context.Background(), map[string]any{"id": "two", "op": "equity_list"})
		done <- err
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("no reservation wait")
	}
	if count.Load() != 1 {
		t.Fatal("called vendor before reservation became ready")
	}
	close(release)
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("wait did not resume")
	}
	if count.Load() != 2 {
		t.Fatal("second call not executed")
	}
}
