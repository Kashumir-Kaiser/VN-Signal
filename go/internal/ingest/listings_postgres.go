package ingest

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// ListingImportSummary reports authoritative storage, not an API call.
type ListingImportSummary struct {
	AsOf             string `json:"as_of"`
	Symbols          int    `json:"symbols"`
	ProviderRows     int    `json:"provider_rows"`
	ExcludedDelisted int    `json:"excluded_delisted"`
	Deactivated      int    `json:"deactivated"`
	AlreadyImported  bool   `json:"already_imported"`
}

// ImportListingSnapshot atomically records an independently probed, complete
// listing frame, one snapshot per symbol/date, and updates current active flags.
// It is deliberately OFFLINE: it never invokes vnstock or spends quota.
func (p *PostgresStore) ImportListingSnapshot(ctx context.Context, snap ListingSnapshot) (ListingImportSummary, error) {
	result := ListingImportSummary{}
	if p == nil || p.DB == nil {
		return result, errors.New("PostgreSQL connection required")
	}
	if err := RevalidateBeforeImport(snap); err != nil {
		return result, err
	}
	result.AsOf = snap.AsOf
	result.Symbols = len(snap.Listings)
	result.ProviderRows = snap.ProviderRows
	result.ExcludedDelisted = snap.ExcludedDelisted
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return ListingImportSummary{}, err
	}
	defer tx.Rollback()
	// Prevent simultaneous writers (including different operating-system processes)
	// from racing over current active status and snapshot dates.
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(2108701, 2601)`); err != nil {
		return ListingImportSummary{}, err
	}
	var last sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT max(snapshot_date)::text FROM core.listing_snapshots`).Scan(&last)
	if err != nil {
		return ListingImportSummary{}, err
	}
	if last.Valid && snap.AsOf < last.String {
		return ListingImportSummary{}, fmt.Errorf("cannot backdate current universe from %s to %s", last.String, snap.AsOf)
	}
	if last.Valid && snap.AsOf == last.String {
		rows, e := tx.QueryContext(ctx, `SELECT s.symbol, l.exchange, coalesce(l.industry,'') FROM core.listing_snapshots l JOIN core.symbols s ON s.symbol_id=l.symbol_id WHERE l.snapshot_date=$1::date ORDER BY s.symbol`, snap.AsOf)
		if e != nil {
			return ListingImportSummary{}, e
		}
		var observed []Listing
		for rows.Next() {
			var l Listing
			if e = rows.Scan(&l.Symbol, &l.Exchange, &l.Industry); e != nil {
				break
			}
			observed = append(observed, l)
		}
		if e == nil {
			e = rows.Err()
		}
		if closeErr := rows.Close(); e == nil {
			e = closeErr
		}
		if e != nil {
			return ListingImportSummary{}, e
		}
		if len(observed) != len(snap.Listings) {
			return ListingImportSummary{}, fmt.Errorf("snapshot already exists but differs in size")
		}
		for i := range observed {
			if observed[i] != snap.Listings[i] {
				return ListingImportSummary{}, fmt.Errorf("snapshot already exists but differs for %s", observed[i].Symbol)
			}
		}
		result.AlreadyImported = true
		return result, tx.Commit()
	}
	// Compute *newly* deactivated symbols, not the lifetime count of inactive
	// symbols. Relistings may make the all-time inactive count decrease.
	incoming := make(map[string]bool, len(snap.Listings))
	for _, listing := range snap.Listings {
		incoming[listing.Symbol] = true
	}
	current, err := tx.QueryContext(ctx, `SELECT symbol FROM core.symbols WHERE active=true`)
	if err != nil {
		return ListingImportSummary{}, err
	}
	active := 0
	for current.Next() {
		var symbol string
		if err = current.Scan(&symbol); err != nil {
			break
		}
		active++
		if !incoming[symbol] {
			result.Deactivated++
		}
	}
	if err == nil {
		err = current.Err()
	}
	if closeErr := current.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return ListingImportSummary{}, err
	}
	// A sudden >5% shrinkage is more likely to be a partial provider response
	// than genuine delistings. Preserve all old state instead of hiding symbols.
	if active > 0 && len(snap.Listings)*100 < active*95 {
		return ListingImportSummary{}, fmt.Errorf("%w: listing count fell from %d to %d (>5%%)", ErrInvalidListing, active, len(snap.Listings))
	}
	ingestID, err := newUUID()
	if err != nil {
		return ListingImportSummary{}, err
	}
	var masterLandingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES($1::uuid,'vci','equity_list',$2,NULL,$3::jsonb,$4,$5) RETURNING landing_id`, ingestID, snap.CollectedAt, string(snap.Frame), snap.SHA256, []byte(snap.Frame)).Scan(&masterLandingID)
	if err != nil {
		return ListingImportSummary{}, fmt.Errorf("raw listing landing: %w", err)
	}
	// Set obsolete members inactive only once the entire replacement frame has
	// passed validation and shrinkage checks, and while the transaction is locked.
	if active > 0 {
		if _, err = tx.ExecContext(ctx, `UPDATE core.symbols SET active=false WHERE active=true`); err != nil {
			return ListingImportSummary{}, err
		}
	}
	for _, row := range snap.Listings {
		var industry any
		if row.Industry != "" {
			industry = row.Industry
		}
		var id int64
		err = tx.QueryRowContext(ctx, `INSERT INTO core.symbols(symbol,exchange,industry,first_seen_at,last_seen_at,active)
    VALUES($1,$2,$3,$4,$4,true)
    ON CONFLICT(symbol) DO UPDATE SET exchange=excluded.exchange,industry=excluded.industry,
     last_seen_at=excluded.last_seen_at,active=true RETURNING symbol_id`, row.Symbol, row.Exchange, industry, snap.CollectedAt).Scan(&id)
		if err != nil {
			return ListingImportSummary{}, fmt.Errorf("upsert listing %s: %w", row.Symbol, err)
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO core.listing_snapshots(snapshot_date,symbol_id,exchange,industry) VALUES($1::date,$2,$3,$4)`, snap.AsOf, id, row.Exchange, industry)
		if err != nil {
			return ListingImportSummary{}, fmt.Errorf("snapshot %s: %w", row.Symbol, err)
		}
	}
	// Preserve ALL provider security categories from this same metered call,
	// including DELISTED, without adding them to the active OHLCV universe.
	if _, _, _, err = syncSecurityLandingTx(ctx, tx, masterLandingID); err != nil {
		return ListingImportSummary{}, fmt.Errorf("transactional securities master: %w", err)
	}
	if err = tx.Commit(); err != nil {
		return ListingImportSummary{}, err
	}
	return result, nil
}