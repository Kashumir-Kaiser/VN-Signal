package ingest

import (
	"strings"
	"testing"
)

func TestAnalyzeMarketBarsZeroVolumeAndTradedAnomaly(t *testing.T) {
	src := payload(`[
      {"time":"2019-01-10","open":3.76,"high":3.38,"low":3.38,"close":3.38,"volume":0},
      {"time":"2019-01-11","open":8,"high":11,"low":9,"close":8.5,"volume":100},
      {"time":"2019-01-14","open":10,"high":7,"low":8,"close":9,"volume":100},
      {"time":"2019-01-15","open":10,"high":10,"low":10,"close":10,"volume":0}
    ]`, 4)
	got, err := AnalyzeMarketBars("ABR", src)
	if err != nil {
		t.Fatal(err)
	}
	if got.SourceRows != 4 || got.Bars.Count != 1 || got.ZeroVolume != 2 || got.InvalidTraded != 1 ||
		len(got.Issues) != 3 || got.Issues[0].Category != "ZERO_VOLUME_UNVERIFIED" ||
		got.Issues[1].Category != "INVALID_OHLC" || got.Issues[1].Reason != "row 0 date 2019-01-14: high below low" ||
		got.FirstDate != "2019-01-10" || got.LastDate != "2019-01-15" {
		t.Fatalf("unreconciled classifications: %+v", got)
	}
	bar := got.Bars.Rows[0]
	if bar.Date != "2019-01-11" || bar.Volume != 100 || bar.Open != 8 || bar.High != 11 || bar.Low != 9 || bar.Close != 8.5 {
		t.Fatalf("auction-priced trade was not retained exactly: %+v", bar)
	}
	auction := payload(`[{"time":"2019-01-11","open":8,"high":11,"low":9,"close":8.5,"volume":100}]`, 1)
	if normalized, normalizeErr := NormalizeBars("ABR", auction); normalizeErr != nil || normalized.Count != 1 {
		t.Fatalf("normalizer rejected auction values outside continuous-session extrema: %+v %v", normalized, normalizeErr)
	}
	if _, err = NormalizeBars("ABR", src); err == nil {
		t.Fatal("normalizer accepted a true high/low inversion")
	}
}
func TestAnalyzeMarketBarsNoTradeOnlyAndRejectsUnreliableFrameShape(t *testing.T) {
	valid := payload(`[{"time":"2019-01-10","open":0,"high":0,"low":0,"close":0,"volume":0}]`, 1)
	r, err := AnalyzeMarketBars("ACE", valid)
	if err != nil || r.Bars.Count != 0 || r.ZeroVolume != 1 || r.InvalidTraded != 0 {
		t.Fatalf("%+v %v", r, err)
	}
	for _, bad := range [][]byte{
		[]byte(strings.Replace(string(valid), `"count":1`, `"count":2`, 1)),
		payload(`[{"time":"2019-01-10","open":1,"high":1,"low":1,"close":1,"volume":100},
                 {"time":"2019-01-10","open":1,"high":1,"low":1,"close":1,"volume":100}]`, 2),
		[]byte(`{"bad":true}`),
	} {
		if _, err := AnalyzeMarketBars("ACE", bad); err == nil {
			t.Fatal("accepted invalid frame structure")
		}
	}
}

func TestAnalyzeMarketBarsForSourceRequiresMatchingProviderAttribution(t *testing.T) {
	rows := `[{"time":"2026-10-16","open":100,"high":101,"low":99,"close":100,"volume":10}]`
	good := payloadWithAttribution(rows, 1, `{"source":"VCI","route":"equity_ohlcv","source_name":"VCI","organisation":"Provider One"}`)
	frame, err := AnalyzeMarketBarsForSource("FPT", "vci", good)
	if err != nil || frame.ProviderSource != "VCI" || frame.ProviderOrganisation != "Provider One" {
		t.Fatalf("frame=%+v err=%v", frame, err)
	}
	missing := payloadWithAttribution(rows, 1, `{"source_name":"VCI"}`)
	if _, err = AnalyzeMarketBarsForSource("FPT", "vci", missing); err == nil {
		t.Fatal("accepted response without provider source attribution")
	}
	mismatch := payloadWithAttribution(rows, 1, `{"source":"kbs"}`)
	if _, err = AnalyzeMarketBarsForSource("FPT", "vci", mismatch); err == nil {
		t.Fatal("accepted response attributed to a different provider")
	}
}

func TestAnalyzeMarketBarsAcceptsExplicitEmptyProviderResponseWithoutCreatingBars(t *testing.T) {
	raw := payloadWithAttribution("[]", 0, "{\"source\":\"VCI\",\"route\":\"equity_ohlcv\",\"source_name\":\"VCI\"}")
	frame, err := AnalyzeMarketBarsForSource("BMD", "vci", raw)
	if err != nil {
		t.Fatal(err)
	}
	if frame.SourceRows != 0 || frame.Bars.Count != 0 || len(frame.Bars.Rows) != 0 ||
		frame.FirstDate != "" || frame.LastDate != "" || len(frame.Issues) != 0 {
		t.Fatalf("empty source response created bar evidence: %+v", frame)
	}

	for _, bad := range [][]byte{
		[]byte(strings.Replace(string(raw), "\"rows\":[]", "\"rows\":null", 1)),
		[]byte(strings.Replace(string(raw), "\"count\":0", "\"count\":1", 1)),
	} {
		if _, err := AnalyzeMarketBarsForSource("BMD", "vci", bad); err == nil {
			t.Fatal("accepted an incomplete or inconsistent empty response")
		}
	}
}

func TestPriceAdjustmentBasisIsSourceSpecific(t *testing.T) {
	for _, tc := range []struct {
		source string
		want   string
	}{
		{source: "VCI", want: "adjusted"},
		{source: " dnse ", want: "adjusted"},
		{source: "vndirect", want: "unadjusted"},
		{source: "kbs", want: "unknown"},
		{source: "", want: "unknown"},
	} {
		if got := priceAdjustmentBasis(tc.source); got != tc.want {
			t.Errorf("priceAdjustmentBasis(%q)=%q, want %q", tc.source, got, tc.want)
		}
	}
}
