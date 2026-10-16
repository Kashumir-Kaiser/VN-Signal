//go:build postgres_integration

package ingest

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"testing"
)

func listingIntegrationFixture(day string, count int) []byte {
	rows := make([]map[string]any, 0, count)
	exchanges := []string{"HOSE", "HNX", "UPCOM"}
	for i := 0; i < count; i++ {
		rows = append(rows, map[string]any{"symbol": fmt.Sprintf("X%03d", i), "exchange": exchanges[i%3], "icb_code_lv2": "9500"})
	}
	rows = append(rows, map[string]any{"symbol": "OLD000", "exchange": "DELISTED", "icb_code_lv2": nil})
	frame := map[string]any{"columns": []string{"symbol", "exchange", "icb_code_lv2"}, "count": len(rows), "rows": rows, "attributes": map[string]any{"source": "vci"}}
	raw, _ := json.Marshal(map[string]any{"at": day + "T03:00:00+07:00", "active": true, "routes": map[string]any{"equity_list": map[string]any{"available": true, "count": len(rows)}}, "listing_frame": frame})
	return raw
}
func TestListingSnapshotTransactionIdempotencyAndDelisting(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	day1, e := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if e != nil {
		t.Fatal(e)
	}
	result, e := store.ImportListingSnapshot(ctx, day1)
	if e != nil || result.Symbols != 20 || result.ProviderRows != 21 || result.ExcludedDelisted != 1 || result.Deactivated != 0 {
		t.Fatalf("first %+v %v", result, e)
	}
	var excluded int
	if e = db.QueryRow(`SELECT count(*) FROM core.symbols WHERE symbol='OLD000'`).Scan(&excluded); e != nil || excluded != 0 {
		t.Fatalf("provider delisted symbol entered current universe: count=%d error=%v", excluded, e)
	}
	result, e = store.ImportListingSnapshot(ctx, day1)
	if e != nil || !result.AlreadyImported {
		t.Fatalf("same day %+v %v", result, e)
	}
	var n int
	if e = db.QueryRow(`SELECT count(*) FROM raw.landings WHERE route='equity_list'`).Scan(&n); e != nil || n != 1 {
		t.Fatalf("duplicate raw landing count=%d error=%v", n, e)
	}
	var exact []byte
	if e = db.QueryRow(`SELECT payload_bytes FROM raw.landings WHERE route='equity_list'`).Scan(&exact); e != nil || !bytes.Equal(exact, day1.Frame) {
		t.Fatalf("raw payload byte parity lost: %v", e)
	}
	// Incomplete route result must roll back and preserve all current listings.
	day2, e := ParseListingProbe(listingIntegrationFixture("2026-10-17", 18), 3)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = store.ImportListingSnapshot(ctx, day2); e == nil {
		t.Fatal("accepted >5% universe shrinkage")
	}
	if e = db.QueryRow(`SELECT count(*) FROM core.symbols WHERE active=true`).Scan(&n); e != nil || n != 20 {
		t.Fatalf("status mutated by failed import: %d %v", n, e)
	}
	// A genuine 5% shrinkage is permitted and the absent member is retained inactive.
	day2, e = ParseListingProbe(listingIntegrationFixture("2026-10-17", 19), 3)
	if e != nil {
		t.Fatal(e)
	}
	result, e = store.ImportListingSnapshot(ctx, day2)
	if e != nil || result.Deactivated != 1 {
		t.Fatalf("second %+v %v", result, e)
	}
	if e = db.QueryRow(`SELECT count(*) FROM core.symbols WHERE active=true`).Scan(&n); e != nil || n != 19 {
		t.Fatalf("active=%d error=%v", n, e)
	}
	if e = db.QueryRow(`SELECT count(*) FROM core.listing_snapshots`).Scan(&n); e != nil || n != 39 {
		t.Fatalf("PIT history=%d error=%v", n, e)
	}
	if _, e = store.ImportListingSnapshot(ctx, day1); e == nil {
		t.Fatal("accepted out-of-order historical snapshot")
	}
	day2.Listings[0].Exchange = "HNX"
	if _, e = store.ImportListingSnapshot(ctx, day2); e == nil {
		t.Fatal("accepted tampered snapshot")
	}
}