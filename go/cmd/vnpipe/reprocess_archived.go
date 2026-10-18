package main

import (
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

// Explicit, offline, source-backed recovery. It only converts previously
// quarantined immutable raw frames; no vnstock worker or quota gateway exists
// on this command path.
func runReprocessArchived(args []string) error {
	f := flag.NewFlagSet("reprocess-archived", flag.ContinueOnError)
	start := f.String("from", "", "original history range start")
	end := f.String("to", "", "original history range end")
	source := f.String("source", "vci", "archived source")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || *source != "vci" || *start == "" || *end == "" || *start > *end {
		return errors.New("reprocess-archived requires --from DATE --to DATE --source vci")
	}
	for _, date := range []string{*start, *end} {
		value, err := time.Parse("2006-01-02", date)
		if err != nil || value.Format("2006-01-02") != date ||
			date > time.Now().In(time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)).Format("2006-01-02") {
			return errors.New("invalid or future backfill date")
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	rows, err := db.QueryContext(ctx, `
        SELECT j.idempotency_key FROM ops.ingest_jobs j
        JOIN raw.landings l ON l.landing_id=j.landed_id
        WHERE j.route='equity_ohlcv' AND j.source='vci'
          AND j.state='PARTIAL' AND l.route IN ('equity_ohlcv','equity_ohlcv_quarantine')
          AND j.date_from=$1::date AND j.date_to=$2::date
          AND NOT EXISTS (
              SELECT 1 FROM ops.bar_quality_reprocess_audit a
              WHERE a.landing_id=l.landing_id AND a.validator_version=$3)
        ORDER BY j.symbol,j.state`, *start, *end, ingest.MarketFrameValidatorVersion)
	if err != nil {
		return err
	}
	keys := []string{}
	for rows.Next() {
		var key string
		if err = rows.Scan(&key); err != nil {
			rows.Close()
			return err
		}
		keys = append(keys, key)
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return err
	}
	if err = rows.Close(); err != nil {
		return err
	}
	store, err := ingest.NewPostgresStore(db)
	if err != nil {
		return err
	}
	completed, partial, skipped := 0, 0, 0
	for _, key := range keys {
		next, recoverErr := store.RecoverArchivedFrame(ctx, key)
		if errors.Is(recoverErr, sql.ErrNoRows) {
			skipped++
			continue
		}
		if recoverErr != nil {
			return fmt.Errorf("offline archive reprocessing %s: %w", key, recoverErr)
		}
		if next == "COMPLETED" {
			completed++
		} else if next == "PARTIAL" {
			partial++
		} else {
			return errors.New("unexpected archival reprocessing state")
		}
	}
	fmt.Printf("Offline archive reprocessing: completed=%d partial=%d skipped=%d selected=%d (zero vendor calls; quota reservations unchanged)\n",
		completed, partial, skipped, len(keys))
	return nil
}
