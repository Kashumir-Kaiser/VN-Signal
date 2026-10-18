package ingest

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestCommitCrossSourceLandingRequiresKBSBytesAndFrame(t *testing.T) {
	rows := `[{"time":"2026-10-16","open":100,"high":101,"low":99,"close":100,"volume":10}]`
	raw := payloadWithAttribution(rows, 1, `{"source":"KBS","route":"equity_ohlcv","source_name":"KBS","organisation":"Provider K"}`)
	frame, err := AnalyzeMarketBarsForSource("FPT", "kbs", raw)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(raw)
	item := MarketLanding{Landing: Landing{
		JobID: "cross-source-job", Source: "vci", FetchedAt: time.Now().UTC(),
		SHA256: hex.EncodeToString(digest[:]), Raw: json.RawMessage(raw), Bars: frame.Bars,
	}, Frame: frame}

	// All validation is local and occurs before any DB access.
	if _, err = (*PostgresStore)(nil).CommitCrossSourceLanding(context.Background(), item); err == nil || !strings.Contains(err.Error(), "invalid cross-source") {
		t.Fatalf("missing store accepted or wrong error: %v", err)
	}
	badChecksum := item
	badChecksum.Landing.SHA256 = strings.Repeat("0", 64)
	if _, err = (*PostgresStore)(nil).CommitCrossSourceLanding(context.Background(), badChecksum); err == nil || !strings.Contains(err.Error(), "checksum") {
		t.Fatalf("bad checksum accepted or wrong error: %v", err)
	}
	badFrame := item
	badFrame.Frame.SourceRows++
	if _, err = (*PostgresStore)(nil).CommitCrossSourceLanding(context.Background(), badFrame); err == nil || !strings.Contains(err.Error(), "differs from source bytes") {
		t.Fatalf("altered frame accepted or wrong error: %v", err)
	}
	wrongProvider := item
	wrongProvider.Landing.Raw = json.RawMessage(payloadWithAttribution(rows, 1, `{"source":"VCI"}`))
	if _, err = (*PostgresStore)(nil).CommitCrossSourceLanding(context.Background(), wrongProvider); err == nil || !strings.Contains(err.Error(), "differs from source bytes") {
		t.Fatalf("non-KBS payload accepted or wrong error: %v", err)
	}
}
