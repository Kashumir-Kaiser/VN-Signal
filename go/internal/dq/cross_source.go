package dq

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/vndirect"
)

const maxCrossSourcePayloadBytes = 10 * 1024 * 1024

type sourceFrameEvidence struct {
	Columns    []string                     `json:"columns"`
	Count      int                          `json:"count"`
	Rows       []map[string]json.RawMessage `json:"rows"`
	Attributes map[string]json.RawMessage   `json:"attributes"`
}

type sourceLandingEvidence struct {
	Route, Source, Symbol sql.NullString
	Payload               []byte
	SHA256                sql.NullString
	Audit                 sourceAuditEvidence
}

type sourceAuditEvidence struct {
	Route, Source, Symbol, DateFrom, DateTo, RequestURL, Outcome, ResponseSHA256 sql.NullString
	HTTPStatus, RowCount                                                         sql.NullInt64
}

func appendCrossSourceEvidence(ctx context.Context, tx *sql.Tx, day string, in *GateInput, report *GateReport) error {
	var selected, tierSelected int
	err := tx.QueryRowContext(ctx, `SELECT count(*)::int,count(u.symbol_id)::int
		FROM ops.dq_cross_source_samples x
		LEFT JOIN core.symbols s ON s.symbol=x.symbol
		LEFT JOIN ops.dq_tier_a_symbols u ON u.symbol_id=s.symbol_id AND u.trade_date=x.trade_date
		WHERE x.trade_date=$1 AND x.selected_for_gate`, day).Scan(&selected, &tierSelected)
	if err != nil {
		return err
	}
	if selected != RequiredCrossSourcePairs || tierSelected != RequiredCrossSourcePairs {
		report.Blocking = append(report.Blocking, fmt.Sprintf(
			"cross-source sample unavailable: have %d explicitly selected rows (%d Tier A), require exactly %d Tier A pairs",
			selected, tierSelected, RequiredCrossSourcePairs))
		return nil
	}

	rows, err := tx.QueryContext(ctx, `SELECT x.symbol,x.primary_source,x.primary_close,x.primary_landing_id,x.primary_source_row,
		x.secondary_source,x.secondary_close,x.secondary_landing_id,x.secondary_source_row,
		p.route,p.source,p.symbol,p.payload_bytes,p.payload_sha256,
		pc.route,pc.source,pc.symbol,pj.date_from::text,pj.date_to::text,pc.request_url,pc.outcome,pc.response_sha256,pc.http_status,pc.row_count,
		q.route,q.source,q.symbol,q.payload_bytes,q.payload_sha256,
		qc.route,qc.source,qc.symbol,qj.date_from::text,qj.date_to::text,qc.request_url,qc.outcome,qc.response_sha256,qc.http_status,qc.row_count
		FROM ops.dq_cross_source_samples x
		JOIN core.symbols s ON s.symbol=x.symbol
		JOIN ops.dq_tier_a_symbols u ON u.symbol_id=s.symbol_id AND u.trade_date=x.trade_date
		LEFT JOIN raw.landings p ON p.landing_id=x.primary_landing_id
		LEFT JOIN raw.landings q ON q.landing_id=x.secondary_landing_id
		LEFT JOIN ops.external_market_calls pc ON pc.landing_id=p.landing_id
		LEFT JOIN ops.ingest_jobs pj ON pj.job_id=pc.job_id
		LEFT JOIN ops.external_market_calls qc ON qc.landing_id=q.landing_id
		LEFT JOIN ops.ingest_jobs qj ON qj.job_id=qc.job_id
		WHERE x.trade_date=$1 AND x.selected_for_gate ORDER BY x.symbol`, day)
	if err != nil {
		return err
	}
	defer rows.Close()

	valid := 0
	for rows.Next() {
		var symbol, primarySource, secondarySource string
		var primaryClose, secondaryClose float64
		var primaryLandingID, primarySourceRow, secondaryLandingID, secondarySourceRow sql.NullInt64
		var primary, secondary sourceLandingEvidence
		if err = rows.Scan(&symbol, &primarySource, &primaryClose, &primaryLandingID, &primarySourceRow,
			&secondarySource, &secondaryClose, &secondaryLandingID, &secondarySourceRow,
			&primary.Route, &primary.Source, &primary.Symbol, &primary.Payload, &primary.SHA256,
			&primary.Audit.Route, &primary.Audit.Source, &primary.Audit.Symbol, &primary.Audit.DateFrom, &primary.Audit.DateTo,
			&primary.Audit.RequestURL, &primary.Audit.Outcome, &primary.Audit.ResponseSHA256, &primary.Audit.HTTPStatus, &primary.Audit.RowCount,
			&secondary.Route, &secondary.Source, &secondary.Symbol, &secondary.Payload, &secondary.SHA256,
			&secondary.Audit.Route, &secondary.Audit.Source, &secondary.Audit.Symbol, &secondary.Audit.DateFrom, &secondary.Audit.DateTo,
			&secondary.Audit.RequestURL, &secondary.Audit.Outcome, &secondary.Audit.ResponseSHA256, &secondary.Audit.HTTPStatus, &secondary.Audit.RowCount); err != nil {
			return err
		}
		if !primaryLandingID.Valid || !primarySourceRow.Valid || !secondaryLandingID.Valid || !secondarySourceRow.Valid {
			report.Blocking = append(report.Blocking, "cross-source evidence lacks verified source-landing and source-row lineage for "+symbol)
			continue
		}
		primaryValue, primaryOrg, primaryErr := verifyCrossSourceLeg(symbol, day, primarySource, primarySourceRow.Int64, primary, primaryClose)
		secondaryValue, secondaryOrg, secondaryErr := verifyCrossSourceLeg(symbol, day, secondarySource, secondarySourceRow.Int64, secondary, secondaryClose)
		if primaryErr != nil || secondaryErr != nil {
			reason := "cross-source evidence failed source replay for " + symbol
			if primaryErr != nil {
				reason += " (primary: " + primaryErr.Error() + ")"
			}
			if secondaryErr != nil {
				reason += " (secondary: " + secondaryErr.Error() + ")"
			}
			report.Blocking = append(report.Blocking, reason)
			continue
		}
		if strings.EqualFold(primaryOrg, secondaryOrg) {
			report.Blocking = append(report.Blocking, "cross-source providers are not independently identified for "+symbol)
			continue
		}
		in.CrossSources = append(in.CrossSources, SourceClose{Symbol: symbol, Date: day, Primary: primaryValue, Secondary: secondaryValue})
		valid++
	}
	if err = rows.Err(); err != nil {
		return err
	}
	if valid != RequiredCrossSourcePairs {
		report.Blocking = append(report.Blocking, fmt.Sprintf("cross-source evidence replayed for %d of exactly %d required Tier A pairs", valid, RequiredCrossSourcePairs))
	}
	return nil
}

