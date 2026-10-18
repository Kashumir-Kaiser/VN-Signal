package dnse

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParseHistoryRetainsAuctionExtremaAndNullCells(t *testing.T) {
	timestamp := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC).Unix()
	body := []byte(fmt.Sprintf(`{"t":[%d,%d],"o":[10,null],"h":[9.5,11],"l":[9,10],"c":[9.2,10.5],"v":[100,0]}`, timestamp, timestamp+86400))
	rows, mismatch, err := ParseHistory(body, "2026-10-16", "2026-10-17")
	if err != nil {
		t.Fatal(err)
	}
	if mismatch || len(rows) != 2 {
		t.Fatalf("mismatch=%v rows=%d", mismatch, len(rows))
	}
	if rows[0].Date != "2026-10-16" || rows[0].Open == nil || *rows[0].Open != 10 || rows[0].High == nil || *rows[0].High != 9.5 {
		t.Fatalf("auction OHLC changed: %+v", rows[0])
	}
	if rows[1].Open != nil || rows[1].Volume == nil || *rows[1].Volume != 0 {
		t.Fatalf("null/zero fields not preserved: %+v", rows[1])
	}
}

func TestParseHistoryMarksUnequalArraysWithoutShifting(t *testing.T) {
	timestamp := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC).Unix()
	body := []byte(fmt.Sprintf(`{"t":[%d,%d],"o":[10],"h":[11,12],"l":[9,10],"c":[10.5,11],"v":[100,200]}`, timestamp, timestamp+86400))
	rows, mismatch, err := ParseHistory(body, "2026-10-16", "2026-10-17")
	if err != nil {
		t.Fatal(err)
	}
	if !mismatch || len(rows) != 2 || rows[1].Open != nil || rows[1].High == nil || *rows[1].High != 12 {
		t.Fatalf("unequal provider arrays were shifted or not marked: mismatch=%v rows=%+v", mismatch, rows)
	}
}

func TestParseHistoryAllowsMultipleTimestampedRowsOnOneLocalDate(t *testing.T) {
	first := time.Date(2022, 12, 27, 0, 0, 0, 0, time.UTC).Unix()
	second := time.Date(2022, 12, 27, 2, 0, 0, 0, time.UTC).Unix()
	body := []byte(fmt.Sprintf(`{"t":[%d,%d],"o":[10,10.2],"h":[10.2,10.5],"l":[9.8,10],"c":[10.2,10.4],"v":[100,200]}`, first, second))
	rows, mismatch, err := ParseHistory(body, "2022-12-27", "2022-12-27")
	if err != nil {
		t.Fatal(err)
	}
	if mismatch || len(rows) != 2 || rows[0].Date != rows[1].Date || rows[0].SourceRow != 0 || rows[1].SourceRow != 1 {
		t.Fatalf("same-date provider observations not preserved: mismatch=%v rows=%+v", mismatch, rows)
	}
}

func TestParseHistoryRejectsOutOfRangeAndNonIncreasingDates(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"outside", `{"t":[1792281600],"o":[1],"h":[1],"l":[1],"c":[1],"v":[1]}`},
		{"duplicate", `{"t":[1792108800,1792108800],"o":[1,1],"h":[1,1],"l":[1,1],"c":[1,1],"v":[1,1]}`},
		{"nonnumeric", `{"t":[1792108800],"o":["1"],"h":[1],"l":[1],"c":[1],"v":[1]}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, _, err := ParseHistory([]byte(test.body), "2026-10-16", "2026-10-17"); err == nil {
				t.Fatal("expected invalid provider frame to fail")
			}
		})
	}
}

func TestFetchHistoryAuditsTheRequestURLAndBounds(t *testing.T) {
	timestamp := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC).Unix()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("symbol") != "VCB" || r.URL.Query().Get("resolution") != "1D" || r.URL.Query().Get("from") == "" || r.URL.Query().Get("to") == "" {
			t.Errorf("unexpected provider query: %s", r.URL.RawQuery)
		}
		_, _ = fmt.Fprintf(w, `{"t":[%d],"o":[10],"h":[11],"l":[9],"c":[10],"v":[100]}`, timestamp)
	}))
	defer server.Close()
	client := &Client{HTTP: server.Client(), BaseURL: server.URL}
	history, err := client.FetchHistory(context.Background(), "vcb", "2026-10-16", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if history.HTTPStatus != http.StatusOK || len(history.Raw) == 0 || len(history.Rows) != 1 || !strings.Contains(history.RequestURL, "symbol=VCB") {
		t.Fatalf("incomplete fetched evidence: %+v", history)
	}
}
