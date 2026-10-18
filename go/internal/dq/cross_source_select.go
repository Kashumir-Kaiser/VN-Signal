package dq

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
)

// CrossSourceSelection describes an offline sample materialized from already
// landed provider frames. It never makes a provider request.
type CrossSourceSelection struct {
	TradeDate string `json:"trade_date"`
	Selected  int    `json:"selected"`
}

type crossSourceCandidate struct {
	symbol                           string
	primarySource, secondarySource   string
	primaryClose, secondaryClose     float64
	primaryLanding, secondaryLanding int64
	primaryRow, secondaryRow         int
}

type crossSourceFrame struct {
	landingID int64
	evidence  sourceLandingEvidence
	close     float64
	row       int
	org       string
}

// SelectCrossSourceFromPostgres deterministically selects exactly 30 Tier A
// symbols with valid traded canonical bars and independently attributed VCI
// plus KBS or audited VNDIRECT landings. It replays/checksums each original
// frame before persisting its zero-based row index. No rows are written unless
// 30 candidates qualify.
func SelectCrossSourceFromPostgres(ctx context.Context, db *sql.DB, date time.Time) (CrossSourceSelection, error) {
	var out CrossSourceSelection
	if ctx == nil || db == nil || date.IsZero() {
		return out, errors.New("context, database and date are required")
	}
	day := date.Format("2006-01-02")
	if parsed, err := time.Parse("2006-01-02", day); err != nil ||
		!parsed.Equal(time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)) {
		return out, errors.New("date must be a date-only value")
	}
	out.TradeDate = day
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return out, err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(2108701,2603)`); err != nil {
		return out, err
	}
	var isSession bool
	if err = tx.QueryRowContext(ctx, `SELECT coalesce((SELECT is_session FROM core.calendar_overrides WHERE trade_date=$1::date),
		(SELECT is_session FROM core.calendar WHERE trade_date=$1::date),false)`, day).Scan(&isSession); err != nil {
		return out, err
	}
	if !isSession {
		return out, fmt.Errorf("cross-source selection requires a recorded trading session: %s", day)
	}

	rows, err := tx.QueryContext(ctx, `SELECT s.symbol
		FROM ops.dq_tier_a_symbols u
		JOIN core.symbols s USING(symbol_id)
		JOIN core.bars_daily b ON b.symbol_id=s.symbol_id AND b.trade_date=$1::date
		WHERE u.trade_date=$1::date AND b.is_traded AND b.v>0 AND b.v<'Infinity'::double precision
		  AND b.o>0 AND b.o<'Infinity'::double precision AND b.h>0 AND b.h<'Infinity'::double precision
		  AND b.l>0 AND b.l<'Infinity'::double precision AND b.c>0 AND b.c<'Infinity'::double precision
		  AND b.h>=b.l
		ORDER BY s.symbol`, day)
	if err != nil {
		return out, err
	}
	var symbols []string
	for rows.Next() {
		var symbol string
		if err = rows.Scan(&symbol); err != nil {
			rows.Close()
			return out, err
		}
		symbols = append(symbols, symbol)
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return out, err
	}
	if err = rows.Close(); err != nil {
		return out, err
	}

	candidates := make([]crossSourceCandidate, 0, RequiredCrossSourcePairs)
	for _, symbol := range symbols {
		frames, frameErr := loadCrossSourceFrames(ctx, tx, symbol, day)
		if frameErr != nil {
			return out, frameErr
		}
		var primary, secondary *crossSourceFrame
		for i := range frames {
			if !strings.EqualFold(frames[i].evidence.Source.String, "vci") {
				continue
			}
			for _, alternateSource := range []string{"kbs", "vndirect"} {
				for j := range frames {
					if strings.EqualFold(frames[j].evidence.Source.String, alternateSource) &&
						!strings.EqualFold(frames[i].org, frames[j].org) {
						primary, secondary = &frames[i], &frames[j]
						break
					}
				}
				if secondary != nil {
					break
				}
			}
			if primary != nil {
				break
			}
		}
		if primary == nil || secondary == nil {
			continue
		}
		candidates = append(candidates, crossSourceCandidate{
			symbol: symbol, primarySource: primary.evidence.Source.String, secondarySource: secondary.evidence.Source.String,
			primaryClose: primary.close, secondaryClose: secondary.close,
			primaryLanding: primary.landingID, secondaryLanding: secondary.landingID,
			primaryRow: primary.row, secondaryRow: secondary.row,
		})
		if len(candidates) == RequiredCrossSourcePairs {
			break
		}
	}
	if len(candidates) != RequiredCrossSourcePairs {
		return out, fmt.Errorf("cross-source selection found %d complete candidates; exactly %d required; no samples written", len(candidates), RequiredCrossSourcePairs)
	}

	if _, err = tx.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET selected_for_gate=false WHERE trade_date=$1::date`, day); err != nil {
		return out, err
	}
	for _, item := range candidates {
		_, err = tx.ExecContext(ctx, `INSERT INTO ops.dq_cross_source_samples
			(trade_date,symbol,primary_source,primary_close,secondary_source,secondary_close,selected_for_gate,
			 primary_landing_id,primary_source_row,secondary_landing_id,secondary_source_row)
			VALUES($1::date,$2,$3,$4,$5,$6,true,$7,$8,$9,$10)
			ON CONFLICT(trade_date,symbol) DO UPDATE SET
			 primary_source=EXCLUDED.primary_source,primary_close=EXCLUDED.primary_close,
			 secondary_source=EXCLUDED.secondary_source,secondary_close=EXCLUDED.secondary_close,
			 selected_for_gate=true,primary_landing_id=EXCLUDED.primary_landing_id,
			 primary_source_row=EXCLUDED.primary_source_row,secondary_landing_id=EXCLUDED.secondary_landing_id,
			 secondary_source_row=EXCLUDED.secondary_source_row`, day, item.symbol,
			item.primarySource, item.primaryClose, item.secondarySource, item.secondaryClose,
			item.primaryLanding, item.primaryRow, item.secondaryLanding, item.secondaryRow)
		if err != nil {
			return out, err
		}
	}
	if err = tx.Commit(); err != nil {
		return out, err
	}
	out.Selected = RequiredCrossSourcePairs
	return out, nil
}

