package main

import "testing"

func TestParseDQCrossSourceArgs(t *testing.T) {
	if _, err := parseDQCrossSourceArgs([]string{"--date", "2026-10-16"}); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{}, {"--date", "2026-02-30"}, {"--date", "2026-10-16", "EXTRA"},
	} {
		if _, err := parseDQCrossSourceArgs(args); err == nil {
			t.Fatalf("accepted invalid args %v", args)
		}
	}
}
