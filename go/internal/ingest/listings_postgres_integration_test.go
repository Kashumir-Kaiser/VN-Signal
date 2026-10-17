//go:build postgres_integration

package ingest

import (
	"bytes"
	"context"
	"database/sql"
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

// Historical securities master must preserve provider DELISTED rows without
// inventing a past exchange, date of delisting, or active tradability.
func TestSecuritiesMasterPreservesAllObservedSymbols(t *testing.T) {
    db:=pgTestDB(t)
    clearDB(t,db)
    store,_:=NewPostgresStore(db)
    ctx:=context.Background()
    snap,err:=ParseListingProbe(listingIntegrationFixture("2026-10-16",20),3)
    if err!=nil{t.Fatal(err)}
    if _,err=store.ImportListingSnapshot(ctx,snap);err!=nil{t.Fatal(err)}
    for query,want:=range map[string]int{
        "SELECT count(*) FROM core.security_master":21,
        "SELECT count(*) FROM core.security_observations":21,
        "SELECT count(*) FROM core.security_observed_days":21,
        "SELECT count(*) FROM core.security_observations WHERE category='EXCHANGE_LISTED'":20,
        "SELECT count(*) FROM core.security_observations WHERE category='PROVIDER_DELISTED_UNDATED'":1,
        "SELECT count(*) FROM core.symbols":20,
        "SELECT count(*) FROM core.listing_snapshots":20,
        "SELECT count(*) FROM ops.api_reservations":0,
    }{
        var n int
        if err=db.QueryRow(query).Scan(&n);err!=nil||n!=want {
            t.Fatalf("%s count=%d expected=%d: %v",query,n,want,err)
        }
    }
    var oldCategory string
    var oldExchange sql.NullString
    if err=db.QueryRow(`SELECT category,exchange FROM core.security_observed_sessions
        WHERE symbol='OLD000'`).Scan(&oldCategory,&oldExchange);err!=nil {
        t.Fatal(err)
    }
    if oldCategory!="PROVIDER_DELISTED_UNDATED"||oldExchange.Valid{
        t.Fatalf("invented historical listing for OLD000: %s %v",oldCategory,oldExchange)
    }
    summary,err:=store.RebuildSecurityMaster(ctx)
    if err!=nil||summary.Frames!=1||summary.ObservationsAdded!=0||summary.AlreadyPresent!=21 {
        t.Fatalf("replay not idempotent: %+v %v",summary,err)
    }
    _,err=db.Exec(`UPDATE raw.landings SET payload_bytes='{}'::bytea
        WHERE route='equity_list'`)
    if err!=nil{t.Fatal(err)}
    if _,err=store.RebuildSecurityMaster(ctx);err==nil{
        t.Fatal("tampered raw listing data accepted")
    }
    var still int
    if err=db.QueryRow(`SELECT count(*) FROM core.security_observations`).Scan(&still);err!=nil||still!=21 {
        t.Fatalf("tamper changed observed history %d %v",still,err)
    }
}

func TestSecurityMasterReplayRejectsMutatedObservationFields(t *testing.T) {
    db:=pgTestDB(t)
    clearDB(t,db)
    store,_:=NewPostgresStore(db)
    ctx:=context.Background()
    snap,err:=ParseListingProbe(listingIntegrationFixture("2026-10-16",20),3)
    if err!=nil{t.Fatal(err)}
    if _,err=store.ImportListingSnapshot(ctx,snap);err!=nil{t.Fatal(err)}
    corruptSecurityObservationForTest(t,db,`UPDATE core.security_observations
        SET legal_name='forged', short_name='tampered'
        WHERE provider_row_index=0`)
    if _,err=store.RebuildSecurityMaster(ctx);err==nil{
        t.Fatal("source master replay accepted mutable observation metadata")
    }
    // The original complete provider frame remains unmodified: the mismatch
    // must be detected from the projection rather than the raw checksum.
    var count int
    if err=db.QueryRow(`SELECT count(*) FROM core.security_observations`).Scan(&count);err!=nil||count!=21{
        t.Fatalf("failed replay changed observation count: %d %v",count,err)
    }
}
func TestSecurityMasterReplayRejectsSwappedObservedClassification(t *testing.T) {
    db:=pgTestDB(t)
    clearDB(t,db)
    store,_:=NewPostgresStore(db)
    ctx:=context.Background()
    snap,err:=ParseListingProbe(listingIntegrationFixture("2026-10-16",20),3)
    if err!=nil{t.Fatal(err)}
    if _,err=store.ImportListingSnapshot(ctx,snap);err!=nil{t.Fatal(err)}
    // Same unique key, but false category/exchange, should not disappear
    // behind the projection's ON CONFLICT DO NOTHING.
    corruptSecurityObservationForTest(t,db,`UPDATE core.security_observations
        SET category='PROVIDER_DELISTED_UNDATED',exchange=NULL
        WHERE provider_row_index=0`)
    if _,err=store.RebuildSecurityMaster(ctx);err==nil{
        t.Fatal("source master replay accepted falsified trading category")
    }
}

// Simulate privileged storage corruption without changing the production
// append-only contract. DDL and the mutation occur in one transaction; the
// trigger is re-enabled before commit, including for subsequent tests.
func corruptSecurityObservationForTest(t *testing.T,db *sql.DB,update string) {
    t.Helper()
    tx,err:=db.BeginTx(context.Background(),nil)
    if err!=nil{t.Fatal(err)}
    defer tx.Rollback()
    for _,statement:=range []string{
        "ALTER TABLE core.security_observations DISABLE TRIGGER security_observation_immutable",
        update,
        "ALTER TABLE core.security_observations ENABLE TRIGGER security_observation_immutable",
    }{
        if _,err=tx.Exec(statement);err!=nil{t.Fatalf("simulate privileged corruption: %v",err)}
    }
    if err=tx.Commit();err!=nil{t.Fatal(err)}
}
