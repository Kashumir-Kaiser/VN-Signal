package vndirect

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseHistoryPreservesNormalAndPutThroughVolumeSeparately(t *testing.T) {
	body := []byte(`{"currentPage":1,"size":5000,"totalElements":1,"totalPages":1,"data":[{"code":"UTT","date":"2026-10-16","open":9.2,"high":9.2,"low":9.2,"close":9.2,"nmVolume":0,"ptVolume":1200}]}`)
	rows, err := ParseHistory(body, "UTT", "2026-10-16", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].Volume == nil || *rows[0].Volume != 0 || rows[0].PTVolume == nil || *rows[0].PTVolume != 1200 {
		t.Fatalf("volume components were not preserved: %+v", rows)
	}
}

func TestParseHistoryRejectsTruncationAndOutOfRangeFrames(t *testing.T) {
	tests := []struct {
		name string
		body string
	}{
		{"truncated", `{"currentPage":1,"size":1,"totalElements":3,"totalPages":1,"data":[{"code":"VCB","date":"2026-10-16","open":1,"high":1,"low":1,"close":1,"nmVolume":1}]}`},
		{"multiple pages", `{"currentPage":1,"size":5000,"totalElements":5001,"totalPages":2,"data":[{"code":"VCB","date":"2026-10-16","open":1,"high":1,"low":1,"close":1,"nmVolume":1}]}`},
		{"out of range", `{"data":[{"code":"VCB","date":"2026-10-17","open":1,"high":1,"low":1,"close":1,"nmVolume":1}]}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, err := ParseHistory([]byte(test.body), "VCB", "2026-10-16", "2026-10-16"); err == nil {
				t.Fatal("expected invalid VNDIRECT frame to fail")
			}
		})
	}
}

func TestParseHistoryMarksUnexpectedProviderTicker(t *testing.T) {
	payload := []byte(`{"data":[{"code":"BCF","date":"2021-01-29","open":10,"high":11,"low":9,"close":10,"nmVolume":100},{"code":"VCBF-BCF","date":"2021-01-31","open":0,"high":0,"low":0,"close":20,"nmVolume":0}]}`)
	rows, err := ParseHistory(payload, "BCF", "2018-10-01", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 || rows[0].TickerMismatch || !rows[1].TickerMismatch || rows[1].ProviderCode != "VCBF-BCF" {
		t.Fatalf("unexpected provider ticker classification: %+v", rows)
	}
}

func TestParseHistoryDoesNotTreatTickerCollisionAsRequestedTickerDuplicate(t *testing.T) {
	payload := []byte(`{"data":[{"code":"BCF","date":"2021-03-31","open":40.7,"high":40.7,"low":40.7,"close":40.7,"nmVolume":100},{"code":"VCBF-BCF","date":"2021-03-31","open":0,"high":0,"low":0,"close":23.6,"nmVolume":0},{"code":"BCF","date":"2021-04-01","open":40.7,"high":40.7,"low":40.7,"close":40.7,"nmVolume":100}]}`)
	rows, err := ParseHistory(payload, "BCF", "2018-10-01", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 || rows[0].TickerMismatch || rows[0].DuplicateDate || !rows[1].TickerMismatch || rows[1].DuplicateDate || rows[2].TickerMismatch || rows[2].DuplicateDate {
		t.Fatalf("unexpected ticker-collision handling: %+v", rows)
	}
}

func TestParseHistoryMarksDuplicateRowsForRequestedTicker(t *testing.T) {
	payload := []byte(`{"data":[{"code":"VCB","date":"2026-10-16","open":1,"high":1,"low":1,"close":1,"nmVolume":1},{"code":"VCB","date":"2026-10-16","open":1,"high":1,"low":1,"close":1,"nmVolume":1}]}`)
	rows, err := ParseHistory(payload, "VCB", "2018-10-01", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 2 || !rows[0].DuplicateDate || !rows[1].DuplicateDate {
		t.Fatalf("requested ticker duplicates were not marked: %+v", rows)
	}
}

func TestFetchHistoryBuildsAuditableURLAndPreservesResponse(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		if q.Get("q") != "code:VCB~date:gte:2026-10-16~date:lte:2026-10-16" || q.Get("size") != "5000" || q.Get("page") != "1" {
			t.Errorf("unexpected VNDIRECT query: %s", r.URL.RawQuery)
		}
		_, _ = fmt.Fprint(w, `{"currentPage":1,"size":5000,"totalElements":1,"totalPages":1,"data":[{"code":"VCB","date":"2026-10-16","open":56.9,"high":57.3,"low":56.6,"close":56.9,"nmVolume":2388700,"ptVolume":49000}]}`)
	}))
	defer server.Close()
	client := &Client{HTTP: server.Client(), BaseURL: server.URL}
	history, err := client.FetchHistory(context.Background(), "vcb", "2026-10-16", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	if history.HTTPStatus != http.StatusOK || len(history.Raw) == 0 || len(history.Rows) != 1 || history.RequestURL == "" {
		t.Fatalf("incomplete fetched evidence: %+v", history)
	}
}
