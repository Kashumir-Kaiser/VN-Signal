package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
)

func TestBackfillIsNeverImplicit(t *testing.T) {
	if err := runBackfill(nil); err == nil {
		t.Fatal("accepted backfill without explicit authorization")
	}
}
func TestBackfillFailsBeforeAnyVendorCallInCI(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	// Even a convincing report cannot bypass the environment's hard stop.
	err := runBackfill([]string{"--active", "--probe", "/nonexistent"})
	if !errors.Is(err, live.ErrDisabled) {
		t.Fatalf("CI was not disabled: %v", err)
	}
}

func TestBackfillRejectsCallerSuppliedSymbols(t *testing.T) {
	err := runBackfill([]string{"--active", "--probe", "/nonexistent", "--symbols", "FPT"})
	if err == nil || !strings.Contains(err.Error(), "flag provided but not defined: -symbols") {
		t.Fatalf("accepted caller-supplied symbols: %v", err)
	}
}

func TestMigrationCannotRunWithoutDriver(t *testing.T) {
	// This test runs only in the default build; tagged PostgreSQL builds
	// exercise the real driver in the integration test workflow.
	t.Setenv("DATABASE_URL", "")
	err := run([]string{"migrate", "--dir", "/absent"})
	if err == nil || (!strings.Contains(err.Error(), "driver") && !strings.Contains(err.Error(), "DATABASE_URL")) {
		t.Fatalf("accepted unconfigured database migration: %v", err)
	}
}
