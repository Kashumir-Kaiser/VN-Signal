//go:build !postgres

package main

import (
	"context"
	"database/sql"
	"errors"
)

// Default/offline build deliberately cannot open PostgreSQL for live ingestion.
// Use the explicitly tagged, pinned PGX build on the user's own machine.
func openPostgres(context.Context, string) (*sql.DB, error) {
	return nil, errors.New("PostgreSQL driver not linked: rebuild with -tags postgres on an authorized local machine")
}
