package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDefaultProbeOHLCVOutputDirUsesRepositoryDocs(t *testing.T) {
	dir := defaultProbeOHLCVOutputDir()
	if !filepath.IsAbs(dir) || !strings.HasSuffix(filepath.Clean(dir), filepath.Join("docs", "probe", "ohlcv")) {
		t.Fatalf("default probe report path is not rooted at repository docs: %q", dir)
	}
}

func TestValidateProbeOHLCVArgs(t *testing.T) {
	valid := probeOHLCVArgs{Symbol: "FPT", Source: "kbs", Start: "2026-10-01", End: "2026-10-16"}
	if err := validateProbeOHLCVArgs(true, valid); err != nil {
		t.Fatalf("valid args rejected: %v", err)
	}
	cases := []struct {
		name   string
		active bool
		args   probeOHLCVArgs
	}{
		{"not active", false, valid},
		{"lowercase ticker", true, probeOHLCVArgs{Symbol: "fpt", Source: "vci", Start: valid.Start, End: valid.End}},
		{"unsupported source", true, probeOHLCVArgs{Symbol: "FPT", Source: "vnd", Start: valid.Start, End: valid.End}},
		{"bad date", true, probeOHLCVArgs{Symbol: "FPT", Source: "vci", Start: "2026-2-01", End: valid.End}},
		{"reversed dates", true, probeOHLCVArgs{Symbol: "FPT", Source: "vci", Start: valid.End, End: valid.Start}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := validateProbeOHLCVArgs(tc.active, tc.args); err == nil {
				t.Fatal("invalid args accepted")
			}
		})
	}
}

func TestExtractProbeOHLCVReportKeepsOnlyRequestedDateRow(t *testing.T) {
	request := probeOHLCVArgs{Symbol: "FPT", Source: "vci", Start: "2026-10-15", End: "2026-10-16", RawPrices: true}
	frame := `{"count":2,"columns":["time","open","close"],"rows":[` +
		`{"time":"2026-10-15T00:00:00","open":99,"close":100,"private_extra":"drop"},` +
		`{"time":"2026-10-16","open":100,"close":101,"private_extra":"drop"}],` +
		`"attributes":{"source":"vci","route":"market.equity.ohlcv","organisation":"Provider A","token":"drop"}}`
	report, err := extractProbeOHLCVReport([]byte(frame), request, time.Date(2026, 10, 18, 0, 0, 0, 0, time.UTC))
	if err != nil {
		t.Fatal(err)
	}
	if !report.Active || !report.Available || report.Count != 2 || report.TargetDate != request.End {
		t.Fatalf("unexpected report summary: %+v", report)
	}
	if report.FirstObservedDate != request.Start || report.LastObservedDate != request.End {
		t.Fatalf("unexpected date bounds: %+v", report)
	}
	if report.TargetDateRow["open"] != float64(100) || len(report.TargetDateRow) != 3 {
		t.Fatalf("target row was not compact/selected: %#v", report.TargetDateRow)
	}
	if report.ProviderAttribution["organisation"] != "Provider A" || report.ProviderAttribution["token"] != "" {
		t.Fatalf("unexpected provider attribution: %#v", report.ProviderAttribution)
	}
	encoded, _ := json.Marshal(report)
	if string(encoded) == "" || containsString(string(encoded), "private_extra") || containsString(string(encoded), "token") {
		t.Fatalf("report retained full frame data: %s", encoded)
	}
}

func TestExtractProbeOHLCVReportRejectsRowCountMismatch(t *testing.T) {
	request := probeOHLCVArgs{Symbol: "FPT", Source: "vci", Start: "2026-10-16", End: "2026-10-16"}
	if _, err := extractProbeOHLCVReport([]byte(`{"count":2,"columns":[],"rows":[]}`), request, time.Now()); err == nil {
		t.Fatal("row count mismatch accepted")
	}
}

func containsString(value, part string) bool {
	for i := 0; i+len(part) <= len(value); i++ {
		if value[i:i+len(part)] == part {
			return true
		}
	}
	return false
}
