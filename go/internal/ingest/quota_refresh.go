package ingest

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// QuotaRefreshRequired checks the durable, cross-process guard before every
// potential vendor request. It does not replenish budget or contact vnstock.
// A cross-midnight guard is rejected: start a new explicitly authorized run
// with a new absolute quota sample, rather than silently continuing overnight.
func (p *PostgresStore) QuotaRefreshRequired(ctx context.Context, lead time.Duration) (bool, error) {
	if p == nil || p.DB == nil || lead < 0 || lead > 2*time.Minute {
		return false, ErrNoQuotaSnapshot
	}
	if err := ctx.Err(); err != nil {
		return false, err
	}
	var expires time.Time
	var day string
	err := p.DB.QueryRowContext(ctx, `SELECT expires_at,day_key::text FROM ops.quota_guard WHERE singleton=true`).Scan(&expires, &day)
	if errors.Is(err, sql.ErrNoRows) {
		return false, ErrNoQuotaSnapshot
	}
	if err != nil {
		return false, fmt.Errorf("quota guard read: %w", err)
	}
	now := p.clock()
	if day != vietnamDate(now) {
		return false, fmt.Errorf("%w: Vietnam trading date changed; restart with newly verified quota", ErrNoQuotaSnapshot)
	}
	return !now.Add(lead).Before(expires), nil
}