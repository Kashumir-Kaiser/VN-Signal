//go:build postgres_integration

package ingest

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

// Uses pgTestDB, clearDB and listingIntegrationFixture in this package.
// This test runs only against the disposable PostgreSQL 16 CI service.
func TestVerifiedUniverseProgressesBeyondFirstBudgetBatch(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.Now()
	asOf := vnMarketDate(now).Format("2006-01-02")
	snap, err := ParseListingProbe(listingIntegrationFixture(asOf, 1005), 1000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	first, err := LoadVerifiedBackfillUniverse(ctx, db, now, "2018-10-01", asOf, "vci")
	if err != nil || len(first.Pending) != 1005 || first.Total != 1005 {
		t.Fatalf("initial %+v: %v", first, err)
	}
	// An earlier completed batch must not occupy the first N slots forever.
	// Blocked and freshly leased work are also never selected.
	_, err = db.ExecContext(ctx, `INSERT INTO raw.landings (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES ('00000000-0000-4000-8000-000000000088','vci','equity_ohlcv',now(),'X000','{}',repeat('0',64),'{}'::bytea)`)
	if err != nil {
		t.Fatal(err)
	}
	for i, state := range []string{"COMPLETED", "BLOCKED", "RUNNING"} {
		symbol := fmt.Sprintf("X%03d", i)
		landed := "NULL"
		if state == "COMPLETED" {
			landed = "(SELECT max(landing_id) FROM raw.landings)"
		}
		_, err = db.ExecContext(ctx, fmt.Sprintf(`INSERT INTO ops.ingest_jobs
            (idempotency_key,route,symbol,source,date_from,date_to,state,landed_id)
            VALUES ($1,'equity_ohlcv',$2,'vci','2018-10-01',$3,$4,%s)`, landed),
			fmt.Sprintf("equity_ohlcv:%s:vci:2018-10-01:%s", symbol, asOf), symbol, asOf, state)
		if err != nil {
			t.Fatal(err)
		}
	}
	next, err := LoadVerifiedBackfillUniverse(ctx, db, time.Now(), "2018-10-01", asOf, "vci")
	if err != nil {
		t.Fatal(err)
	}
	if next.Completed != 1 || next.Blocked != 1 || next.Leased != 1 || len(next.Pending) != 1002 || next.Pending[0] != "X003" {
		t.Fatalf("resume did not move beyond completed batch: %+v", next)
	}
	// A malformed appended listing frame must block all market calls. Existing
	// raw rows cannot be changed after insertion.
	insertCorruptListingLandingForTest(t, db, asOf)
	if _, err = LoadVerifiedBackfillUniverse(ctx, db, time.Now(), "2018-10-01", asOf, "vci"); !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatalf("corrupt appended frame accepted: %v", err)
	}
	_, err = db.ExecContext(ctx, `UPDATE raw.landings SET payload_bytes='corrupted'::bytea WHERE route='equity_list'`)
	if err == nil {
		t.Fatal("raw landing UPDATE was not rejected")
	}
}

func TestVerifiedUniverseRejectsPartialActiveFlags(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	today := vnMarketDate(time.Now()).Format("2006-01-02")
	snap, err := ParseListingProbe(listingIntegrationFixture(today, 1000), 1000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	_, err = db.ExecContext(ctx, `UPDATE core.symbols SET active=false WHERE symbol='X000'`)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = LoadVerifiedBackfillUniverse(ctx, db, time.Now(), "2018-10-01", today, "vci"); !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatalf("partial snapshot accepted: %v", err)
	}
}

// The upstream JSON remains unchanged, and both mutable tables agree, but
// changing a single exchange still must block subsequent vendor requests.
func TestVerifiedUniverseRejectsCoordinatedMetadataTamper(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	today := vnMarketDate(time.Now()).Format("2006-01-02")
	snap, err := ParseListingProbe(listingIntegrationFixture(today, 1000), 1000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	_, err = db.ExecContext(ctx, `UPDATE core.symbols SET exchange='HNX' WHERE symbol='X000'`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.ExecContext(ctx, `UPDATE core.listing_snapshots SET exchange='HNX'
        WHERE symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='X000')`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = LoadVerifiedBackfillUniverse(ctx, db, time.Now(), "2018-10-01", today, "vci")
	if !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatalf("coordinated metadata tampering passed despite unchanged source frame: %v", err)
	}
}

func TestVerifiedUniverseRejectsSymbolIndustryDrift(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	today := vnMarketDate(time.Now()).Format("2006-01-02")
	snap, err := ParseListingProbe(listingIntegrationFixture(today, 1000), 1000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	_, err = db.ExecContext(ctx, `UPDATE core.symbols SET industry='9999' WHERE symbol='X000'`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = LoadVerifiedBackfillUniverse(ctx, db, time.Now(), "2018-10-01", today, "vci")
	if !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatalf("current classification drift accepted: %v", err)
	}
}

// A32/ABC-style requeued legacy errors have no archived source for offline
// recovery. Skip them by default, but keep explicit retry possible.
func TestBackfillDefersLegacyInvalidFrameWithoutWriting(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	now := time.Now()
	today := vnMarketDate(now).Format("2006-01-02")
	snap, err := ParseListingProbe(listingIntegrationFixture(today, 1000), 1000)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	_, err = db.ExecContext(ctx, `INSERT INTO ops.ingest_jobs
      (idempotency_key,route,symbol,source,date_from,date_to,state,attempts,last_error_type)
      VALUES
      ('equity_ohlcv:X000:vci:2018-10-01:'||$1,'equity_ohlcv','X000','vci','2018-10-01',$1::date,'PENDING',1,'InvalidFrame'),
      ('equity_ohlcv:X001:vci:2018-10-01:'||$1,'equity_ohlcv','X001','vci','2018-10-01',$1::date,'PENDING',1,'InvalidFrame: bad candle')`, today)
	if err != nil {
		t.Fatal(err)
	}
	normal, err := LoadVerifiedBackfillUniverse(ctx, db, now, "2018-10-01", today, "vci")
	if err != nil {
		t.Fatal(err)
	}
	if normal.DeferredInvalid != 2 || len(normal.Pending) != 998 || normal.Pending[0] != "X002" {
		t.Fatalf("unarchived failures erroneously retried: %+v", normal)
	}
	retried, err := LoadVerifiedBackfillUniverseWithPolicy(ctx, db, now, "2018-10-01", today, "vci", true)
	if err != nil {
		t.Fatal(err)
	}
	if retried.DeferredInvalid != 0 || len(retried.Pending) != 1000 ||
		retried.Pending[0] != "X000" || retried.Pending[1] != "X001" {
		t.Fatalf("explicitly authorized retry not selectable %+v", retried)
	}
	var state string
	var attempts int
	err = db.QueryRowContext(ctx, `SELECT state,attempts FROM ops.ingest_jobs WHERE symbol='X000'`).Scan(&state, &attempts)
	if err != nil || state != "PENDING" || attempts != 1 {
		t.Fatalf("audit mutated: %q %d %v", state, attempts, err)
	}
}
