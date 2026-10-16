package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

// quotaGuardStore is a narrowly scoped seam for fault-injected, offline tests.
// Production implements it with PostgreSQL; no cache or fake implementation is
// ever used to authorize real market-data calls.
type quotaGuardStore interface {
	QuotaRefreshRequired(context.Context, time.Duration) (bool, error)
	InstallQuota(context.Context, ingest.QuotaSnapshot) error
}

// ensureFreshQuota is invoked BEFORE each new market-data reservation. It
// neither requests a market route nor ever refunds an already spent call.
func ensureFreshQuota(ctx context.Context, store quotaGuardStore, rpm int, read func(context.Context) (ingest.QuotaSnapshot, error)) error {
	if store == nil || read == nil || rpm < 1 || rpm > 60 {
		return ingest.ErrNoQuotaSnapshot
	}
	needed, err := store.QuotaRefreshRequired(ctx, 90*time.Second)
	if err != nil {
		return err
	}
	if !needed {
		return ctx.Err()
	}
	snapshot, err := read(ctx)
	if err != nil {
		return fmt.Errorf("fresh absolute quota report required: %w", err)
	}
	if snapshot.VerifiedRPM != rpm { // refuse a different tier/rate mid-run
		return fmt.Errorf("tier changed from %d RPM to %d RPM; restart explicitly", rpm, snapshot.VerifiedRPM)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := store.InstallQuota(ctx, snapshot); err != nil {
		return fmt.Errorf("durable quota refresh rejected: %w", err)
	}
	return nil
}

// observeAbsoluteQuota is read-only with respect to market-data endpoints.
// Unknown, percentage-only, or non-JSON usage fails closed. The short-lived
// observation timestamp is assigned AFTER obtaining the CLI report.
func observeAbsoluteQuota(ctx context.Context, days int, invoke func(context.Context, map[string]any) (worker.Response, error)) (ingest.QuotaSnapshot, error) {
	if days < 1 || days > 31 || invoke == nil {
		return ingest.QuotaSnapshot{}, quota.ErrUnknown
	}
	reply, err := invoke(ctx, map[string]any{"id": "backfill-quota-verify", "op": "probe", "active": false})
	if err != nil {
		return ingest.QuotaSnapshot{}, err
	}
	if reply.ID != "backfill-quota-verify" || !reply.OK {
		return ingest.QuotaSnapshot{}, errors.New("passive quota worker report failed or mismatched")
	}
	var report struct{ Status, Usage json.RawMessage }
	if err := json.Unmarshal(reply.Data, &report); err != nil {
		return ingest.QuotaSnapshot{}, err
	}
	daily, monthly, err := quota.ParseRemaining(report.Usage)
	if err != nil {
		return ingest.QuotaSnapshot{}, err
	}
	rpm, err := quota.TierRPM(report.Status, report.Usage)
	if err != nil {
		return ingest.QuotaSnapshot{}, err
	}
	if _, err := quota.Budget(daily, monthly, days); err != nil {
		return ingest.QuotaSnapshot{}, err
	}
	return ingest.QuotaSnapshot{
		DailyRemaining: daily, MonthlyRemaining: monthly,
		TradingDaysRemaining: days, VerifiedRPM: rpm,
		ObservedAt: time.Now().UTC().Add(-time.Millisecond),
	}, ctx.Err()
}
