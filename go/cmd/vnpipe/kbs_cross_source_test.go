package main

import "testing"

func TestParseKBSCrossSourceArgsRequiresExplicitOptInAndRange(t *testing.T) {
	valid := []string{"--active", "--from", "2026-09-01", "--to", "2026-09-30", "--days", "12"}
	parsed, err := parseKBSCrossSourceArgs(valid)
	if err != nil {
		t.Fatalf("valid default-cap arguments rejected: %v", err)
	}
	if parsed.sampleDate != parsed.end {
		t.Fatalf("default sample date=%s, want --to %s", parsed.sampleDate, parsed.end)
	}
	if _, err := parseKBSCrossSourceArgs([]string{"--from", "2026-09-01", "--to", "2026-09-30", "--days", "12"}); err == nil {
		t.Fatal("missing --active accepted")
	}
}

func TestParseKBSCrossSourceArgsAllowsSampleDateInsideExtendedRange(t *testing.T) {
	args := []string{"--active", "--from", "2026-10-01", "--to", "2026-10-17", "--sample-date", "2026-10-16", "--days", "10"}
	parsed, err := parseKBSCrossSourceArgs(args)
	if err != nil {
		t.Fatalf("sample date in request interval rejected: %v", err)
	}
	if parsed.sampleDate != "2026-10-16" {
		t.Fatalf("sample date=%s", parsed.sampleDate)
	}
	base := []string{"--active", "--from", "2026-10-01", "--to", "2026-10-17"}
	for _, bad := range []string{"2026-09-30", "2026-10-18", "not-a-date"} {
		invalid := append(append([]string{}, base...), "--sample-date", bad, "--days", "10")
		if _, err := parseKBSCrossSourceArgs(invalid); err == nil {
			t.Errorf("out-of-range or malformed sample date %q accepted", bad)
		}
	}
}

func TestParseKBSCrossSourceArgsStrictMaximum(t *testing.T) {
	base := []string{"--active", "--from", "2026-09-01", "--to", "2026-09-30", "--days", "12"}
	for _, max := range []string{"0", "31", "-1"} {
		args := append(append([]string{}, base...), "--max-calls", max)
		if _, err := parseKBSCrossSourceArgs(args); err == nil {
			t.Errorf("--max-calls %s accepted", max)
		}
	}
	args := append(append([]string{}, base...), "--max-calls", "30")
	if _, err := parseKBSCrossSourceArgs(args); err != nil {
		t.Fatalf("maximum allowed cap rejected: %v", err)
	}
}

func TestParseKBSCrossSourceArgsRejectsBadDatesAndExtraSymbols(t *testing.T) {
	cases := [][]string{
		{"--active", "--from", "2026-02-30", "--to", "2026-03-01", "--days", "4"},
		{"--active", "--from", "2026-03-02", "--to", "2026-03-01", "--days", "4"},
		{"--active", "--from", "2026-03-01", "--to", "2026-03-02", "--days", "4", "FPT"},
	}
	for _, args := range cases {
		if _, err := parseKBSCrossSourceArgs(args); err == nil {
			t.Errorf("invalid arguments accepted: %v", args)
		}
	}
}

func TestCandidateSelectionInputValidatesCapAndDates(t *testing.T) {
	// Invalid input fails before dereferencing the database; this also verifies
	// that callers cannot request an unbounded candidate scan.
	if _, err := loadKBSCrossSourceCandidates(nil, nil, "2026-03-02", "2026-03-02", "2026-03-01", 1); err == nil {
		t.Fatal("reversed range accepted")
	}
	if _, err := loadKBSCrossSourceCandidates(nil, nil, "2026-03-01", "2026-03-01", "2026-03-02", 31); err == nil {
		t.Fatal("oversized candidate cap accepted")
	}
	if _, err := loadKBSCrossSourceCandidates(nil, nil, "2026-03-01", "2026-03-01", "2026-03-02", 1); err == nil {
		t.Fatal("nil DB accepted")
	}
}
