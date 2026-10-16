//go:build postgres_integration

package ingest

import (
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
func verified(t *testing.T, s *PostgresStore, budget int) {
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
	verified(t, store, 3)
	_, err := db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES('FPT','HOSE',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	p, _ := quota.NewPacer(60, 3)
	calls := 0
	gate, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		return worker.Response{ID: job["id"].(string), OK: true, Data: json.RawMessage(payload("["+one+"]", 1))}, nil
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
	again, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
	if err != nil || again.Skipped != 1 || calls != 1 {
		t.Fatalf("resume=%+v err=%v calls=%d", again, err, calls)
	}
}
func TestPostgresDurableQuotaAndRollback(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	verified(t, s, 1)
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
	raw := json.RawMessage(payload("["+one+"]", 1))
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
