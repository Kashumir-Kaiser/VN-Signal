package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type fakeGuard struct {
	due    bool
	err    error
	writes int
	last   ingest.QuotaSnapshot
	reject error
}

func (s *fakeGuard) QuotaRefreshRequired(_ context.Context, lead time.Duration) (bool, error) {
	if lead != 90*time.Second {
		panic("wrong deadline")
	}
	return s.due, s.err
}
func (s *fakeGuard) InstallQuota(_ context.Context, q ingest.QuotaSnapshot) error {
	s.writes++
	s.last = q
	return s.reject
}
func TestQuotaRefreshOnlyWhenRequiredAndVerified(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1") // mock callbacks cannot call vnstock
	ctx := context.Background()
	s := &fakeGuard{}
	reads := 0
	read := func(context.Context) (ingest.QuotaSnapshot, error) {
		reads++
		return ingest.QuotaSnapshot{VerifiedRPM: 60, ObservedAt: time.Now()}, nil
	}
	if err := ensureFreshQuota(ctx, s, 60, read); err != nil || reads != 0 || s.writes != 0 {
		t.Fatalf("not due: %v", err)
	}
	s.due = true
	if err := ensureFreshQuota(ctx, s, 60, read); err != nil || reads != 1 || s.writes != 1 {
		t.Fatalf("due: %v", err)
	}
	s.reject = errors.New("database down")
	if err := ensureFreshQuota(ctx, s, 60, read); err == nil {
		t.Fatal("DB failure accepted")
	}
	s.reject = nil
	if err := ensureFreshQuota(ctx, s, 20, read); err == nil || s.writes != 2 {
		t.Fatal("changed tier accepted")
	}
	if err := ensureFreshQuota(ctx, s, 60, func(context.Context) (ingest.QuotaSnapshot, error) { return ingest.QuotaSnapshot{}, quota.ErrUnknown }); err == nil {
		t.Fatal("missing report accepted")
	}
	s.err = ingest.ErrNoQuotaSnapshot
	if err := ensureFreshQuota(ctx, s, 60, read); !errors.Is(err, ingest.ErrNoQuotaSnapshot) {
		t.Fatalf("missing guard: %v", err)
	}
}
func TestObserveAbsoluteQuotaFailsClosed(t *testing.T) {
	mk := func(report string) func(context.Context, map[string]any) (worker.Response, error) {
		return func(_ context.Context, j map[string]any) (worker.Response, error) {
			if j["op"] != "probe" || j["active"] != false {
				t.Fatal("attempted live call")
			}
			return worker.Response{ID: j["id"].(string), OK: true, Data: json.RawMessage(report)}, nil
		}
	}
	valid := `{"status":{"tier":"community","authenticated":true},"usage":{"tier":"community","authenticated":true,"limits":{"per_minute":60,"per_day":300,"per_month":1000},"used":{"day":240,"month":700}}}`
	v, err := observeAbsoluteQuota(context.Background(), 12, mk(valid))
	if err != nil || v.VerifiedRPM != 60 || v.DailyRemaining != 60 || v.MonthlyRemaining != 300 || v.ObservedAt.IsZero() {
		t.Fatalf("valid report: %+v %v", v, err)
	}
	for _, bad := range []string{
		`{}`,
		`{"status":{"tier":"community","authenticated":true},"usage":{"daily_remaining":"80%","monthly_remaining":100}}`,
		`{"status":{"tier":"paid","authenticated":true},"usage":{"tier":"paid","authenticated":true,"limits":{"per_minute":60,"per_day":300,"per_month":1000},"used":{"day":0,"month":0}}}`,
		`{"status":{"tier":"guest","authenticated":false},"usage":{"tier":"guest","authenticated":false,"limits":{"per_minute":10,"per_day":300,"per_month":1000},"used":{"day":0,"month":0}}}`,
	} {
		if _, err := observeAbsoluteQuota(context.Background(), 12, mk(bad)); err == nil {
			t.Fatalf("invalid quota accepted: %s", bad)
		}
	}
	if _, err := observeAbsoluteQuota(context.Background(), 0, mk(valid)); err == nil {
		t.Fatal("missing sessions accepted")
	}
	_, err = observeAbsoluteQuota(context.Background(), 12, func(context.Context, map[string]any) (worker.Response, error) {
		return worker.Response{ID: "wrong", OK: true, Data: json.RawMessage(valid)}, nil
	})
	if err == nil {
		t.Fatal("wrong worker response ID accepted")
	}
}
