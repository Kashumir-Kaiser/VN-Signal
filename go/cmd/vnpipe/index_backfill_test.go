package main

import (
	"strings"
	"testing"
	"time"
)

func TestValidateIndexProbeAcceptsFreshRecordedProviderRoute(t *testing.T) {
	now := time.Date(2026, 10, 17, 12, 0, 0, 0, time.UTC)
	valid := `{"at":"2026-10-17T11:59:00Z","active":true,"routes":{"index_ohlcv":{"available":true,"columns":["time","open","high","low","close","volume"],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}}}`
	if err := validateIndexProbe([]byte(valid), now, "kbs"); err != nil {
		t.Fatal(err)
	}
	validVCI := strings.Replace(valid, "\"source\":\"kbs\"", "\"source\":\"vci\"", 1)
	if err := validateIndexProbe([]byte(validVCI), now, "vci"); err != nil {
		t.Fatal(err)
	}
	for _, bad := range []string{
		`{"at":"2026-10-17T11:59:00Z","active":false,"routes":{"index_ohlcv":{"available":true,"columns":["time","open","high","low","close","volume"],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}}}`,
		`{"at":"2026-10-17T11:59:00Z","active":true,"routes":{"index_ohlcv":{"available":true,"columns":["time","open","high","low","close","volume"],"attributes":{"route":"market.index.ohlcv","source":"vci"}}}}`,
		`{"at":"2026-10-17T11:59:00Z","active":true,"routes":{"index_ohlcv":{"available":true,"columns":["time","open","high","low","close"],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}}}`,
		`{"at":"2026-10-15T11:59:00Z","active":true,"routes":{"index_ohlcv":{"available":true,"columns":["time","open","high","low","close","volume"],"attributes":{"route":"market.index.ohlcv","source":"kbs"}}}}`,
	} {
		if err := validateIndexProbe([]byte(bad), now, "kbs"); err == nil {
			t.Fatalf("accepted unsupported probe %s", bad)
		}
	}
}
