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
	failLookup, failCommit, failQuarantine bool
	attempts               map[string]string
	quarantined            map[string]json.RawMessage
	reasons                map[string]string
}

func (s *memoryStore) ReserveAttempt(_ context.Context, _ BackfillJob, key, _ string, at time.Time) (time.Time, error) {
	if s.attempts == nil {
		s.attempts = map[string]string{}
	}
	if s.attempts[key] != "" {
		return at, errors.New("duplicate concurrent attempt")
	}
	s.attempts[key] = "RESERVED"
	return at, nil
}
func (s *memoryStore) MarkDispatch(_ context.Context, key string) error {
	if s.attempts[key] != "RESERVED" {
		return errors.New("not reserved")
	}
	s.attempts[key] = "SENT"
	return nil
}
func (s *memoryStore) MarkOutcome(_ context.Context, key, outcome, _ string) error {
	if s.attempts[key] != "SENT" && s.attempts[key] != "RESERVED" {
		return errors.New("not dispatched")
	}
	s.attempts[key] = ""
	return nil
}
func (s *memoryStore) BlockInvalid(_ context.Context, key, _ string) error {
	if s.attempts[key] != "" {
		s.attempts[key] = "BLOCKED"
	}
	return nil
}
func (s *memoryStore) QuarantineFrame(_ context.Context, key, _, reason string, raw json.RawMessage) error {
	if s.failQuarantine {
		return errors.New("cannot persist quarantine")
	}
	if s.quarantined == nil {
		s.quarantined = map[string]json.RawMessage{}
		s.reasons = map[string]string{}
	}
	s.quarantined[key] = append(json.RawMessage(nil), raw...)
	s.reasons[key] = reason
	s.attempts[key] = "BLOCKED"
	return nil
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
	for _, mode := range []string{"lookup", "commit", "invalid", "vendor", "quarantine_error"} {
		t.Run(mode, func(t *testing.T) {
			p, _ := quota.NewPacer(1000, 1)
			calls := 0
			gate, _ := live.New(p, func(_ context.Context, j map[string]any) (worker.Response, error) {
				calls++
				if mode == "vendor" {
					return worker.Response{ID: j["id"].(string), OK: false, Error: &struct {
						Type    string `json:"type"`
						Message string `json:"message"`
					}{Type: "RateLimitedError"}}, nil
				}
				data := payload("["+one+"]", 1)
				if mode == "invalid" || mode == "quarantine_error" {
					data = []byte(`{"bad":true}`)
				}
				return worker.Response{ID: j["id"].(string), OK: true, Data: data}, nil
			})
			s := &memoryStore{done: map[string]Landing{}, failLookup: mode == "lookup", failCommit: mode == "commit", failQuarantine: mode == "quarantine_error"}
			r := Runner{Gateway: gate, Store: s, Now: time.Now}
			summary, e := r.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
			if mode == "invalid" {
				if e != nil || summary.Blocked != 1 || len(s.quarantined) != 1 {
					t.Fatalf("invalid frame not quarantined: summary=%+v err=%v", summary, e)
				}
			} else if e == nil {
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

// The quota refresh hook must precede any pacer reservation or vendor call.
// Already-completed jobs never require new account usage checks.
func TestRunnerBeforeCallFailsClosedAndSkipsCompleted(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	calls, checks := 0, 0
	gate, _ := live.New(p, func(context.Context, map[string]any) (worker.Response, error) {
		calls++
		t.Fatal("worker invoked despite refused quota refresh")
		return worker.Response{}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	runner := Runner{Gateway: gate, Store: s, Now: time.Now, BeforeCall: func(context.Context) error {
		checks++
		return quota.ErrUnknown
	}}
	if _, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci"); !errors.Is(err, quota.ErrUnknown) {
		t.Fatalf("missing quota was accepted: %v", err)
	}
	if calls != 0 || checks != 1 || p.Remaining() != 1 || len(s.attempts) != 0 {
		t.Fatalf("called worker or reserved quota: worker=%d checks=%d remaining=%d", calls, checks, p.Remaining())
	}
	key := "equity_ohlcv:FPT:vci:2026-10-15:2026-10-16"
	s.done[key] = Landing{JobID: key}
	got, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
	if err != nil || got.Skipped != 1 || checks != 1 || calls != 0 {
		t.Fatalf("completed job consumed quota check: %+v err=%v checks=%d", got, err, checks)
	}
}

func TestRunnerQuarantinesIsolatedCorruptionAndContinues(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 5)
	calls := 0
	g, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		id := job["id"].(string)
		if job["symbol"] == "AAA" || job["symbol"] == "AAC" {
			return worker.Response{ID: id, OK: true, Data: json.RawMessage(payload(`[{"time":"2026-10-15","open":0,"high":105,"low":99,"close":103,"volume":100}]`, 1))}, nil
		}
		return worker.Response{ID: id, OK: true, Data: json.RawMessage(payload("["+one+"]", 1))}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: g, Store: s, Now: time.Now}
	jobs := []BackfillJob{}
	for _, symbol := range []string{"AAA", "AAB", "AAC", "AAD"} {
		jobs = append(jobs, BackfillJob{Route: "equity_ohlcv", Symbol: symbol, Start: "2026-10-15", End: "2026-10-16"})
	}
	summary, err := r.RunBarsBackfill(context.Background(), jobs, "vci")
	if err != nil || summary.Blocked != 2 || summary.Committed != 2 || calls != 4 ||
		len(s.quarantined) != 2 || len(s.done) != 2 || p.Remaining() != 1 {
		t.Fatalf("summary=%+v err=%v calls=%d", summary, err, calls)
	}
	if len(summary.BlockedPreview) != 2 || s.reasons["equity_ohlcv:AAA:vci:2026-10-15:2026-10-16"] == "" {
		t.Fatalf("missing quarantine diagnostic: %+v", summary)
	}
}
func TestRunnerStopsSystemicCorruption(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 6)
	calls := 0
	g, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		return worker.Response{ID: job["id"].(string), OK: true, Data: json.RawMessage(payload(`[{"time":"2026-10-15","open":0,"high":105,"low":99,"close":103,"volume":100}]`, 1))}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: g, Store: s, Now: time.Now}
	jobs := []BackfillJob{}
	for _, symbol := range []string{"AAA", "AAB", "AAC", "AAD", "AAE", "AAF"} {
		jobs = append(jobs, BackfillJob{Route: "equity_ohlcv", Symbol: symbol, Start: "2026-10-15", End: "2026-10-16"})
	}
	sum, err := r.RunBarsBackfill(context.Background(), jobs, "vci")
	if !errors.Is(err, ErrExcessiveInvalidFrames) || calls != 3 || sum.Blocked != 3 ||
		len(s.quarantined) != 3 || p.Remaining() != 3 || len(s.done) != 0 {
		t.Fatalf("systemic corruption not stopped: summary=%+v err=%v calls=%d", sum, err, calls)
	}
}