func verifyCrossSourceLeg(symbol, day, expectedSource string, sourceRow int64, landing sourceLandingEvidence, expectedClose float64) (float64, string, error) {
	if !landing.Route.Valid || landing.Route.String != "equity_ohlcv" || !landing.Source.Valid || !landing.Symbol.Valid ||
		!strings.EqualFold(landing.Source.String, expectedSource) || !strings.EqualFold(landing.Symbol.String, symbol) {
		return 0, "", errors.New("landing route, source, or symbol mismatch")
	}
	if sourceRow < 0 || len(landing.Payload) < 2 || len(landing.Payload) > maxCrossSourcePayloadBytes || !landing.SHA256.Valid {
		return 0, "", errors.New("source landing bytes or row index unavailable")
	}
	digest := sha256.Sum256(landing.Payload)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), landing.SHA256.String) || !json.Valid(landing.Payload) {
		return 0, "", errors.New("source landing checksum or JSON invalid")
	}
	if strings.EqualFold(expectedSource, "vndirect") {
		return verifyVNDIRECTCrossSourceLeg(symbol, day, sourceRow, landing, expectedClose)
	}
	var frame sourceFrameEvidence
	decoder := json.NewDecoder(bytes.NewReader(landing.Payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&frame); err != nil {
		return 0, "", errors.New("source frame shape invalid")
	}
	if err := decoder.Decode(new(any)); err != io.EOF || frame.Count < 1 || frame.Count != len(frame.Rows) || sourceRow >= int64(frame.Count) {
		return 0, "", errors.New("source frame row count or trailing data invalid")
	}
	columns := make(map[string]bool, len(frame.Columns))
	for _, column := range frame.Columns {
		if columns[column] {
			return 0, "", errors.New("source frame has duplicate columns")
		}
		columns[column] = true
	}
	dateColumn := "time"
	if !columns[dateColumn] {
		dateColumn = "date"
	}
	for _, column := range []string{dateColumn, "open", "high", "low", "close", "volume"} {
		if !columns[column] {
			return 0, "", errors.New("source frame is missing an OHLCV column")
		}
	}
	providerSource := evidenceString(frame.Attributes["source"])
	organisation := evidenceString(frame.Attributes["organisation"])
	if providerSource == "" || !strings.EqualFold(providerSource, expectedSource) || organisation == "" {
		return 0, "", errors.New("provider source or organisation attribution unavailable")
	}
	if providerRoute := evidenceString(frame.Attributes["route"]); providerRoute != "" &&
		!strings.EqualFold(providerRoute, "equity_ohlcv") && !strings.EqualFold(providerRoute, "market.equity.ohlcv") {
		return 0, "", errors.New("provider route attribution mismatch")
	}

	previous := ""
	for i, row := range frame.Rows {
		date, ok := evidenceDate(row[dateColumn])
		if !ok || (previous != "" && date <= previous) {
			return 0, "", fmt.Errorf("source row %d has invalid or unordered session date", i)
		}
		previous = date
	}
	row := frame.Rows[int(sourceRow)]
	date, _ := evidenceDate(row[dateColumn])
	if date != day {
		return 0, "", errors.New("lineaged source row is not the sample session")
	}
	open, openOK := evidenceNumber(row["open"])
	high, highOK := evidenceNumber(row["high"])
	low, lowOK := evidenceNumber(row["low"])
	closeValue, closeOK := evidenceNumber(row["close"])
	volume, volumeOK := evidenceNumber(row["volume"])
	if !openOK || !highOK || !lowOK || !closeOK || !volumeOK || volume <= 0 {
		return 0, "", errors.New("lineaged source row is not a valid traded OHLCV bar")
	}
	bar := Bar{Symbol: symbol, Date: day, Open: open, High: high, Low: low, Close: closeValue, Volume: volume}
	if err := Validate([]Bar{bar}); err != nil {
		return 0, "", errors.New("lineaged source OHLCV validation failed")
	}
	if !finitePositive(expectedClose) || !nearlyEqual(closeValue, expectedClose) {
		return 0, "", errors.New("stored sample close differs from its source row")
	}
	return closeValue, organisation, nil
}

