package ingest

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

type memoryStore struct {
	done                   map[string]Landing
	failLookup, failCommit bool
}

func (s *memoryStore) Completed(_ context.Context, key string) (bool, error) {
	if s.failLookup {
		return false, errors.New("database down")
	}
	_, ok := s.done[key]
	return ok, nil
}
func (s *memoryStore) CommitLanding(_ context.Context, land Landing) error {
	if s.failCommit {
		return errors.New("rollback")
	}
	s.done[land.JobID] = land
	return nil
}
func TestRunnerQuotaAndIdempotency(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	calls := 0
	f, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		id, _ := job["id"].(string)
		return worker.Response{ID: id, OK: true, Data: json.RawMessage(payload("["+one+"]", 1))}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: f, Store: s, Now: func() time.Time { return time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC) }}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	sum, e := r.RunBarsBackfill(context.Background(), []BackfillJob{job, job}, "vci")
	if e != nil || sum.Committed != 1 || sum.Skipped != 1 || calls != 1 || p.Remaining() != 0 {
		t.Fatalf("summary %+v err %v calls %d quota %d", sum, e, calls, p.Remaining())
	}
	for _, l := range s.done {
		if l.Source != "vci" || l.Bars.Rows[0].Symbol != "FPT" || len(l.SHA256) != 64 || l.FetchedAt.Year() != 2026 {
			t.Fatalf("bad landing %+v", l)
		}
	}
	// A later invocation with the same job does not spend another request.
	sum, e = r.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
	if e != nil || sum.Skipped != 1 || calls != 1 {
		t.Fatalf("resume %+v %v", sum, e)
	}
}
func TestRunnerFailsClosedOnStorageFaults(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	for _, mode := range []string{"lookup", "commit", "invalid", "vendor"} {
		t.Run(mode, func(t *testing.T) {
			p, _ := quota.NewPacer(1000, 1)
			calls := 0
			gate, _ := live.New(p, func(_ context.Context, j map[string]any) (worker.Response, error) {
				calls++
				if mode == "vendor" {
					return worker.Response{OK: false, Error: &struct {
						Type    string `json:"type"`
						Message string `json:"message"`
					}{Type: "RateLimitedError"}}, nil
				}
				data := payload("["+one+"]", 1)
				if mode == "invalid" {
					data = []byte(`{"bad":true}`)
				}
				return worker.Response{OK: true, Data: data}, nil
			})
			s := &memoryStore{done: map[string]Landing{}, failLookup: mode == "lookup", failCommit: mode == "commit"}
			r := Runner{Gateway: gate, Store: s, Now: time.Now}
			_, e := r.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
			if e == nil {
				t.Fatal("failure accepted")
			}
			if mode == "lookup" && (calls != 0 || p.Remaining() != 1) {
				t.Fatal("spent quota on failed lookup")
			}
			if mode != "lookup" && (calls != 1 || p.Remaining() != 0) {
				t.Fatal("not metered")
			}
			if len(s.done) != 0 {
				t.Fatal("wrote failed job")
			}
		})
	}
}
func TestRunnerCannotExecuteInHostedCI(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	p, _ := quota.NewPacer(60, 2)
	g, _ := live.New(p, func(context.Context, map[string]any) (worker.Response, error) {
		t.Fatal("vendor was called")
		return worker.Response{}, nil
	})
	r := Runner{Gateway: g, Store: &memoryStore{done: map[string]Landing{}}, Now: time.Now}
	_, err := r.RunBarsBackfill(context.Background(), []BackfillJob{{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}}, "vci")
	if !errors.Is(err, live.ErrDisabled) || p.Remaining() != 2 {
		t.Fatal(err)
	}
}
