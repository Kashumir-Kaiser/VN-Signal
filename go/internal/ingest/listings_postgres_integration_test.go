//go:build postgres_integration

package ingest

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"slices"
	"strings"
	"testing"
	"time"
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

// This test mutates the singleton quota guard, so it must never open a user's
// configured database. CI's disposable service uses this exact database name.
func requireVNSignalTestDatabase(t *testing.T) {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	parsed, err := url.Parse(dsn)
	if err != nil || parsed == nil {
		t.Fatal("PostgreSQL integration requires DATABASE_URL to target the disposable vnsignal_test database")
	}
	host := parsed.Hostname()
	localHost := host == "localhost" || host == "127.0.0.1" || host == "::1"
	if parsed.Scheme != "postgres" && parsed.Scheme != "postgresql" || !localHost || strings.Trim(parsed.Path, "/") != "vnsignal_test" {
		t.Fatal("PostgreSQL integration requires DATABASE_URL to target the disposable vnsignal_test database")
	}
}

func TestProfileCallAuditUsesOneQuotaReservationAndValidTransitions(t *testing.T) {
	requireVNSignalTestDatabase(t)
	db := pgTestDB(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	// Preserve the disposable DB's prior singleton guard so cleanup restores
	// it even if an assertion below fails.
	var oldVerified, oldExpires time.Time
	var oldDay string
	var oldBudget, oldSpent int
	var oldSpacing int64
	var oldLast sql.NullTime
	hadGuard := false
	err := db.QueryRowContext(ctx, `SELECT verified_at,expires_at,day_key::text,call_budget,spent,
       min_spacing_ms,last_not_before FROM ops.quota_guard WHERE singleton=true`).
		Scan(&oldVerified, &oldExpires, &oldDay, &oldBudget, &oldSpent, &oldSpacing, &oldLast)
	if err == nil {
		hadGuard = true
	} else if err != sql.ErrNoRows {
		t.Fatal(err)
	}

	symbol := fmt.Sprintf("Q%011d", time.Now().UnixNano()%100000000000)
	var securityID int64
	setup, err := db.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer setup.Rollback()
	err = setup.QueryRowContext(ctx, `INSERT INTO core.security_master(symbol,first_observed_at,last_observed_at)
       VALUES($1,now(),now()) RETURNING security_id`, symbol).Scan(&securityID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = setup.ExecContext(ctx, `INSERT INTO ops.company_profile_jobs(security_id) VALUES($1)`, securityID); err != nil {
		t.Fatal(err)
	}
	_, err = setup.ExecContext(ctx, `INSERT INTO ops.quota_guard
       (singleton,verified_at,expires_at,day_key,call_budget,spent,min_spacing_ms,last_not_before)
       VALUES(true,now()-interval '1 second',now()+interval '5 minutes',
         (now() at time zone 'Asia/Ho_Chi_Minh')::date,10,0,1000,NULL)
       ON CONFLICT(singleton) DO UPDATE SET verified_at=EXCLUDED.verified_at,
         expires_at=EXCLUDED.expires_at,day_key=EXCLUDED.day_key,call_budget=EXCLUDED.call_budget,
         spent=EXCLUDED.spent,min_spacing_ms=EXCLUDED.min_spacing_ms,last_not_before=NULL`)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cleanupCtx, stop := context.WithTimeout(context.Background(), 10*time.Second)
		defer stop()
		tx, e := db.BeginTx(cleanupCtx, nil)
		if e != nil {
			t.Errorf("begin profile audit cleanup: %v", e)
			return
		}
		defer tx.Rollback()
		if _, e = tx.ExecContext(cleanupCtx, `DELETE FROM ops.company_profile_call_audit
           WHERE attempt_id IN (SELECT attempt_id FROM ops.company_profile_attempts WHERE security_id=$1)`, securityID); e != nil {
			t.Errorf("delete profile call audit fixture: %v", e)
			return
		}
		if _, e = tx.ExecContext(cleanupCtx, `DELETE FROM ops.company_profile_attempts WHERE security_id=$1`, securityID); e != nil {
			t.Errorf("delete profile attempt fixture: %v", e)
			return
		}
		if _, e = tx.ExecContext(cleanupCtx, `DELETE FROM ops.company_profile_jobs WHERE security_id=$1`, securityID); e != nil {
			t.Errorf("delete profile queue fixture: %v", e)
			return
		}
		if _, e = tx.ExecContext(cleanupCtx, `DELETE FROM core.security_master WHERE security_id=$1`, securityID); e != nil {
			t.Errorf("delete security fixture: %v", e)
			return
		}
		if hadGuard {
			_, e = tx.ExecContext(cleanupCtx, `UPDATE ops.quota_guard SET verified_at=$1,expires_at=$2,
              day_key=$3,call_budget=$4,spent=$5,min_spacing_ms=$6,last_not_before=$7 WHERE singleton=true`,
				oldVerified, oldExpires, oldDay, oldBudget, oldSpent, oldSpacing, oldLast)
		} else {
			_, e = tx.ExecContext(cleanupCtx, `DELETE FROM ops.quota_guard WHERE singleton=true`)
		}
		if e != nil {
			t.Errorf("restore quota guard fixture: %v", e)
			return
		}
		if e = tx.Commit(); e != nil {
			t.Errorf("commit profile audit cleanup: %v", e)
		}
	})
	if err = setup.Commit(); err != nil {
		t.Fatal(err)
	}

	store, _ := NewPostgresStore(db)
	attempt, _, err := store.ReserveProfileCall(ctx, symbol, t.TempDir(), false, false)
	if err != nil {
		t.Fatal(err)
	}
	var spent int
	if err = db.QueryRowContext(ctx, `SELECT spent FROM ops.quota_guard WHERE singleton=true`).Scan(&spent); err != nil || spent != 1 {
		t.Fatalf("profile reservation should spend exactly one quota unit: spent=%d err=%v", spent, err)
	}
	if err = store.DispatchProfileCallAudit(ctx, attempt.ID); err == nil {
		t.Fatal("dispatch without a linked audit row succeeded")
	}
	requested := time.Now().Add(-time.Second)
	auditAt, err := store.ReserveProfileCallAudit(ctx, attempt.ID, requested)
	if err != nil {
		t.Fatal(err)
	}
	var durableWhen time.Time
	if err = db.QueryRowContext(ctx, `SELECT not_before FROM ops.company_profile_attempts WHERE attempt_id=$1`, attempt.ID).Scan(&durableWhen); err != nil {
		t.Fatal(err)
	}
	if !auditAt.Equal(durableWhen) {
		t.Fatalf("audit reservation changed durable pacing: at=%s profile=%s", auditAt, durableWhen)
	}
	if _, err = store.ReserveProfileCallAudit(ctx, attempt.ID, requested); err == nil {
		t.Fatal("duplicate API audit reservation succeeded")
	}
	if err = store.FinishProfileCallAudit(ctx, attempt.ID, "SUCCEEDED", ""); err == nil {
		t.Fatal("successful finish before dispatch succeeded")
	}
	if err = db.QueryRowContext(ctx, `SELECT spent FROM ops.quota_guard WHERE singleton=true`).Scan(&spent); err != nil || spent != 1 {
		t.Fatalf("creating call audit double-counted quota: spent=%d err=%v", spent, err)
	}
	if err = store.DispatchProfileCallAudit(ctx, attempt.ID); err != nil {
		t.Fatal(err)
	}
	if err = store.DispatchProfileCallAudit(ctx, attempt.ID); err == nil {
		t.Fatal("duplicate dispatch succeeded")
	}
	if err = store.FinishProfileCallAudit(ctx, attempt.ID, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	if err = store.FinishProfileCallAudit(ctx, attempt.ID, "FAILED", "duplicate"); err == nil {
		t.Fatal("duplicate finish succeeded")
	}
	var status string
	if err = db.QueryRowContext(ctx, `SELECT status FROM ops.company_profile_call_audit WHERE attempt_id=$1`, attempt.ID).Scan(&status); err != nil || status != "SUCCEEDED" {
		t.Fatalf("wrong final API audit state %q: %v", status, err)
	}
	if err = db.QueryRowContext(ctx, `SELECT spent FROM ops.quota_guard WHERE singleton=true`).Scan(&spent); err != nil || spent != 1 {
		t.Fatalf("API audit lifecycle must not spend additional quota: spent=%d err=%v", spent, err)
	}
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
	var rawBefore int
	if e = db.QueryRow(`SELECT count(*) FROM raw.landings WHERE route='equity_list' AND (fetched_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date='2026-10-16'`).Scan(&rawBefore); e != nil {
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
	if e = db.QueryRow(`SELECT count(*) FROM raw.landings WHERE route='equity_list' AND (fetched_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date='2026-10-16'`).Scan(&n); e != nil || n != rawBefore+1 {
		t.Fatalf("first import raw landing delta=%d error=%v", n-rawBefore, e)
	}
	var exact []byte
	if e = db.QueryRow(`SELECT payload_bytes FROM raw.landings WHERE route='equity_list' ORDER BY landing_id DESC LIMIT 1`).Scan(&exact); e != nil || !bytes.Equal(exact, day1.Frame) {
		t.Fatalf("raw payload byte parity lost: %v", e)
	}
	if _, e = store.ImportListingSnapshot(ctx, day1); e != nil {
		t.Fatalf("idempotent repeat: %v", e)
	}
	if e = db.QueryRow(`SELECT count(*) FROM raw.landings WHERE route='equity_list' AND (fetched_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date='2026-10-16'`).Scan(&n); e != nil || n != rawBefore+1 {
		t.Fatalf("idempotent repeat appended a landing: count=%d error=%v", n, e)
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
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	snap, err := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	for query, want := range map[string]int{
		"SELECT count(*) FROM core.security_master":                                                  21,
		"SELECT count(*) FROM core.security_observations":                                            21,
		"SELECT count(*) FROM core.security_observed_days":                                           21,
		"SELECT count(*) FROM core.security_observations WHERE category='EXCHANGE_LISTED'":           20,
		"SELECT count(*) FROM core.security_observations WHERE category='PROVIDER_DELISTED_UNDATED'": 1,
		"SELECT count(*) FROM core.symbols":                                                          20,
		"SELECT count(*) FROM core.listing_snapshots":                                                20,
		"SELECT count(*) FROM ops.api_reservations":                                                  0,
	} {
		var n int
		if err = db.QueryRow(query).Scan(&n); err != nil || n != want {
			t.Fatalf("%s count=%d expected=%d: %v", query, n, want, err)
		}
	}
	var oldCategory string
	var oldExchange sql.NullString
	if err = db.QueryRow(`SELECT category,exchange FROM core.security_observed_sessions
        WHERE symbol='OLD000'`).Scan(&oldCategory, &oldExchange); err != nil {
		t.Fatal(err)
	}
	if oldCategory != "PROVIDER_DELISTED_UNDATED" || oldExchange.Valid {
		t.Fatalf("invented historical listing for OLD000: %s %v", oldCategory, oldExchange)
	}
	summary, err := store.RebuildSecurityMaster(ctx)
	if err != nil || summary.Frames != 1 || summary.ObservationsAdded != 0 || summary.AlreadyPresent != 21 {
		t.Fatalf("replay not idempotent: %+v %v", summary, err)
	}
	insertCorruptListingLandingForTest(t, db, "2026-10-16")
	if _, err = store.RebuildSecurityMaster(ctx); err == nil {
		t.Fatal("corrupt appended raw listing data accepted")
	}
	var still int
	if err = db.QueryRow(`SELECT count(*) FROM core.security_observations`).Scan(&still); err != nil || still != 21 {
		t.Fatalf("corrupt appended frame changed observed history %d %v", still, err)
	}
}

// insertCorruptListingLandingForTest creates an intentionally inconsistent
// archived frame at insertion time. It exercises digest validation without
// mutating append-only evidence after it has been stored.
func insertCorruptListingLandingForTest(t *testing.T, db *sql.DB, asOf string) {
	t.Helper()
	good := []byte(`{"columns":["symbol","exchange","icb_code_lv2"],"count":0,"rows":[]}`)
	bad := []byte(`{"columns":["symbol","exchange","icb_code_lv2"],"count":1,"rows":[]}`)
	digest := sha256.Sum256(good)
	_, err := db.Exec(`INSERT INTO raw.landings(ingest_id,source,route,fetched_at,payload,payload_sha256,payload_bytes)
        VALUES(gen_random_uuid(),'vci','equity_list',$1::date::timestamptz,
               $2::jsonb,$3,$4)`, asOf, string(good), hex.EncodeToString(digest[:]), bad)
	if err != nil {
		t.Fatal(err)
	}
}

func TestSecurityMasterReplayRejectsMutatedObservationFields(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	snap, err := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	corruptSecurityObservationForTest(t, db, `UPDATE core.security_observations
        SET legal_name='forged', short_name='tampered'
        WHERE provider_row_index=0`)
	if _, err = store.RebuildSecurityMaster(ctx); err == nil {
		t.Fatal("source master replay accepted mutable observation metadata")
	}
	// The original complete provider frame remains unmodified: the mismatch
	// must be detected from the projection rather than the raw checksum.
	var count int
	if err = db.QueryRow(`SELECT count(*) FROM core.security_observations`).Scan(&count); err != nil || count != 21 {
		t.Fatalf("failed replay changed observation count: %d %v", count, err)
	}
}
func TestSecurityMasterReplayRejectsSwappedObservedClassification(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	snap, err := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	// Same unique key, but false category/exchange, should not disappear
	// behind the projection's ON CONFLICT DO NOTHING.
	corruptSecurityObservationForTest(t, db, `UPDATE core.security_observations
        SET category='PROVIDER_DELISTED_UNDATED',exchange=NULL
        WHERE provider_row_index=0`)
	if _, err = store.RebuildSecurityMaster(ctx); err == nil {
		t.Fatal("source master replay accepted falsified trading category")
	}
}

// Simulate privileged storage corruption without changing the production
// append-only contract. DDL and the mutation occur in one transaction; the
// trigger is re-enabled before commit, including for subsequent tests.
func corruptSecurityObservationForTest(t *testing.T, db *sql.DB, update string) {
	t.Helper()
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for _, statement := range []string{
		"ALTER TABLE core.security_observations DISABLE TRIGGER security_observation_immutable",
		update,
		"ALTER TABLE core.security_observations ENABLE TRIGGER security_observation_immutable",
	} {
		if _, err = tx.Exec(statement); err != nil {
			t.Fatalf("simulate privileged corruption: %v", err)
		}
	}
	if err = tx.Commit(); err != nil {
		t.Fatal(err)
	}
}

func TestArchivedCompanyProfileIsProviderMetadataNotFirstTrade(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	snap, err := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	report := companyProbeFixture("X000", "2020-02-01T00:00:00+07:00")
	// Mimic the real Go probe's pretty-printed 2026-10-17.json rather
	// than a compact synthetic frame. Previously failed on SHA mismatch.
	var pretty bytes.Buffer
	if err := json.Indent(&pretty, report, "", "  "); err != nil {
		t.Fatal(err)
	}
	p, err := ParseCompanyInfoProbe(pretty.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	created, err := store.ImportCompanyInfo(ctx, p)
	if err != nil || !created {
		t.Fatalf("initial profile import: %v %v", created, err)
	}
	repeated, err := store.ImportCompanyInfo(ctx, p)
	if err != nil || repeated {
		t.Fatalf("replayed profile not idempotent: %v %v", repeated, err)
	}
	var date string
	err = db.QueryRow(`SELECT reported_listing_date::text
       FROM core.company_profile_listing_evidence WHERE symbol='X000'`).Scan(&date)
	if err != nil || date != "2020-02-01" {
		t.Fatalf("missing source reported date %s %v", date, err)
	}
	for q, want := range map[string]int{
		"SELECT count(*) FROM raw.landings WHERE landing_id=(SELECT landing_id FROM core.company_profile_observations LIMIT 1)": 1,
		"SELECT count(*) FROM core.company_profile_observations":                                                                1,
		"SELECT count(*) FROM core.security_lifecycle_evidence":                                                                 0,
		"SELECT count(*) FROM ops.api_reservations":                                                                             0,
	} {
		var n int
		if err = db.QueryRow(q).Scan(&n); err != nil || n != want {
			t.Fatalf("%s got %d want %d: %v", q, n, want, err)
		}
	}
	p.ReportedListingDate = "1999-01-01"
	if _, err = store.ImportCompanyInfo(ctx, p); err == nil {
		t.Fatal("caller-invented reported listing date accepted")
	}
}

func TestProfileBatchQueueQuotaAndResume(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	ctx := context.Background()
	snap, err := ParseListingProbe(listingIntegrationFixture("2026-10-16", 20), 3)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportListingSnapshot(ctx, snap); err != nil {
		t.Fatal(err)
	}
	if err = store.SeedProfileQueue(ctx); err != nil {
		t.Fatal(err)
	}
	queue, err := store.ProfileQueue(ctx)
	if err != nil || len(queue) != 21 {
		t.Fatalf("full universe not queued: %d %v", len(queue), err)
	}
	profile, err := ParseCompanyInfoProbe(companyProbeFixture("X000", "2020-02-01"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.ImportCompanyInfo(ctx, profile); err != nil {
		t.Fatal(err)
	}
	if err = store.SeedProfileQueue(ctx); err != nil {
		t.Fatal(err)
	}
	queue, err = store.ProfileQueue(ctx)
	if err != nil {
		t.Fatal(err)
	}
	imported := false
	for _, c := range queue {
		if c.Symbol == "X000" {
			imported = c.State == "IMPORTED"
		}
	}
	if !imported {
		t.Fatal("already imported profile requeued")
	}
	q := QuotaSnapshot{
		DailyRemaining: 30, MonthlyRemaining: 3000, TradingDaysRemaining: 10,
		VerifiedRPM: 60, ObservedAt: time.Now().UTC().Add(-time.Millisecond),
	}
	if err = store.InstallQuota(ctx, q); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	first, at, err := store.ReserveProfileCall(ctx, "X001", dir, false, false)
	if err != nil || first.ID == 0 || at.IsZero() {
		t.Fatalf("durable reserve: %+v %v", first, err)
	}
	if !strings.HasSuffix(first.ReportPath, fmt.Sprintf("X001-%012d.json", first.ID)) {
		t.Fatalf("wrong deterministic archive path: %s", first.ReportPath)
	}
	if _, _, err = store.ReserveProfileCall(ctx, "X001", dir, false, false); !errors.Is(err, ErrProfileUnknownOutcome) {
		t.Fatalf("in flight request not protected: %v", err)
	}
	attempts, err := store.UnfinishedProfileAttempts(ctx)
	if err != nil || len(attempts) != 1 || attempts[0].ID != first.ID {
		t.Fatalf("no recoverable attempt: %+v %v", attempts, err)
	}
	if err = store.EndProfileCall(ctx, first.ID, "UNKNOWN", "InterruptedWithoutSavedResponse"); err != nil {
		t.Fatal(err)
	}
	if _, _, err = store.ReserveProfileCall(ctx, "X001", dir, false, false); !errors.Is(err, ErrProfileUnknownOutcome) {
		t.Fatalf("unknown request automatically repeated: %v", err)
	}
	repeated, _, err := store.ReserveProfileCall(ctx, "X001", dir, false, true)
	if err != nil || repeated.ID == first.ID {
		t.Fatalf("explicit retry failed: %+v %v", repeated, err)
	}
	if err = store.EndProfileCall(ctx, repeated.ID, "ERROR", "ProviderFailure"); err != nil {
		t.Fatal(err)
	}
	if _, _, err = store.ReserveProfileCall(ctx, "X001", dir, false, false); !errors.Is(err, ErrProfileAlreadyHandled) {
		t.Fatalf("error request auto retried: %v", err)
	}
	// Prior versions misclassified an interrupted request as ERROR, even
	// though the provider may have received and billed the call.
	former, _, err := store.ReserveProfileCall(ctx, "X002", dir, false, false)
	if err != nil {
		t.Fatal(err)
	}
	if err = store.EndProfileCall(ctx, former.ID, "ERROR", "WorkerTimeout"); err != nil {
		t.Fatal(err)
	}
	corrected, err := store.ReclassifyLegacyProfileTimeouts(ctx)
	if err != nil || corrected != 1 {
		t.Fatalf("legacy timeout not corrected: %d %v", corrected, err)
	}
	if _, _, err = store.ReserveProfileCall(ctx, "X002", dir, true, false); !errors.Is(err, ErrProfileUnknownOutcome) {
		t.Fatalf("old WorkerTimeout request was retried via --retry-errors: %v", err)
	}
	corrected, err = store.ReclassifyLegacyProfileTimeouts(ctx)
	if err != nil || corrected != 0 {
		t.Fatalf("not idempotent: %d %v", corrected, err)
	}
	var previousState string
	err = db.QueryRow(`SELECT status FROM ops.company_profile_attempts WHERE attempt_id=$1`, former.ID).
		Scan(&previousState)
	if err != nil || previousState != "UNKNOWN" {
		t.Fatalf("legacy attempt still mislabeled: %s %v", previousState, err)
	}
	var spent int
	if err = db.QueryRow(`SELECT spent FROM ops.quota_guard`).Scan(&spent); err != nil || spent != 3 {
		t.Fatalf("shared quota not debited twice: %d %v", spent, err)
	}
	batch, err := store.StartProfileBatch(ctx, 5)
	if err != nil {
		t.Fatal(err)
	}
	sum := ProfileBatchSummary{BatchID: batch, MaxCalls: 5, Attempted: 2, Errors: 1, SkippedExisting: 1, SkippedUnknown: 1}
	if err = store.FinishProfileBatch(ctx, sum); err != nil {
		t.Fatal(err)
	}
	var n int
	if err = db.QueryRow(`SELECT attempted FROM ops.company_profile_batch_runs WHERE batch_id=$1`, batch).Scan(&n); err != nil || n != 2 {
		t.Fatalf("batch summary absent: %d %v", n, err)
	}
	var rawFlags string
	err = db.QueryRow(`SELECT to_json(review_flags)::text FROM ops.company_profile_coverage_review WHERE symbol='X000'`).Scan(&rawFlags)
	if err != nil {
		t.Fatal(err)
	}
	var flags []string
	if err = json.Unmarshal([]byte(rawFlags), &flags); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(flags, "NO_VALID_OHLCV_ROWS") ||
		!slices.Contains(flags, "FIRST_EVER_PUBLIC_TRADE_UNVERIFIED") {
		t.Fatalf("coverage flags wrong: %+v %v", flags, err)
	}
}
