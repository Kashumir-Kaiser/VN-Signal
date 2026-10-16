package ingest

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func listingProbe(rows []map[string]any) []byte {
	frame := map[string]any{"columns": []string{"symbol", "exchange", "organ_name", "icb_code_lv2"}, "count": len(rows), "rows": rows, "attributes": map[string]any{"source": "vci"}}
	report := map[string]any{"at": "2026-10-16T09:00:00+00:00", "active": true, "routes": map[string]any{"equity_list": map[string]any{"count": len(rows), "available": true}}, "listing_frame": frame}
	b, _ := json.Marshal(report)
	return b
}
func goodListings() []map[string]any {
	return []map[string]any{{"symbol": "fpt", "exchange": "HOSE", "icb_code_lv2": "9500"}, {"symbol": "hpg", "exchange": "HNX", "icb_code_lv2": 1700}, {"symbol": "acb", "exchange": "UPCoM", "icb_code_lv2": nil}}
}
func TestParseListingProbe(t *testing.T) {
	p, e := ParseListingProbe(listingProbe(goodListings()), 3)
	if e != nil {
		t.Fatal(e)
	}
	if p.AsOf != "2026-10-16" || len(p.Listings) != 3 || p.ProviderRows != 3 || p.ExcludedDelisted != 0 || p.Listings[0].Symbol != "ACB" || p.Listings[0].Exchange != "UPCOM" || p.Listings[1].Industry != "9500" {
		t.Fatalf("unexpected %+v", p)
	}
	if err := RevalidateBeforeImport(p); err != nil {
		t.Fatal(err)
	}
	p.Listings[0].Exchange = "HOSE"
	if err := RevalidateBeforeImport(p); err == nil {
		t.Fatal("mutated canonical accepted")
	}
}
func TestParseListingProbeExcludesProviderDelistedRows(t *testing.T) {
	rows := append(goodListings(), map[string]any{
		"symbol": "OLD", "exchange": "DELISTED", "icb_code_lv2": nil,
		"organ_name": "Công ty Cũ",
	})
	raw := listingProbe(rows)
	snapshot, err := ParseListingProbe(raw, 3)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.ProviderRows != 4 || snapshot.ExcludedDelisted != 1 || len(snapshot.Listings) != 3 {
		t.Fatalf("provider/current counts mismatch: provider=%d excluded=%d listings=%d",
			snapshot.ProviderRows, snapshot.ExcludedDelisted, len(snapshot.Listings))
	}
	if !strings.Contains(string(snapshot.Frame), "\"exchange\":\"DELISTED\"") {
		t.Fatal("original delisted row was not retained in the raw frame")
	}
	if err := RevalidateBeforeImport(snapshot); err != nil {
		t.Fatal(err)
	}
}

func TestInvalidListingSnapshotFailsClosed(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func([]map[string]any) []map[string]any
	}{
		{"duplicate", func(a []map[string]any) []map[string]any { a[1]["symbol"] = "FPT"; return a }},
		{"unknown exchange", func(a []map[string]any) []map[string]any { a[1]["exchange"] = "OTC"; return a }},
		{"missing exchange", func(a []map[string]any) []map[string]any { delete(a[2], "exchange"); return a }},
		{"invalid ticker", func(a []map[string]any) []map[string]any { a[0]["symbol"] = "ABC-1"; return a }},
		{"partial exchange", func(a []map[string]any) []map[string]any { a[2]["exchange"] = "HOSE"; return a }},
		{"invalid industry", func(a []map[string]any) []map[string]any { a[1]["icb_code_lv2"] = "A1"; return a }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, e := ParseListingProbe(listingProbe(tc.mutate(goodListings())), 3)
			if !errors.Is(e, ErrInvalidListing) {
				t.Fatal(e)
			}
		})
	}
	for _, tc := range []struct {
		name   string
		change func(map[string]any)
	}{
		{"passive", func(m map[string]any) { m["active"] = false }},
		{"count mismatch", func(m map[string]any) { m["routes"].(map[string]any)["equity_list"].(map[string]any)["count"] = 999 }},
		{"missing frame", func(m map[string]any) { delete(m, "listing_frame") }},
		{"time missing", func(m map[string]any) { m["at"] = "" }},
		{"vendor unavailable", func(m map[string]any) {
			m["routes"].(map[string]any)["equity_list"].(map[string]any)["available"] = false
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var m map[string]any
			_ = json.Unmarshal(listingProbe(goodListings()), &m)
			tc.change(m)
			b, _ := json.Marshal(m)
			_, e := ParseListingProbe(b, 3)
			if !errors.Is(e, ErrInvalidListing) {
				t.Fatal(e)
			}
		})
	}
	_, e := ParseListingProbe(listingProbe(goodListings()), 1000)
	if !errors.Is(e, ErrInvalidListing) {
		t.Fatal("partial snapshot accepted")
	}
}
func TestLargeAndTrailingFramesRejected(t *testing.T) {
	frame := `{"columns":["symbol","exchange"],"count":3,"rows":[{"symbol":"A","exchange":"HOSE"},{"symbol":"B","exchange":"HNX"},{"symbol":"C","exchange":"UPCOM"}]}`
	_, err := decodeListingFrame([]byte(frame+` {"extra":true}`), 3)
	if !errors.Is(err, ErrInvalidListing) {
		t.Fatal("trailing JSON accepted", err)
	}
	_, err = ParseListingProbe([]byte(strings.Repeat("a", 12*1024*1024+1)), 3)
	if !errors.Is(err, ErrInvalidListing) {
		t.Fatal("oversize accepted")
	}
}
