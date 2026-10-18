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

const validIndex = `{"columns":["time","open","high","low","close","volume"],"count":1,"rows":[{"time":"2026-10-16","open":100,"high":102,"low":99,"close":101,"volume":200}],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}`
const validIndexVCI = `{"columns":["time","open","high","low","close","volume"],"count":1,"rows":[{"time":"2026-10-16","open":100,"high":102,"low":99,"close":101,"volume":200}],"attributes":{"route":"market.index.ohlcv","source":"vci"}}`

func TestIndexFrameCapabilityIsNarrowAndStrict(t *testing.T) {
	f, err := AnalyzeIndexBarsForSource("VNINDEX", "kbs", []byte(validIndex))
	if err != nil || len(f.Rows) != 1 || f.FirstDate != "2026-10-16" {
		t.Fatalf("frame=%+v err=%v", f, err)
	}
	if f, err := AnalyzeIndexBarsForSource("VNINDEX", "vci", []byte(validIndexVCI)); err != nil || len(f.Rows) != 1 {
		t.Fatalf("VCI frame=%+v err=%v", f, err)
	}
	for _, tc := range []struct{ symbol, source, raw string }{{"VN30", "kbs", validIndex}, {"VNINDEX", "vci", validIndex}, {"VNINDEX", "mas", validIndex}, {"VNINDEX", "kbs", `{"columns":[],"count":0,"rows":[],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}`}} {
		if _, err := AnalyzeIndexBarsForSource(tc.symbol, tc.source, []byte(tc.raw)); err == nil {
			t.Fatalf("accepted unsupported input: %+v", tc)
		}
	}
}

func TestRunIndexBackfillUsesRecordedGatewayAndOnlyProbeVerifiedSymbol(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	calls := 0
	g, _ := live.New(p, func(_ context.Context, j map[string]any) (worker.Response, error) {
		calls++
		if j["op"] != "index_ohlcv" || j["symbol"] != "VNINDEX" || j["source"] != "kbs" {
			t.Fatalf("wrong request: %#v", j)
		}
		return worker.Response{ID: j["id"].(string), OK: true, Data: json.RawMessage(validIndex)}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: g, Store: s, Now: time.Now}
	job := BackfillJob{Route: "index_ohlcv", Symbol: "VNINDEX", Start: "2026-10-16", End: "2026-10-16"}
	if _, err := r.RunIndexBackfill(context.Background(), []BackfillJob{{Route: "index_ohlcv", Symbol: "VN30", Start: job.Start, End: job.End}}); err == nil || calls != 0 || p.Remaining() != 1 {
		t.Fatal("unprobed index was dispatched")
	}
	got, err := r.RunIndexBackfill(context.Background(), []BackfillJob{job})
	if err != nil || got.Committed != 1 || calls != 1 || p.Remaining() != 0 {
		t.Fatalf("summary=%+v calls=%d left=%d err=%v", got, calls, p.Remaining(), err)
	}
	got, err = r.RunIndexBackfill(context.Background(), []BackfillJob{job})
	if err != nil || got.Skipped != 1 || calls != 1 {
		t.Fatalf("idempotency failed: %+v calls=%d err=%v", got, calls, err)
	}
}

func TestRunIndexBackfillSupportsVCISource(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	g, _ := live.New(p, func(_ context.Context, j map[string]any) (worker.Response, error) {
		if j["source"] != "vci" {
			t.Fatalf("wrong provider: %#v", j)
		}
		return worker.Response{ID: j["id"].(string), OK: true, Data: json.RawMessage(validIndexVCI)}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: g, Store: s, Now: time.Now}
	job := BackfillJob{Route: "index_ohlcv", Symbol: "VNINDEX", Source: "vci", Start: "2026-10-16", End: "2026-10-16"}
	got, err := r.RunIndexBackfill(context.Background(), []BackfillJob{job})
	key := "index_ohlcv:VNINDEX:vci:2026-10-16:2026-10-16"
	if err != nil || got.Committed != 1 || s.done[key].Source != "vci" {
		t.Fatalf("summary=%+v landing=%+v err=%v", got, s.done[key], err)
	}
}

func TestRunIndexBackfillFailsClosedOnQuotaCheck(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	g, _ := live.New(p, func(context.Context, map[string]any) (worker.Response, error) {
		t.Fatal("called without quota")
		return worker.Response{}, errors.New("unexpected")
	})
	r := Runner{Gateway: g, Store: &memoryStore{done: map[string]Landing{}}, Now: time.Now, BeforeCall: func(context.Context) error { return quota.ErrUnknown }}
	_, err := r.RunIndexBackfill(context.Background(), []BackfillJob{{Route: "index_ohlcv", Symbol: "VNINDEX", Start: "2026-10-16", End: "2026-10-16"}})
	if !errors.Is(err, quota.ErrUnknown) || p.Remaining() != 1 {
		t.Fatalf("err=%v remaining=%d", err, p.Remaining())
	}
}

func TestRunIndexBackfillQuarantinesInvalidResponse(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	p, _ := quota.NewPacer(60000, 1)
	g, _ := live.New(p, func(_ context.Context, j map[string]any) (worker.Response, error) {
		return worker.Response{ID: j["id"].(string), OK: true, Data: json.RawMessage(`{"bad":true}`)}, nil
	})
	s := &memoryStore{done: map[string]Landing{}}
	r := Runner{Gateway: g, Store: s, Now: time.Now}
	_, err := r.RunIndexBackfill(context.Background(), []BackfillJob{{Route: "index_ohlcv", Symbol: "VNINDEX", Start: "2026-10-16", End: "2026-10-16"}})
	if err == nil || len(s.quarantined) != 1 || string(s.quarantined["index_ohlcv:VNINDEX:kbs:2026-10-16:2026-10-16"]) != `{"bad":true}` {
		t.Fatalf("err=%v quarantine=%q", err, s.quarantined)
	}
}
