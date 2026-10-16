package ingest

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"
)

// ErrUnverifiedUniverse prevents a stale, partial or tampered listing snapshot
// from becoming an ingestion universe. History is retained in PostgreSQL.
var ErrUnverifiedUniverse = errors.New("verified current listing universe required")

// UniverseSelection is a point-in-time SQL-derived queue, not a ticker list
// supplied by the user or guessed from a static watchlist.
type UniverseSelection struct {
	AsOf      string   `json:"as_of"`
	Total     int      `json:"total"`
	Completed int      `json:"completed"`
	Blocked   int      `json:"blocked"`
	Leased    int      `json:"leased"`
	Pending   []string `json:"pending"`
}

const minVerifiedUniverse = 1000
const universeMaxAgeDays = 7

func vnMarketDate(at time.Time) time.Time {
	loc := time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)
	t := at.In(loc)
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, loc)
}

func validateUniverse(asOf string, now time.Time, total, active, matched, exchanges int) error {
	day, err := time.Parse("2006-01-02", asOf)
	if err != nil || now.IsZero() {
		return ErrUnverifiedUniverse
	}
	// Compare exchange-local calendar days; a Friday snapshot remains usable
	// over the weekend, but old data cannot silently pass as current.
	today := vnMarketDate(now)
	snapshot := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, today.Location())
	age := int(today.Sub(snapshot).Hours() / 24)
	if age < 0 || age > universeMaxAgeDays || total < minVerifiedUniverse ||
		active != total || matched != total || exchanges != 3 {
		return fmt.Errorf("%w: snapshot=%s age=%d count=%d active=%d matched=%d exchanges=%d",
			ErrUnverifiedUniverse, asOf, age, total, active, matched, exchanges)
	}
	return nil
}

// LoadVerifiedBackfillUniverse supplies only uncompleted, unblocked and
// currently unleased symbols for the requested *exact* date range and source.
// All SQL reads come from the user's locally imported listing snapshot.
// The planner must cap Pending by the freshly verified absolute vendor budget.
func LoadVerifiedBackfillUniverse(ctx context.Context, db *sql.DB, now time.Time, start, end, source string) (UniverseSelection, error) {
	var result UniverseSelection
	if db == nil || ctx == nil || source != "vci" || start == "" || end == "" || start > end || now.IsZero() {
		return result, ErrUnverifiedUniverse
	}
	for _, value := range []string{start, end} {
		t, err := time.Parse("2006-01-02", value)
		if err != nil || t.Format("2006-01-02") != value || value > vnMarketDate(now).Format("2006-01-02") {
			return result, ErrUnverifiedUniverse
		}
	}
	// Repeatable-read snapshot keeps listing state and provenance consistent.
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return result, err
	}
	defer tx.Rollback()
	// A partial import, accidental modification of active flags, or missing
	// exchange never authorizes a new market-data job.
	var day sql.NullString
	if err := tx.QueryRowContext(ctx, `SELECT max(snapshot_date)::text FROM core.listing_snapshots`).Scan(&day); err != nil {
		return result, err
	}
	if !day.Valid {
		return result, ErrUnverifiedUniverse
	}
	result.AsOf = day.String
	var active, matched, exchanges int
	err = tx.QueryRowContext(ctx, `SELECT
        (SELECT count(*) FROM core.listing_snapshots WHERE snapshot_date=$1::date),
        (SELECT count(*) FROM core.symbols WHERE active),
        (SELECT count(*) FROM core.listing_snapshots l
            JOIN core.symbols s ON s.symbol_id=l.symbol_id
            WHERE l.snapshot_date=$1::date AND s.active AND s.exchange=l.exchange),
        (SELECT count(DISTINCT exchange) FROM core.listing_snapshots WHERE snapshot_date=$1::date)`, result.AsOf).
		Scan(&result.Total, &active, &matched, &exchanges)
	if err != nil {
		return UniverseSelection{}, err
	}
	if err := validateUniverse(result.AsOf, now, result.Total, active, matched, exchanges); err != nil {
		return UniverseSelection{}, err
	}
	// The importer stores raw bytes and their digest in the same transaction
	// as the listing snapshot. An absent or altered source fails closed.
	var bytes []byte
	var wantDigest string
	err = tx.QueryRowContext(ctx, `SELECT payload_bytes,payload_sha256 FROM raw.landings
        WHERE route='equity_list' AND source='vci' AND
        (fetched_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date=$1::date
        ORDER BY landing_id DESC LIMIT 1`, result.AsOf).Scan(&bytes, &wantDigest)
	if err != nil {
		return UniverseSelection{}, fmt.Errorf("%w: listing provenance: %v", ErrUnverifiedUniverse, err)
	}
	sum := sha256.Sum256(bytes)
	if len(bytes) < 2 || len(bytes) > 10*1024*1024 || !strings.EqualFold(hex.EncodeToString(sum[:]), wantDigest) {
		return UniverseSelection{}, fmt.Errorf("%w: listing provenance digest", ErrUnverifiedUniverse)
	}
	// Query once; no one-query-per-symbol loops. Exclude completed work before
	// applying the budget cap to avoid starvation on second and later runs.
	rows, err := tx.QueryContext(ctx, `SELECT s.symbol,COALESCE(j.state,''),j.updated_at
        FROM core.listing_snapshots l
        JOIN core.symbols s ON s.symbol_id=l.symbol_id
        LEFT JOIN ops.ingest_jobs j
          ON j.idempotency_key=('equity_ohlcv:' || s.symbol || ':' || $2 || ':' || $3 || ':' || $4)
        WHERE l.snapshot_date=$1::date AND s.active
        ORDER BY s.symbol`, result.AsOf, source, start, end)
	if err != nil {
		return UniverseSelection{}, err
	}
	for rows.Next() {
		var symbol, state string
		var updated sql.NullTime
		if err := rows.Scan(&symbol, &state, &updated); err != nil {
			rows.Close()
			return UniverseSelection{}, err
		}
		switch state {
		case "COMPLETED":
			result.Completed++
		case "BLOCKED":
			result.Blocked++
		case "RESERVED", "RUNNING":
			if !updated.Valid || now.Sub(updated.Time) < 15*time.Minute {
				result.Leased++
			} else {
				result.Pending = append(result.Pending, symbol)
			}
		case "", "PENDING":
			result.Pending = append(result.Pending, symbol)
		default:
			rows.Close()
			return UniverseSelection{}, fmt.Errorf("%w: unknown job state %q", ErrUnverifiedUniverse, state)
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return UniverseSelection{}, err
	}
	if err := rows.Close(); err != nil {
		return UniverseSelection{}, err
	}
	if result.Total != result.Completed+result.Blocked+result.Leased+len(result.Pending) {
		return UniverseSelection{}, fmt.Errorf("%w: inconsistent queue counts", ErrUnverifiedUniverse)
	}
	if err := tx.Commit(); err != nil {
		return UniverseSelection{}, err
	}
	return result, nil
}