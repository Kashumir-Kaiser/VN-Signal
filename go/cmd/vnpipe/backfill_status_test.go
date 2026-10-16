package main

import (
	"strings"
	"testing"
)

func TestBackfillStatusRejectsIncompleteArgumentsWithoutSideEffects(t *testing.T) {
	for _, args := range [][]string{{}, {"--from", "2018-10-01"}, {"--from", "2018-10-01", "--to", "2026-10-16", "--source", "unknown"}, {"--from", "2018-10-01", "--to", "2026-10-16", "unexpected"}} {
		if err := runBackfillStatus(args); err == nil || !strings.Contains(err.Error(), "backfill-status requires") {
			t.Fatalf("invalid arguments accepted: %v err=%v", args, err)
		}
	}
}