func verifyVNDIRECTCrossSourceLeg(symbol, day string, sourceRow int64, landing sourceLandingEvidence, expectedClose float64) (float64, string, error) {
	audit := landing.Audit
	if !audit.Route.Valid || audit.Route.String != "equity_ohlcv" || !audit.Source.Valid || !strings.EqualFold(audit.Source.String, "vndirect") ||
		!audit.Symbol.Valid || !strings.EqualFold(audit.Symbol.String, symbol) || !audit.DateFrom.Valid || !audit.DateTo.Valid ||
		!audit.RequestURL.Valid || !audit.Outcome.Valid || audit.Outcome.String != "SUCCEEDED" ||
		!audit.ResponseSHA256.Valid || !strings.EqualFold(audit.ResponseSHA256.String, landing.SHA256.String) ||
		!audit.HTTPStatus.Valid || audit.HTTPStatus.Int64 != 200 || !audit.RowCount.Valid || audit.RowCount.Int64 < 1 {
		return 0, "", errors.New("VNDIRECT landing lacks a matching successful audited request")
	}
	if audit.DateFrom.String > day || audit.DateTo.String < day || audit.DateFrom.String > audit.DateTo.String {
		return 0, "", errors.New("VNDIRECT audited request does not cover the sample session")
	}
	requestURL, err := url.Parse(audit.RequestURL.String)
	if err != nil || requestURL.Scheme != "https" || requestURL.Host != "api-finfo.vndirect.com.vn" ||
		requestURL.Path != "/v4/stock_prices" || requestURL.User != nil || requestURL.Fragment != "" {
		return 0, "", errors.New("VNDIRECT audited endpoint attribution is invalid")
	}
	query := requestURL.Query()
	if query.Get("q") != fmt.Sprintf("code:%s~date:gte:%s~date:lte:%s", strings.ToUpper(symbol), audit.DateFrom.String, audit.DateTo.String) ||
		query.Get("sort") != "date:asc" || query.Get("size") != "5000" || query.Get("page") != "1" {
		return 0, "", errors.New("VNDIRECT audited request filters do not match its job")
	}
	bars, err := vndirect.ParseHistory(landing.Payload, symbol, audit.DateFrom.String, audit.DateTo.String)
	if err != nil || int64(len(bars)) != audit.RowCount.Int64 || sourceRow < 0 || sourceRow >= int64(len(bars)) {
		return 0, "", errors.New("VNDIRECT source frame or audited row count is invalid")
	}
	row := bars[int(sourceRow)]
	if row.SourceRow != int(sourceRow) || row.TickerMismatch || !strings.EqualFold(row.ProviderCode, symbol) || row.Date != day || row.DuplicateDate {
		return 0, "", errors.New("lineaged VNDIRECT row is not a unique exact-ticker session bar")
	}
	if row.Open == nil || row.High == nil || row.Low == nil || row.Close == nil || row.Volume == nil || *row.Volume <= 0 {
		return 0, "", errors.New("lineaged VNDIRECT row is not a traded OHLCV bar")
	}
	bar := Bar{Symbol: symbol, Date: day, Open: *row.Open, High: *row.High, Low: *row.Low, Close: *row.Close, Volume: *row.Volume}
	if err = Validate([]Bar{bar}); err != nil {
		return 0, "", errors.New("lineaged VNDIRECT OHLCV validation failed")
	}
	if !finitePositive(expectedClose) || !nearlyEqual(*row.Close, expectedClose) {
		return 0, "", errors.New("stored sample close differs from its VNDIRECT source row")
	}
	return *row.Close, "VNDIRECT Securities (api-finfo.vndirect.com.vn)", nil
}

