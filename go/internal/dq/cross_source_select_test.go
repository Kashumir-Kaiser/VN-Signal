package dq

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"testing"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/vndirect"
)

func TestLocateCrossSourceRowReplaysFullFrameZeroBased(t *testing.T) {
	payload := []byte(`{"columns":["time","open","high","low","close","volume"],"count":3,"rows":[{"time":"2026-10-14","open":10,"high":11,"low":9,"close":10,"volume":20},{"time":"2026-10-15","open":12,"high":13,"low":11,"close":12.5,"volume":30},{"time":"2026-10-16","open":14,"high":15,"low":13,"close":14.5,"volume":40}],"attributes":{"source":"vci","organisation":"Provider A","route":"market.equity.ohlcv"}}`)
	row, closeValue, ok := locateCrossSourceRow(payload, "2026-10-15")
	if !ok || row != 1 || closeValue != 12.5 {
		t.Fatalf("row=%d close=%v ok=%v", row, closeValue, ok)
	}
	digest := sha256.Sum256(payload)
	landing := sourceLandingEvidence{
		Route: stringNull("equity_ohlcv"), Source: stringNull("vci"), Symbol: stringNull("FPT"),
		Payload: payload, SHA256: stringNull(hex.EncodeToString(digest[:])),
	}
	value, org, err := verifyCrossSourceLeg("FPT", "2026-10-15", "vci", int64(row), landing, closeValue)
	if err != nil || value != closeValue || org != "Provider A" {
		t.Fatalf("replayed evidence value=%v org=%q err=%v", value, org, err)
	}
}

func TestLocateCrossSourceRowRejectsAmbiguousOrMalformedFrames(t *testing.T) {
	base := `{"columns":["date","close"],"count":%d,"rows":[%s],"attributes":{}}`
	duplicate := fmt.Sprintf(base, 2, `{"date":"2026-10-15","close":10},{"date":"2026-10-15","close":11}`)
	if row, _, ok := locateCrossSourceRow([]byte(duplicate), "2026-10-15"); ok {
		t.Fatalf("duplicate session accepted at row %d", row)
	}
	countMismatch := []byte(`{"columns":["date","close"],"count":2,"rows":[{"date":"2026-10-15","close":10}],"attributes":{}}`)
	if _, _, ok := locateCrossSourceRow(countMismatch, "2026-10-15"); ok {
		t.Fatal("count-mismatched frame accepted")
	}
	if _, _, ok := locateCrossSourceRow([]byte(`{} {}`), "2026-10-15"); ok {
		t.Fatal("trailing JSON accepted")
	}
}

func TestLocateVNDIRECTRowRequiresAuditedExactTickerAndAcceptsAuctionOHLC(t *testing.T) {
	payload := []byte(`{"currentPage":1,"size":5000,"totalElements":2,"totalPages":1,"data":[{"code":"FPT","date":"2026-10-15","open":13.5,"high":14,"low":13,"close":13.8,"nmVolume":30,"ptVolume":0},{"code":"FPT","date":"2026-10-16","open":14,"high":15,"low":15,"close":15,"nmVolume":40,"ptVolume":0}]}`)
	row, closeValue, ok := locateVNDIRECTCrossSourceRow(payload, "FPT", "2026-10-15", "2026-10-16", "2026-10-16")
	if !ok || row != 1 || closeValue != 15 {
		t.Fatalf("VNDIRECT row=%d close=%v ok=%v", row, closeValue, ok)
	}
	digest := sha256.Sum256(payload)
	requestURL, err := vndirect.NewClient().RequestURL("FPT", "2026-10-15", "2026-10-16")
	if err != nil {
		t.Fatal(err)
	}
	landing := sourceLandingEvidence{
		Route: stringNull("equity_ohlcv"), Source: stringNull("vndirect"), Symbol: stringNull("FPT"),
		Payload: payload, SHA256: stringNull(hex.EncodeToString(digest[:])),
		Audit: sourceAuditEvidence{
			Route: stringNull("equity_ohlcv"), Source: stringNull("vndirect"), Symbol: stringNull("FPT"),
			DateFrom: stringNull("2026-10-15"), DateTo: stringNull("2026-10-16"), RequestURL: stringNull(requestURL),
			Outcome: stringNull("SUCCEEDED"), ResponseSHA256: stringNull(hex.EncodeToString(digest[:])),
			HTTPStatus: sql.NullInt64{Int64: 200, Valid: true}, RowCount: sql.NullInt64{Int64: 2, Valid: true},
		},
	}
	value, org, err := verifyCrossSourceLeg("FPT", "2026-10-16", "vndirect", int64(row), landing, closeValue)
	if err != nil || value != 15 || org == "" {
		t.Fatalf("replayed VNDIRECT value=%v org=%q err=%v", value, org, err)
	}

	landing.Audit.RequestURL = stringNull("https://example.com/v4/stock_prices")
	if _, _, err = verifyCrossSourceLeg("FPT", "2026-10-16", "vndirect", int64(row), landing, closeValue); err == nil {
		t.Fatal("unattributed VNDIRECT endpoint accepted")
	}
}

func TestLocateVNDIRECTRowRejectsDuplicateTickerDate(t *testing.T) {
	payload := []byte(`{"currentPage":1,"size":5000,"totalElements":2,"totalPages":1,"data":[{"code":"FPT","date":"2026-10-16","open":14,"high":15,"low":15,"close":15,"nmVolume":40},{"code":"FPT","date":"2026-10-16","open":14,"high":15,"low":15,"close":15,"nmVolume":40}]}`)
	if row, _, ok := locateVNDIRECTCrossSourceRow(payload, "FPT", "2026-10-16", "2026-10-16", "2026-10-16"); ok {
		t.Fatalf("duplicate daily ticker rows accepted at row %d", row)
	}
}

func stringNull(value string) sql.NullString {
	return sql.NullString{String: value, Valid: true}
}
