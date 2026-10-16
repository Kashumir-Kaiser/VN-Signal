package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

// runImportListings imports an already-metered and saved active probe frame.
// There are no new vendor calls or runtime API-key requirements at import time.
func runImportListings(args []string) error {
	f := flag.NewFlagSet("import-listings", flag.ContinueOnError)
	probePath := f.String("probe", "", "Go active probe report with embedded listing_frame")
	minimum := f.Int("min-symbols", 1000, "minimum full-universe symbols for a complete snapshot")
	if err := f.Parse(args); err != nil {
		return err
	}
	if len(f.Args()) != 0 || *probePath == "" || *minimum < 1000 {
		return errors.New("import-listings requires --probe and --min-symbols >= 1000 to protect full-universe snapshots")
	}
	file, err := os.Open(*probePath)
	if err != nil {
		return err
	}
	defer file.Close()
	b, err := io.ReadAll(io.LimitReader(file, 12*1024*1024+1))
	if err != nil {
		return err
	}
	snapshot, err := ingest.ParseListingProbe(b, *minimum)
	if err != nil {
		return fmt.Errorf("refusing partial or unverified listing probe: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	db, err := openPostgres(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return err
	}
	defer db.Close()
	store, err := ingest.NewPostgresStore(db)
	if err != nil {
		return err
	}
	result, err := store.ImportListingSnapshot(ctx, snapshot)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}
