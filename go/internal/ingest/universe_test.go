package ingest

import (
	"errors"
	"testing"
	"time"
)

func TestUniverseSnapshotFreshnessAndCompleteness(t *testing.T) {
	now := time.Date(2026, 10, 16, 11, 0, 0, 0, time.UTC)
	cases := []struct {
		name, date                        string
		total, active, matched, exchanges int
		ok                                bool
	}{
		{"today", "2026-10-16", 1100, 1100, 1100, 3, true},
		{"last_week", "2026-10-09", 1100, 1100, 1100, 3, true},
		{"expired", "2026-10-08", 1100, 1100, 1100, 3, false},
		{"future", "2026-10-17", 1100, 1100, 1100, 3, false},
		{"too_small", "2026-10-16", 999, 999, 999, 3, false},
		{"one_missing", "2026-10-16", 1100, 1100, 1099, 3, false},
		{"active_mismatch", "2026-10-16", 1100, 1099, 1099, 3, false},
		{"no_exchange", "2026-10-16", 1100, 1100, 1100, 2, false},
		{"bad_date", "2026-99-99", 1100, 1100, 1100, 3, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateUniverse(tc.date, now, tc.total, tc.active, tc.matched, tc.exchanges)
			if (err == nil) != tc.ok {
				t.Fatalf("unexpected verification: %v", err)
			}
			if err != nil && !errors.Is(err, ErrUnverifiedUniverse) {
				t.Fatal(err)
			}
		})
	}
}
func TestNilDBFailsClosed(t *testing.T) {
	_, err := LoadVerifiedBackfillUniverse(nil, nil, time.Now(), "2018-10-01", "2026-10-16", "vci")
	if !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatal(err)
	}
}
func TestMarketDateCrossesUTC(t *testing.T) {
	at := time.Date(2026, 10, 16, 20, 0, 0, 0, time.UTC)
	if got := vnMarketDate(at).Format("2006-01-02"); got != "2026-10-17" {
		t.Fatal(got)
	}
}