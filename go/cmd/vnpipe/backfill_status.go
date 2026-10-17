package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

// backfill-status is a read-only preflight of the already imported universe
// and the durable queue. It never imports data or reserves vendor quota.
func runBackfillStatus(args []string) error {
	f := flag.NewFlagSet("backfill-status", flag.ContinueOnError)
	start := f.String("from", "", "same historical start date used for backfill")
	end := f.String("to", "", "same historical end date used for backfill")
	source := f.String("source", "vci", "probe-verified vendor source")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) > 0 || *start == "" || *end == "" || *source != "vci" {
		return errors.New("backfill-status requires --from DATE --to DATE and source vci")
	}
	if _, err := config.Load(configPath()); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	queue, err := ingest.LoadVerifiedBackfillUniverse(ctx, db, time.Now(), *start, *end, *source)
	if err != nil {
		return err
	}
	// Never emit entire universe or prices. An explicit sample makes progress
	// inspectable while keeping a single small JSONL-friendly response.
	preview := queue.Pending
	if len(preview) > 10 {
		preview = preview[:10]
	}
	return json.NewEncoder(os.Stdout).Encode(struct {
		AsOf           string   `json:"listing_as_of"`
		Total          int      `json:"symbols"`
		Completed      int      `json:"completed"`
		Partial        int      `json:"partial"`
		Blocked        int      `json:"blocked"`
		Leased         int      `json:"leased"`
        DeferredInvalid int `json:"deferred_invalid_frame"`
		Pending        int      `json:"pending"`
		PendingPreview []string `json:"pending_preview"`
		Verified       bool     `json:"source_provenance_verified"`
	}{queue.AsOf, queue.Total, queue.Completed, queue.Partial, queue.Blocked, queue.Leased, queue.DeferredInvalid, len(queue.Pending), preview, true})
}