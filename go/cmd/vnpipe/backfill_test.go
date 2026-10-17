package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
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

func TestBackfillCallCapPreservesDeferred(t *testing.T){
    p:=ingest.Plan{Planned:[]ingest.BackfillJob{
        {Symbol:"AAA"},{Symbol:"AAB"},{Symbol:"AAC"},{Symbol:"AAD"}},
        Deferred:[]ingest.BackfillJob{{Symbol:"AAE"}}}
    capped:=capBackfillCalls(p,2)
    if len(capped.Planned)!=2||len(capped.Deferred)!=3||
       capped.Deferred[0].Symbol!="AAC"||capped.Deferred[2].Symbol!="AAE"{
        t.Fatalf("bad capped plan %+v",capped)
    }
    if out:=capBackfillCalls(capped,5);len(out.Planned)!=2||len(out.Deferred)!=3{
        t.Fatalf("unexpected plan expansion %+v",out)
    }
}
func TestBackfillRejectsZeroMaxCalls(t *testing.T){
    if err:=runBackfill([]string{"--active","--probe","missing.json","--max-calls","0"});err==nil{
        t.Fatal("zero-call limit accepted")
    }
}
