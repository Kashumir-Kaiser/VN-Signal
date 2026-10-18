package main

import "testing"

func TestParseKBSInvalidHistoryArgsRequiresExplicitOptIn(t *testing.T) {
	args := []string{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--days", "13", "--max-calls", "500"}
	parsed, err := parseKBSInvalidHistoryArgs(args)
	if err != nil {
		t.Fatalf("valid args rejected: %v", err)
	}
	if !parsed.active || parsed.maxCalls != 500 || parsed.start != "2018-10-01" || parsed.end != "2026-10-16" {
		t.Fatalf("unexpected parsed args: %+v", parsed)
	}
	if _, err = parseKBSInvalidHistoryArgs([]string{"--from", "2018-10-01", "--to", "2026-10-16", "--days", "13"}); err == nil {
		t.Fatal("missing --active accepted")
	}
}

func TestParseKBSInvalidHistoryArgsRejectsUnsafeRangesAndCaps(t *testing.T) {
	base := []string{"--active", "--from", "2018-10-01", "--to", "2026-10-16", "--days", "13"}
	for _, extra := range [][]string{
		{"--from", "2026-10-17"},
		{"--to", "2018-09-30"},
		{"--days", "0"},
		{"--days", "32"},
		{"--max-calls", "0"},
		{"--max-calls", "5001"},
		{"FPT"},
	} {
		args := append(append([]string{}, base...), extra...)
		if _, err := parseKBSInvalidHistoryArgs(args); err == nil {
			t.Errorf("invalid extra arguments accepted: %v", extra)
		}
	}
}

func TestKBSInvalidHistoryCandidateSelectionValidatesBounds(t *testing.T) {
	if _, err := loadKBSInvalidHistoryCandidates(nil, nil, "2026-10-16", "2018-10-01", 1); err == nil {
		t.Fatal("reversed range accepted")
	}
	if _, err := loadKBSInvalidHistoryCandidates(nil, nil, "2018-10-01", "2026-10-16", 31); err == nil {
		t.Fatal("oversized cap accepted")
	}
	if _, err := loadKBSInvalidHistoryCandidates(nil, nil, "2018-10-01", "2026-10-16", 1); err == nil {
		t.Fatal("nil database accepted")
	}
}