// loadCrossSourceFrames reads landed frames newest-first per provider. Each
// payload is checked and replayed before it can supply a same-session row.
func loadCrossSourceFrames(ctx context.Context, tx *sql.Tx, symbol, day string) ([]crossSourceFrame, error) {
	rows, err := tx.QueryContext(ctx, `SELECT l.landing_id,l.route,l.source,l.symbol,l.payload_bytes,l.payload_sha256,
		c.route,c.source,c.symbol,j.date_from::text,j.date_to::text,c.request_url,c.outcome,c.response_sha256,c.http_status,c.row_count
		FROM raw.landings l
		LEFT JOIN ops.external_market_calls c ON c.landing_id=l.landing_id
		LEFT JOIN ops.ingest_jobs j ON j.job_id=c.job_id
		WHERE l.symbol=$1 AND l.source IN ('vci','kbs','vndirect') AND l.route='equity_ohlcv'
		AND l.payload_bytes IS NOT NULL ORDER BY l.source,l.landing_id DESC`, symbol)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var found []crossSourceFrame
	for rows.Next() {
		var landingID int64
		var evidence sourceLandingEvidence
		if err = rows.Scan(&landingID, &evidence.Route, &evidence.Source, &evidence.Symbol, &evidence.Payload, &evidence.SHA256,
			&evidence.Audit.Route, &evidence.Audit.Source, &evidence.Audit.Symbol, &evidence.Audit.DateFrom, &evidence.Audit.DateTo,
			&evidence.Audit.RequestURL, &evidence.Audit.Outcome, &evidence.Audit.ResponseSHA256, &evidence.Audit.HTTPStatus, &evidence.Audit.RowCount); err != nil {
			return nil, err
		}
		source := strings.ToLower(evidence.Source.String)
		rowIndex, closeValue, ok := 0, 0.0, false
		if source == "vndirect" && evidence.Audit.DateFrom.Valid && evidence.Audit.DateTo.Valid {
			rowIndex, closeValue, ok = locateVNDIRECTCrossSourceRow(evidence.Payload, symbol, evidence.Audit.DateFrom.String, evidence.Audit.DateTo.String, day)
		} else if source != "vndirect" {
			rowIndex, closeValue, ok = locateCrossSourceRow(evidence.Payload, day)
		}
		if !ok {
			continue
		}
		_, org, verifyErr := verifyCrossSourceLeg(symbol, day, source, int64(rowIndex), evidence, closeValue)
		if verifyErr != nil {
			continue
		}
		found = append(found, crossSourceFrame{landingID: landingID, evidence: evidence, close: closeValue, row: rowIndex, org: org})
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	return found, nil
}

// locateCrossSourceRow replays the original complete frame shape to identify
// the exact zero-based row for a date. The caller then invokes the full
// checksum, attribution and OHLCV validator before accepting the index.
func locateCrossSourceRow(payload []byte, day string) (int, float64, bool) {
	if len(payload) < 2 || len(payload) > maxCrossSourcePayloadBytes || !json.Valid(payload) {
		return 0, 0, false
	}
	var frame sourceFrameEvidence
	decoder := json.NewDecoder(bytes.NewReader(payload))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&frame) != nil || decoder.Decode(new(any)) != io.EOF || frame.Count < 1 || frame.Count != len(frame.Rows) {
		return 0, 0, false
	}
	dateColumn := "time"
	columns := map[string]bool{}
	for _, column := range frame.Columns {
		columns[column] = true
	}
	if !columns[dateColumn] {
		dateColumn = "date"
	}
	if !columns[dateColumn] || !columns["close"] {
		return 0, 0, false
	}
	found := -1
	var closeValue float64
	for index, row := range frame.Rows {
		rowDate, ok := evidenceDate(row[dateColumn])
		if !ok {
			return 0, 0, false
		}
		if rowDate == day {
			if found >= 0 {
				return 0, 0, false
			}
			value, valid := evidenceNumber(row["close"])
			if !valid {
				return 0, 0, false
			}
			found, closeValue = index, value
		}
	}
	return found, closeValue, found >= 0
}
