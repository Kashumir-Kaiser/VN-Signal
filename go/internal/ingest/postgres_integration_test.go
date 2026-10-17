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
	"os"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func pgTestDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL is mandatory for postgres integration")
	}
	db, e := sql.Open("pgx", dsn)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { db.Close() })
	if e = db.PingContext(context.Background()); e != nil {
		t.Fatal(e)
	}
	return db
}
func clearDB(t *testing.T, db *sql.DB) {
	t.Helper()
	_, e := db.Exec(`TRUNCATE ops.api_reservations,ops.ingest_jobs,raw.landings,core.bars_daily,core.listing_snapshots,core.symbols,ops.quota_guard RESTART IDENTITY CASCADE`)
	if e != nil {
		t.Fatal(e)
	}
}
func installVerifiedQuota(t *testing.T, s *PostgresStore, budget int) {
	t.Helper()
	// DailyRemaining=budget*2 means floor(80%) >= budget for budget>=2.
	e := s.InstallQuota(context.Background(), QuotaSnapshot{DailyRemaining: budget * 2, MonthlyRemaining: 10000, TradingDaysRemaining: 2, VerifiedRPM: 60, ObservedAt: time.Now().Add(-500 * time.Millisecond)})
	if e != nil {
		t.Fatal(e)
	}
}
func TestPostgresIngestionTransactionAndResume(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	installVerifiedQuota(t, store, 3)
	_, err := db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES('FPT','HOSE',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	p, _ := quota.NewPacer(60, 3)
	calls := 0
	gate, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		return worker.Response{ID: job["id"].(string), OK: true, Data: json.RawMessage(payload("["+two+"]", 1))}, nil
	})
	runner := Runner{Gateway: gate, Store: store, Now: time.Now}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	sum, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job, job}, "vci")
	if err != nil || sum.Committed != 1 || sum.Skipped != 1 || calls != 1 {
		t.Fatalf("sum=%+v err=%v calls=%d", sum, err, calls)
	}
	var n int
	for _, q := range []string{
		`SELECT COUNT(*) FROM raw.landings`,
		`SELECT COUNT(*) FROM core.bars_daily`,
		`SELECT COUNT(*) FROM ops.ingest_jobs WHERE state='COMPLETED' AND landed_id IS NOT NULL`,
		`SELECT COUNT(*) FROM ops.api_reservations WHERE outcome='SUCCEEDED'`,
	} {
		if err = db.QueryRow(q).Scan(&n); err != nil || n != 1 {
			t.Fatalf("query=%s n=%d err=%v", q, n, err)
		}
	}
	// JSONB is intentionally queryable, but exact bytes must also survive
	// normalization for provenance/hash verification.
	var original []byte
	if err = db.QueryRow(`SELECT payload_bytes FROM raw.landings WHERE route='equity_ohlcv' LIMIT 1`).Scan(&original); err != nil ||
		!bytes.Equal(original, []byte(payload("["+two+"]", 1))) {
		t.Fatalf("vendor payload byte parity: %v", err)
	}
	again, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
	if err != nil || again.Skipped != 1 || calls != 1 {
		t.Fatalf("resume=%+v err=%v calls=%d", again, err, calls)
	}
}
func TestPostgresDurableQuotaAndRollback(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	installVerifiedQuota(t, s, 1)
	ctx := context.Background()
	a := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	b := BackfillJob{Route: "equity_ohlcv", Symbol: "HPG", Start: "2026-10-15", End: "2026-10-16"}
	at := time.Now().Add(time.Second)
	_, err := s.ReserveAttempt(ctx, a, "quota-test-A", "vci", at)
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.ReserveAttempt(ctx, b, "quota-test-B", "vci", at)
	if !errors.Is(err, quota.ErrExhausted) {
		t.Fatalf("quota budget bypass: %v", err)
	}
	if err = s.MarkDispatch(ctx, "quota-test-A"); err != nil {
		t.Fatal(err)
	}
	if err = s.MarkOutcome(ctx, "quota-test-A", "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(payload("["+two+"]", 1))
	bars, err := NormalizeBars("FPT", raw)
	if err != nil {
		t.Fatal(err)
	}
	// No core.symbols FPT exists: every insert must roll back, including raw.
	land := Landing{JobID: "quota-test-A", Source: "vci", FetchedAt: time.Now(), Raw: raw, Bars: bars}
	land.SHA256 = checksum(raw)
	if err = s.CommitLanding(ctx, land); err == nil {
		t.Fatal("committed before listing")
	}
	var count int
	if err = db.QueryRow(`SELECT COUNT(*) FROM raw.landings`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("partial raw landing: %d %v", count, err)
	}
	if err = db.QueryRow(`SELECT COUNT(*) FROM core.bars_daily`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("partial bars: %d %v", count, err)
	}
	// Even after a restart a fresh store sees the same spent allowance.
	fresh, _ := NewPostgresStore(db)
	_, err = fresh.ReserveAttempt(ctx, b, "quota-test-B", "vci", at)
	if !errors.Is(err, quota.ErrExhausted) {
		t.Fatalf("restart reset quota: %v", err)
	}
}

func checksum(data []byte) string { x := sha256.Sum256(data); return hex.EncodeToString(x[:]) }

func TestPostgresQuarantinePreservesRawWithoutCanonicalBars(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	installVerifiedQuota(t, s, 1)
	ctx := context.Background()
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "A32", Start: "2026-10-15", End: "2026-10-16"}
	key := "equity_ohlcv:A32:vci:2026-10-15:2026-10-16"
	if _, err := s.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkDispatch(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkOutcome(ctx, key, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(payload(`[{"time":"2026-10-15","open":0,"high":105,"low":99,"close":103,"volume":100}]`, 1))
	reason := "InvalidFrame: row 0 date 2026-10-15: open price is nonpositive or nonfinite"
	if err := s.QuarantineFrame(ctx, key, "vci", reason, raw); err != nil {
		t.Fatal(err)
	}
	var state, recordedReason, route, digest string
	var archived []byte
	if err := db.QueryRow(`SELECT j.state,j.last_error_type,l.route,l.payload_bytes,l.payload_sha256
        FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id
        WHERE j.idempotency_key=$1`, key).Scan(&state, &recordedReason, &route, &archived, &digest); err != nil {
		t.Fatal(err)
	}
	if state != "BLOCKED" || recordedReason != reason || route != "equity_ohlcv_quarantine" ||
		!bytes.Equal(archived, []byte(raw)) || digest != checksum(raw) {
		t.Fatalf("quarantine lost provenance: state=%s reason=%s route=%s", state, recordedReason, route)
	}
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM core.bars_daily`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("invalid bars entered canonical storage: %d %v", count, err)
	}
	if err := s.QuarantineFrame(ctx, key, "vci", reason, raw); err == nil {
		t.Fatal("duplicate quarantine unexpectedly succeeded")
	}
}

func TestMarketArchiveOfflineRecoveryPreservesInvalidRowsAndQuota(t *testing.T) {
    t.Setenv("VNPIPE_DISABLE_LIVE","1")
    db:=pgTestDB(t)
    clearDB(t,db)
    store,_:=NewPostgresStore(db)
    installVerifiedQuota(t,store,2)
    ctx:=context.Background()
    _,err:=db.Exec(`INSERT INTO core.symbols (symbol,exchange,first_seen_at,last_seen_at)
        VALUES ('ABR','UPCOM',now(),now())`)
    if err!=nil{t.Fatal(err)}
    job:=BackfillJob{Route:"equity_ohlcv",Symbol:"ABR",Start:"2019-01-10",End:"2019-01-14"}
    key:="equity_ohlcv:ABR:vci:2019-01-10:2019-01-14"
    if _,err=store.ReserveAttempt(ctx,job,key,"vci",time.Now());err!=nil{t.Fatal(err)}
    if err=store.MarkDispatch(ctx,key);err!=nil{t.Fatal(err)}
    if err=store.MarkOutcome(ctx,key,"SUCCEEDED","");err!=nil{t.Fatal(err)}
    raw:=json.RawMessage(payload(`[
        {"time":"2019-01-10","open":3.76,"high":3.38,"low":3.38,"close":3.38,"volume":0},
        {"time":"2019-01-11","open":10,"high":11,"low":9,"close":10.5,"volume":100},
        {"time":"2019-01-14","open":10,"high":9,"low":8,"close":9,"volume":100}]`,3))
    if err=store.QuarantineFrame(ctx,key,"vci","InvalidFrame",raw);err!=nil{t.Fatal(err)}
    state,err:=store.RecoverArchivedFrame(ctx,key)
    if err!=nil || state!="PARTIAL" {t.Fatalf("recovery=%s err=%v",state,err)}
    for query,want:=range map[string]int{
        "SELECT count(*) FROM raw.landings":1,
        "SELECT count(*) FROM core.bars_daily":1,
        "SELECT count(*) FROM ops.bar_quality_issues":2,
        "SELECT count(*) FROM ops.bar_quality_issues WHERE category='ZERO_VOLUME_UNVERIFIED'":1,
        "SELECT count(*) FROM ops.bar_quality_issues WHERE category='INVALID_OHLC'":1,
        "SELECT count(*) FROM ops.ingest_jobs WHERE state='PARTIAL'":1,
        "SELECT count(*) FROM ops.api_reservations":1,
    }{
        var n int
        if err=db.QueryRow(query).Scan(&n);err!=nil||n!=want {
            t.Fatalf("%s: got %d want %d err=%v",query,n,want,err)
        }
    }
    var traded bool
    if err=db.QueryRow(`SELECT is_traded FROM core.bars_daily`).Scan(&traded);err!=nil||!traded {
        t.Fatal("canonical bar is not an actual traded session")
    }
    if _,err=store.RecoverArchivedFrame(ctx,key);err==nil {
        t.Fatal("replayed already recovered frame")
    }
}

func TestLegacyUnarchivedRequeueIsAuditedAndDoesNotRefundQuota(t *testing.T) {
    db:=pgTestDB(t)
    clearDB(t,db)
    s,_:=NewPostgresStore(db)
    installVerifiedQuota(t,s,3)
    _,err:=db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES ('A32','UPCOM',now(),now())`)
    if err!=nil{t.Fatal(err)}
    ctx:=context.Background()
    job:=BackfillJob{Route:"equity_ohlcv",Symbol:"A32",Start:"2018-10-01",End:"2026-10-16"}
    key:="equity_ohlcv:A32:vci:2018-10-01:2026-10-16"
    if _,err=s.ReserveAttempt(ctx,job,key,"vci",time.Now());err!=nil{t.Fatal(err)}
    if err=s.MarkDispatch(ctx,key);err!=nil{t.Fatal(err)}
    if err=s.MarkOutcome(ctx,key,"SUCCEEDED","");err!=nil{t.Fatal(err)}
    if err=s.BlockInvalid(ctx,key,"InvalidFrame");err!=nil{t.Fatal(err)}
    if err=s.RequeueUnarchivedLegacy(ctx,"A32",job.Start,job.End,"vci");err!=nil{t.Fatal(err)}
    var state string
    if err=db.QueryRow(`SELECT state FROM ops.ingest_jobs WHERE idempotency_key=$1`,key).Scan(&state);err!=nil||state!="PENDING"{
        t.Fatalf("wrong post-requeue state %s: %v",state,err)
    }
    if err=s.RequeueUnarchivedLegacy(ctx,"A32",job.Start,job.End,"vci");err==nil{
        t.Fatal("duplicate requeue accepted")
    }
    if _,err=s.ReserveAttempt(ctx,job,key,"vci",time.Now());err!=nil{t.Fatalf("not safely retryable: %v",err)}
    for query,want:=range map[string]int{
        "SELECT count(*) FROM ops.ingest_requeue_audit":1,
        "SELECT count(*) FROM ops.api_reservations":2,
        "SELECT attempts FROM ops.ingest_jobs WHERE symbol='A32'":2,
        "SELECT spent FROM ops.quota_guard WHERE singleton=true":2,
    }{
        var n int
        if err=db.QueryRow(query).Scan(&n);err!=nil||n!=want {
            t.Fatalf("audit quota mismatch %s got=%d want=%d err=%v",query,n,want,err)
        }
    }
}

func TestLifecycleZeroVolumeNeverImpliedListed(t *testing.T) {
    db:=pgTestDB(t)
    clearDB(t,db)
    ctx:=context.Background()
    _=ctx
    _,err:=db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES('LC1','UPCOM',now(),now())`)
    if err!=nil{t.Fatal(err)}
    source:=[]byte(`{"official_notice":"first-ever public trade and dated status intervals","example_fixture":true}`)
    originalDigest:=checksum(source)
    var landingID int64
    err=db.QueryRow(`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES('00000000-0000-0000-0000-000000000071','official',
               'security_lifecycle_notice',now(),'LC1',$1::jsonb,$2,$3)
        RETURNING landing_id`,string(source),originalDigest,source).Scan(&landingID)
    if err!=nil{t.Fatal(err)}
    var jobID int64
    err=db.QueryRow(`INSERT INTO ops.ingest_jobs
        (idempotency_key,route,symbol,source,date_from,date_to,state)
        VALUES('equity_ohlcv:LC1:vci:2018-01-01:2020-04-15',
          'equity_ohlcv','LC1','vci','2018-01-01','2020-04-15','PENDING')
        RETURNING job_id`).Scan(&jobID)
    if err!=nil{t.Fatal(err)}
    dates:=[]string{"2018-01-15","2020-01-15","2020-02-15","2020-03-15","2020-04-15"}
    for i,date:=range dates{
        _,err=db.Exec(`INSERT INTO ops.bar_quality_issues
            (job_id,landing_id,source_row,trade_date,category,reason)
            VALUES($1,$2,$3,$4::date,'ZERO_VOLUME_UNVERIFIED','zero source volume')`,
            jobID,landingID,i,date)
        if err!=nil{t.Fatal(err)}
    }
    var unknown int
    err=db.QueryRow(`SELECT count(*) FROM ops.zero_volume_lifecycle_status
        WHERE derived_lifecycle_status='LISTING_STATUS_UNVERIFIED'`).Scan(&unknown)
    if err!=nil||unknown!=5{t.Fatalf("premature tradability inference: %d %v",unknown,err)}
    var symbolID int64
    if err=db.QueryRow(`SELECT symbol_id FROM core.symbols WHERE symbol='LC1'`).Scan(&symbolID);err!=nil{
        t.Fatal(err)
    }
    insert:=func(kind,start,end string){
        t.Helper()
        _,err=db.Exec(`INSERT INTO core.security_lifecycle_evidence
            (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
            VALUES ($1,'UPCOM',$2,$3::date,$4::date,$5,
             'https://www.hnx.vn/en-gb/co-phieu.html','2020-01-01')`,
             symbolID,kind,start,end,landingID)
        if err!=nil{t.Fatalf("insert %s: %v",kind,err)}
    }
    insert("FIRST_EVER_PUBLIC_TRADE","2020-01-01","2020-01-01")
    insert("TRADE_ELIGIBLE","2020-01-01","2020-01-31")
    insert("TRADING_SUSPENDED","2020-02-01","2020-02-29")
    insert("DELISTED","2020-03-01","2020-03-31")
    expected:=[]string{"BEFORE_FIRST_PUBLIC_TRADE","VERIFIED_ELIGIBLE_NO_MATCH",
        "VERIFIED_SUSPENDED","VERIFIED_DELISTED","LISTING_STATUS_UNVERIFIED"}
    rows,err:=db.Query(`SELECT derived_lifecycle_status
        FROM ops.zero_volume_lifecycle_status ORDER BY trade_date`)
    if err!=nil{t.Fatal(err)}
    got:=[]string{}
    for rows.Next(){
        var status string
        if err=rows.Scan(&status);err!=nil{rows.Close();t.Fatal(err)}
        got=append(got,status)
    }
    if err=rows.Err();err!=nil{t.Fatal(err)}
    rows.Close()
    if len(got)!=len(expected){t.Fatalf("status coverage %+v",got)}
    for i,v:=range expected{if got[i]!=v {t.Fatalf("%s => %s, want %s",dates[i],got[i],v)}}
    insert("TRADE_ELIGIBLE","2020-02-10","2020-02-20")
    var conflicting string
    err=db.QueryRow(`SELECT derived_lifecycle_status FROM ops.zero_volume_lifecycle_status
        WHERE trade_date='2020-02-15'`).Scan(&conflicting)
    if err!=nil||conflicting!="CONFLICTING_EVIDENCE"{
        t.Fatalf("contradictory trading windows silently accepted: %s %v",conflicting,err)
    }
    if _,err=db.Exec(`UPDATE core.security_lifecycle_evidence SET date_from='2000-01-01'
        WHERE symbol_id=$1`,symbolID);err==nil{
        t.Fatal("source lifecycle evidence was mutable")
    }
    _,err=db.Exec(`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES('00000000-0000-0000-0000-000000000072','official',
               'security_lifecycle_notice',now(),'LC1',$1::jsonb,$2,$3)`,
        string(source),"0000000000000000000000000000000000000000000000000000000000000000",source)
    if err!=nil{t.Fatal(err)}
    _,err=db.Exec(`INSERT INTO core.security_lifecycle_evidence
        (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
        SELECT $1,'UPCOM','TRADING_SUSPENDED','2020-04-01','2020-04-30',
               max(landing_id),'https://www.hnx.vn/en-gb/co-phieu.html','2020-01-01'
        FROM raw.landings`,symbolID)
    if err==nil{t.Fatal("tampered archived evidence digest accepted")}
}
