//go:build postgres_integration

package ingest

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

// Live database test: a second observation, even a vendor-cached one that
// repeats the earlier counts, cannot replenish already-spent account calls.
func TestPostgresQuotaRefreshPreservesSpentBudget(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	first := QuotaSnapshot{DailyRemaining: 10, MonthlyRemaining: 100, TradingDaysRemaining: 2,
		VerifiedRPM: 60, ObservedAt: time.Now().UTC().Add(-time.Second)}
	if err := store.InstallQuota(ctx, first); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		job := BackfillJob{Route: "equity_ohlcv", Symbol: fmt.Sprintf("Q%02d", i), Start: "2026-01-01", End: "2026-01-02"}
		_, err = store.ReserveAttempt(ctx, job, "quota-refresh-"+job.Symbol, "vci", time.Now())
		if err != nil {
			t.Fatalf("reservation %d: %v", i, err)
		}
	}
	var beforeBudget, beforeSpent int
	if err := db.QueryRowContext(ctx, `SELECT call_budget,spent FROM ops.quota_guard`).Scan(&beforeBudget, &beforeSpent); err != nil {
		t.Fatal(err)
	}
	if beforeBudget != 8 || beforeSpent != 3 {
		t.Fatalf("budget=%d spent=%d before refresh", beforeBudget, beforeSpent)
	}
	second := first
	second.ObservedAt = time.Now().UTC().Add(-time.Millisecond)
	if err := store.InstallQuota(ctx, second); err != nil {
		t.Fatal(err)
	}
	var budget, spent, reservations int
	if err := db.QueryRowContext(ctx, `SELECT call_budget,spent FROM ops.quota_guard`).Scan(&budget, &spent); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM ops.api_reservations`).Scan(&reservations); err != nil {
		t.Fatal(err)
	}
	if budget != 5 || spent != 0 || reservations != 3 {
		t.Fatalf("quota resurrected: budget=%d spent=%d reservations=%d", budget, spent, reservations)
	}
	// The read-only due check must become true before expiry, and reject an
	// old Vietnam market-day allowance even if the process was suspended.
	observedNow := store.clock()
	due, err := store.QuotaRefreshRequired(ctx, 90*time.Second)
	if err != nil || due {
		t.Fatalf("fresh quota unexpectedly due: %v %v", due, err)
	}
	store.Now = func() time.Time { return observedNow.Add(4 * time.Minute) }
	due, err = store.QuotaRefreshRequired(ctx, 90*time.Second)
	if err != nil || !due {
		t.Fatalf("near expiry not detected: %v %v", due, err)
	}
	store.Now = func() time.Time { return observedNow.Add(26 * time.Hour) }
	if _, err = store.QuotaRefreshRequired(ctx, 90*time.Second); !errors.Is(err, ErrNoQuotaSnapshot) {
		t.Fatalf("previous market day allowed: %v", err)
	}
}