func locateVNDIRECTCrossSourceRow(payload []byte, symbol, start, end, day string) (int, float64, bool) {
	bars, err := vndirect.ParseHistory(payload, symbol, start, end)
	if err != nil {
		return 0, 0, false
	}
	found := -1
	var closeValue float64
	for _, row := range bars {
		if row.TickerMismatch || row.Date != day {
			continue
		}
		if found >= 0 || row.DuplicateDate || row.Open == nil || row.High == nil || row.Low == nil || row.Close == nil || row.Volume == nil || *row.Volume <= 0 {
			return 0, 0, false
		}
		bar := Bar{Symbol: symbol, Date: day, Open: *row.Open, High: *row.High, Low: *row.Low, Close: *row.Close, Volume: *row.Volume}
		if Validate([]Bar{bar}) != nil {
			return 0, 0, false
		}
		found, closeValue = row.SourceRow, *row.Close
	}
	return found, closeValue, found >= 0
}

func evidenceString(raw json.RawMessage) string {
	var value string
	if len(raw) == 0 || json.Unmarshal(raw, &value) != nil {
		return ""
	}
	return strings.TrimSpace(value)
}

func evidenceDate(raw json.RawMessage) (string, bool) {
	var value string
	if json.Unmarshal(raw, &value) != nil {
		return "", false
	}
	var parsed time.Time
	var err error
	switch {
	case len(value) == len("2006-01-02"):
		parsed, err = time.Parse("2006-01-02", value)
	case len(value) >= 19 && value[10] == 'T':
		for _, format := range []string{time.RFC3339Nano, "2006-01-02T15:04:05", "2006-01-02T15:04:05.000000"} {
			parsed, err = time.Parse(format, value)
			if err == nil {
				break
			}
		}
	default:
		return "", false
	}
	if err != nil {
		return "", false
	}
	return parsed.Format("2006-01-02"), true
}

func evidenceNumber(raw json.RawMessage) (float64, bool) {
	if len(raw) == 0 || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return 0, false
	}
	var number json.Number
	if json.Unmarshal(raw, &number) == nil {
		value, err := number.Float64()
		return value, err == nil && !math.IsNaN(value) && !math.IsInf(value, 0)
	}
	var text string
	if json.Unmarshal(raw, &text) != nil || strings.TrimSpace(text) == "" {
		return 0, false
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(text), 64)
	return value, err == nil && !math.IsNaN(value) && !math.IsInf(value, 0)
}

func finitePositive(value float64) bool {
	return value > 0 && !math.IsNaN(value) && !math.IsInf(value, 0)
}

func nearlyEqual(a, b float64) bool {
	scale := math.Max(1, math.Max(math.Abs(a), math.Abs(b)))
	return math.Abs(a-b) <= scale*1e-12
}
