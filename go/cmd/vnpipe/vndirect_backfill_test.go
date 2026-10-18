package main

import "testing"

func TestParseVNDIRECTBackfillArgs(t *testing.T) {
	parsed, err := parseVNDIRECTBackfillArgs([]string{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--symbols", "vcb,ABC", "--max-calls", "2", "--pace", "750ms", "--shard-index", "1", "--shard-count", "4"})
	if err != nil {
		t.Fatal(err)
	}
	if parsed.symbols != "ABC,VCB" || parsed.maxCalls != 2 || !parsed.active || parsed.pace.String() != "750ms" || parsed.shardIndex != 1 || parsed.shardCount != 4 {
		t.Fatalf("unexpected options: %+v", parsed)
	}
}

func TestParseVNDIRECTBackfillArgsRejectsUnsafeOrAmbiguousRequests(t *testing.T) {
	valid := []string{"--active", "--from", "2018-10-01", "--to", "2026-10-16"}
	if _, err := parseVNDIRECTBackfillArgs(valid[1:]); err == nil {
		t.Fatal("missing explicit active authorization accepted")
	}
	for _, args := range [][]string{
		{"--active", "--from", "2026-10-17", "--to", "2026-10-16"},
		{"--active", "--from", "2018-02-30", "--to", "2026-10-16"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--symbols", "VCB,vcb"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--pace", "1ms"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--max-calls", "2001"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--shard-count", "4", "--shard-index", "4"},
	} {
		if _, err := parseVNDIRECTBackfillArgs(args); err == nil {
			t.Errorf("unsafe request accepted: %v", args)
		}
	}
}
