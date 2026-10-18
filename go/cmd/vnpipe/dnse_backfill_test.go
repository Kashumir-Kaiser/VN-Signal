package main

import (
	"reflect"
	"testing"
)

func TestParseDNSEBackfillArgs(t *testing.T) {
	parsed, err := parseDNSEBackfillArgs([]string{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--symbols", "vcb,ABC", "--max-calls", "2", "--pace", "750ms"})
	if err != nil {
		t.Fatal(err)
	}
	if parsed.symbols != "ABC,VCB" || parsed.maxCalls != 2 || !parsed.active || parsed.pace.String() != "750ms" {
		t.Fatalf("unexpected options: %+v", parsed)
	}
}

func TestParseDNSEBackfillArgsRejectsUnsafeOrAmbiguousRequests(t *testing.T) {
	valid := []string{"--active", "--from", "2018-10-01", "--to", "2026-10-16"}
	if _, err := parseDNSEBackfillArgs(valid[1:]); err == nil {
		t.Fatal("missing explicit active authorization accepted")
	}
	for _, args := range [][]string{
		{"--active", "--from", "2026-10-17", "--to", "2026-10-16"},
		{"--active", "--from", "2018-02-30", "--to", "2026-10-16"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--symbols", "VCB,vcb"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--pace", "1ms"},
		{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--max-calls", "2001"},
	} {
		if _, err := parseDNSEBackfillArgs(args); err == nil {
			t.Errorf("unsafe request accepted: %v", args)
		}
	}
}

func TestSortedKeys(t *testing.T) {
	got := sortedKeys(map[string]bool{"VCB": true, "ABC": true, "HPG": true})
	want := []string{"ABC", "HPG", "VCB"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
