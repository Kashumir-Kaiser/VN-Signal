package ingest

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"reflect"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/dnse"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/vndirect"
)

type ExternalMarketCall struct {
	CallID  int64
	JobID   int64
	Key     string
	Attempt int
	Symbol  string
	Source  string
	Start   string
	End     string
}

type ExternalMarketSummary struct {
	LandingID      int64
	Rows           int
	Traded         int
	NoTrade        int
	Invalid        int
	DuplicateDates int
	State          string
}

// BeginExternalMarketCall durably starts an explicitly authorized, non-vnstock
// provider request. It does not reserve vnstock quota. The request and each
// outcome are kept in ops.external_market_calls, while bars remain in a
// source-keyed table separate from canonical VCI bars.
func (p *PostgresStore) BeginExternalMarketCall(ctx context.Context, source, symbol, start, end, requestURL string, retryFailed bool) (ExternalMarketCall, error) {
	var out ExternalMarketCall
	source = strings.ToLower(strings.TrimSpace(source))
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if p == nil || p.DB == nil || !validExternalSource(source) || !validAlternateSymbol(symbol) ||
		!validISODate(start) || !validISODate(end) || start > end || strings.TrimSpace(requestURL) == "" || len(requestURL) > 2048 {
		return out, errors.New("invalid external market request")
	}
	key := fmt.Sprintf("equity_ohlcv:%s:%s:%s:%s", symbol, source, start, end)
	// Explicit row locks and unique keys serialize per-symbol state transitions;
	// Read Committed avoids unrelated symbols conflicting under concurrent feeds.
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return out, err
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(ctx, `INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
		VALUES($1,'equity_ohlcv',$2,$3,$4::date,$5::date) ON CONFLICT(idempotency_key) DO NOTHING`, key, symbol, source, start, end); err != nil {
		return out, err
	}
	var state, storedRoute, storedSource, storedSymbol, storedStart, storedEnd string
	var jobID int64
	var attempts int
	var updated time.Time
	if err = tx.QueryRowContext(ctx, `SELECT job_id,state,route,source,symbol,date_from::text,date_to::text,attempts,updated_at
		FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, key).Scan(&jobID, &state, &storedRoute, &storedSource, &storedSymbol, &storedStart, &storedEnd, &attempts, &updated); err != nil {
		return out, err
	}
	if storedRoute != "equity_ohlcv" || storedSource != source || storedSymbol != symbol || storedStart != start || storedEnd != end {
		return out, errors.New("external market idempotency key collision")
	}
	if state == "COMPLETED" {
		return out, ErrJobCompleted
	}
	if state == "PARTIAL" && !retryFailed {
		return out, ErrJobCompleted
	}
	if state == "BLOCKED" && !retryFailed {
		return out, ErrJobBlocked
	}
	if (state == "RUNNING" || state == "RESERVED") && p.clock().Sub(updated) < 15*time.Minute {
		return out, ErrInFlight
	}
	if attempts > 0 && !retryFailed {
		return out, errors.New("external market retry requires --retry-failed")
	}
	attempt := attempts + 1
	if state == "RUNNING" || state == "RESERVED" {
		_, err = tx.ExecContext(ctx, `UPDATE ops.external_market_calls SET outcome='FAILED',error_type='AbandonedAttempt',finished_at=now()
			WHERE job_id=$1 AND attempt_no=$2 AND outcome='STARTED'`, jobID, attempts)
		if err != nil {
			return out, err
		}
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='RUNNING',attempts=$2,last_error_type=NULL,updated_at=now()
		WHERE job_id=$1`, jobID, attempt)
	if err != nil {
		return out, err
	}
	if n, e := res.RowsAffected(); e != nil || n != 1 {
		return out, errors.New("external market job start transition failed")
	}
	var callID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO ops.external_market_calls(job_id,attempt_no,source,route,symbol,request_url,outcome)
		VALUES($1,$2,$3,'equity_ohlcv',$4,$5,'STARTED') RETURNING call_id`, jobID, attempt, source, symbol, requestURL).Scan(&callID)
	if err != nil {
		return out, err
	}
	if err = tx.Commit(); err != nil {
		return out, err
	}
	return ExternalMarketCall{CallID: callID, JobID: jobID, Key: key, Attempt: attempt, Symbol: symbol, Source: source, Start: start, End: end}, nil
}

func (p *PostgresStore) FailExternalMarketCall(ctx context.Context, call ExternalMarketCall, status int, response []byte, errorType string, rateLimited bool) error {
	if p == nil || p.DB == nil || call.CallID < 1 || call.JobID < 1 || !validExternalSource(call.Source) || len(response) > 10*1024*1024 {
		return errors.New("invalid external market failure")
	}
	if errorType == "" {
		errorType = "ProviderFailure"
	}
	if len(errorType) > 64 {
		errorType = errorType[:64]
	}
	var digest any
	if len(response) > 0 {
		sum := sha256.Sum256(response)
		digest = hex.EncodeToString(sum[:])
	}
	outcome := "FAILED"
	if rateLimited {
		outcome = "RATE_LIMITED"
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var quarantinedLanding any
	if status >= 200 && status < 300 && len(response) > 0 && json.Valid(response) {
		quarantineIngestID, uuidErr := newUUID()
		if uuidErr != nil {
			return uuidErr
		}
		sum := sha256.Sum256(response)
		sha := hex.EncodeToString(sum[:])
		var landingID int64
		err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
			VALUES($1::uuid,$2,'equity_ohlcv_quarantine',now(),$3,$4::jsonb,$5,$6) RETURNING landing_id`,
			quarantineIngestID, call.Source, call.Symbol, string(response), sha, response).Scan(&landingID)
		if err != nil {
			return err
		}
		quarantinedLanding = landingID
	}
	var current string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.external_market_calls WHERE call_id=$1 AND job_id=$2 FOR UPDATE`, call.CallID, call.JobID).Scan(&current); err != nil {
		return err
	}
	if current != "STARTED" {
		return errors.New("external market call is not awaiting an outcome")
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.external_market_calls SET outcome=$2,error_type=$3,http_status=NULLIF($4,0),response_sha256=$5,landing_id=COALESCE($6,landing_id),finished_at=now()
		WHERE call_id=$1`, call.CallID, outcome, errorType, status, digest, quarantinedLanding); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='BLOCKED',last_error_type=$2,updated_at=now()
		WHERE job_id=$1 AND state='RUNNING'`, call.JobID, errorType)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (p *PostgresStore) CommitDNSEHistory(ctx context.Context, call ExternalMarketCall, fetchedAt time.Time, history dnse.History) (ExternalMarketSummary, error) {
	var summary ExternalMarketSummary
	if p == nil || p.DB == nil || call.CallID < 1 || call.Source != "dnse" || fetchedAt.IsZero() ||
		len(history.Raw) == 0 || len(history.Raw) > 10*1024*1024 || !json.Valid(history.Raw) {
		return summary, errors.New("invalid DNSE landing")
	}
	rows, mismatch, err := dnse.ParseHistory(history.Raw, call.Start, call.End)
	if err != nil || mismatch != history.FieldLengthMismatch || !reflectDeepEqualDNSERows(rows, history.Rows) {
		return summary, errors.New("DNSE parsed rows differ from archived source bytes")
	}
	digest := sha256.Sum256(history.Raw)
	sha := hex.EncodeToString(digest[:])
	ingestID, err := newUUID()
	if err != nil {
		return summary, err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return summary, err
	}
	defer tx.Rollback()
	var current string
	var jobID int64
	var symbol, source, start, end, requestURL string
	var httpStatus sql.NullInt64
	if err = tx.QueryRowContext(ctx, `SELECT c.outcome,j.job_id,j.symbol,j.source,j.date_from::text,j.date_to::text,
		c.request_url,c.http_status FROM ops.external_market_calls c JOIN ops.ingest_jobs j USING(job_id)
		WHERE c.call_id=$1 FOR UPDATE OF c,j`, call.CallID).Scan(&current, &jobID, &symbol, &source, &start, &end, &requestURL, &httpStatus); err != nil {
		return summary, err
	}
	if current != "STARTED" || jobID != call.JobID || source != call.Source || symbol != call.Symbol || start != call.Start || end != call.End ||
		(httpStatus.Valid && httpStatus.Int64 != int64(history.HTTPStatus)) || history.HTTPStatus != http.StatusOK || requestURL != history.RequestURL {
		return summary, errors.New("DNSE response has no matched running audited call")
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES($1::uuid,$2,'equity_ohlcv',$3,$4,$5::jsonb,$6,$7) RETURNING landing_id`, ingestID, call.Source, fetchedAt, call.Symbol, string(history.Raw), sha, []byte(history.Raw)).Scan(&landingID)
	if err != nil {
		return summary, err
	}
	var symbolID int64
	if err = tx.QueryRowContext(ctx, `SELECT symbol_id FROM core.symbols WHERE symbol=$1`, call.Symbol).Scan(&symbolID); err != nil {
		return summary, fmt.Errorf("alternate bars require a known symbol: %w", err)
	}
	invalid := 0
	duplicateDates := 0
	for i := 0; i < len(rows); {
		j := i + 1
		for j < len(rows) && rows[j].Date == rows[i].Date {
			j++
		}
		if j-i > 1 {
			duplicateDates++
			for k := i; k < j; k++ {
				_, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
					VALUES($1,$2,$3,$4::date,'DUPLICATE_DAILY_BUCKET','Multiple provider timestamps map to this Vietnam trade date; retained in raw landing and omitted from daily projection')`,
					jobID, landingID, rows[k].SourceRow, rows[k].Date)
				if err != nil {
					return summary, err
				}
			}
			i = j
			continue
		}
		row := rows[i]
		i++
		volume, volOK := finitePositiveOrZero(row.Volume)
		prices := []*float64{row.Open, row.High, row.Low, row.Close}
		priceOK := true
		for _, price := range prices {
			if price == nil || !finitePositive(*price) {
				priceOK = false
			}
		}
		category, reason := "", ""
		if row.Volume == nil || !volOK {
			category, reason = "INVALID_VOLUME", "missing, negative or nonfinite provider volume"
		} else if !priceOK {
			category, reason = "INVALID_PRICE", "missing, nonpositive or nonfinite traded OHLC price"
		} else if *row.High < *row.Low {
			category, reason = "INVALID_OHLC", "high below low"
		} else if volume == 0 {
			category, reason = "ZERO_VOLUME_UNVERIFIED", "zero provider volume; stored as a nontraded source observation"
		}
		if category != "" {
			if _, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
				VALUES($1,$2,$3,$4::date,$5,$6)`, jobID, landingID, row.SourceRow, row.Date, category, reason); err != nil {
				return summary, err
			}
		}
		if category == "INVALID_VOLUME" || category == "INVALID_PRICE" || category == "INVALID_OHLC" {
			invalid++
			continue
		}
		if !priceOK {
			continue
		}
		isTraded := volume > 0
		_, err = tx.ExecContext(ctx, `INSERT INTO core.bars_daily_sources
			(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
			VALUES($1,$2::date,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::uuid,$14)
			ON CONFLICT(symbol_id,trade_date,source) DO UPDATE SET
			o=EXCLUDED.o,h=EXCLUDED.h,l=EXCLUDED.l,c=EXCLUDED.c,v=EXCLUDED.v,adj_basis=EXCLUDED.adj_basis,
			is_traded=EXCLUDED.is_traded,landing_id=EXCLUDED.landing_id,source_row=EXCLUDED.source_row,
			ingest_id=EXCLUDED.ingest_id,fetched_at=EXCLUDED.fetched_at
			WHERE core.bars_daily_sources.fetched_at<=EXCLUDED.fetched_at`,
			symbolID, row.Date, call.Source, *row.Open, *row.High, *row.Low, *row.Close, volume,
			priceAdjustmentBasis(call.Source), isTraded, landingID, row.SourceRow, ingestID, fetchedAt)
		if err != nil {
			return summary, err
		}
		if isTraded {
			summary.Traded++
		} else {
			summary.NoTrade++
		}
	}
	if mismatch && len(rows) > 0 {
		if _, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
			VALUES($1,$2,0,$3::date,'FIELD_LENGTH_MISMATCH','Provider OHLCV arrays have unequal lengths; missing cells were not shifted')`, jobID, landingID, rows[0].Date); err != nil {
			return summary, err
		}
	}
	summary.Rows = len(rows)
	summary.Invalid = invalid
	summary.DuplicateDates = duplicateDates
	summary.LandingID = landingID
	summary.State = "COMPLETED"
	errorType := any(nil)
	if len(rows) == 0 {
		summary.State = "BLOCKED"
		errorType = "NoHistoryData"
	} else if invalid > 0 || mismatch || duplicateDates > 0 {
		summary.State = "PARTIAL"
		errorType = "PartialDNSEFrame"
		if invalid > 0 {
			errorType = "PartialInvalidDNSEFrame"
		} else if duplicateDates > 0 {
			errorType = "DuplicateDNSEDailyBuckets"
		}
	}
	callOutcome := "SUCCEEDED"
	if len(rows) == 0 {
		callOutcome = "EMPTY"
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.external_market_calls SET outcome=$2,http_status=$3,response_sha256=$4,row_count=$5,landing_id=$6,finished_at=now()
		WHERE call_id=$1 AND outcome='STARTED'`, call.CallID, callOutcome, history.HTTPStatus, sha, len(rows), landingID); err != nil {
		return summary, err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state=$2,landed_id=$3,last_error_type=$4,updated_at=now()
		WHERE job_id=$1 AND state='RUNNING'`, jobID, summary.State, landingID, errorType)
	if err != nil {
		return summary, err
	}
	if n, e := res.RowsAffected(); e != nil || n != 1 {
		return summary, errors.New("DNSE job state transition failed")
	}
	return summary, tx.Commit()
}

// CommitVNDIRECTHistory stores the API's unadjusted OHLC and normal-market
// volume as a separate source series. Put-through volume remains in the exact
// raw landing and is not mixed into normal-market volume.
func (p *PostgresStore) CommitVNDIRECTHistory(ctx context.Context, call ExternalMarketCall, fetchedAt time.Time, history vndirect.History) (ExternalMarketSummary, error) {
	var summary ExternalMarketSummary
	if p == nil || p.DB == nil || call.CallID < 1 || call.Source != "vndirect" || fetchedAt.IsZero() ||
		len(history.Raw) == 0 || len(history.Raw) > 10*1024*1024 || !json.Valid(history.Raw) {
		return summary, errors.New("invalid VNDIRECT landing")
	}
	rows, err := vndirect.ParseHistory(history.Raw, call.Symbol, call.Start, call.End)
	if err != nil || !reflect.DeepEqual(rows, history.Rows) {
		return summary, errors.New("VNDIRECT parsed rows differ from archived source bytes")
	}
	digest := sha256.Sum256(history.Raw)
	sha := hex.EncodeToString(digest[:])
	ingestID, err := newUUID()
	if err != nil {
		return summary, err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return summary, err
	}
	defer tx.Rollback()
	var current string
	var jobID int64
	var symbol, source, start, end, requestURL string
	var httpStatus sql.NullInt64
	err = tx.QueryRowContext(ctx, `SELECT c.outcome,j.job_id,j.symbol,j.source,j.date_from::text,j.date_to::text,
		c.request_url,c.http_status FROM ops.external_market_calls c JOIN ops.ingest_jobs j USING(job_id)
		WHERE c.call_id=$1 FOR UPDATE OF c,j`, call.CallID).Scan(&current, &jobID, &symbol, &source, &start, &end, &requestURL, &httpStatus)
	if err != nil {
		return summary, err
	}
	if current != "STARTED" || jobID != call.JobID || source != call.Source || symbol != call.Symbol || start != call.Start || end != call.End ||
		(httpStatus.Valid && httpStatus.Int64 != int64(history.HTTPStatus)) || history.HTTPStatus != http.StatusOK || requestURL != history.RequestURL {
		return summary, errors.New("VNDIRECT response has no matched running audited call")
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES($1::uuid,$2,'equity_ohlcv',$3,$4,$5::jsonb,$6,$7) RETURNING landing_id`, ingestID, call.Source, fetchedAt, call.Symbol, string(history.Raw), sha, []byte(history.Raw)).Scan(&landingID)
	if err != nil {
		return summary, err
	}
	var symbolID int64
	if err = tx.QueryRowContext(ctx, `SELECT symbol_id FROM core.symbols WHERE symbol=$1`, call.Symbol).Scan(&symbolID); err != nil {
		return summary, fmt.Errorf("alternate bars require a known symbol: %w", err)
	}
	invalid := 0
	duplicateDates := 0
	for _, row := range rows {
		if row.TickerMismatch {
			invalid++
			providerCode := row.ProviderCode
			if providerCode == "" {
				providerCode = "(missing)"
			}
			if _, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
				VALUES($1,$2,$3,$4::date,'PROVIDER_TICKER_MISMATCH',$5)`, jobID, landingID, row.SourceRow, row.Date,
				fmt.Sprintf("VNDIRECT returned ticker %s for requested %s; raw row retained and omitted from this symbol series", providerCode, call.Symbol)); err != nil {
				return summary, err
			}
			continue
		}
		if row.DuplicateDate {
			invalid++
			duplicateDates++
			if _, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
				VALUES($1,$2,$3,$4::date,'DUPLICATE_DAILY_BUCKET','Multiple VNDIRECT rows for this requested ticker and Vietnam date; raw rows retained and ambiguous daily bars omitted')`,
				jobID, landingID, row.SourceRow, row.Date); err != nil {
				return summary, err
			}
			continue
		}
		volume, volOK := finitePositiveOrZero(row.Volume)
		prices := []*float64{row.Open, row.High, row.Low, row.Close}
		priceOK := true
		for _, price := range prices {
			if price == nil || !finitePositive(*price) {
				priceOK = false
			}
		}
		category, reason := "", ""
		if row.Volume == nil || !volOK {
			category, reason = "INVALID_VOLUME", "missing, negative or nonfinite normal-market volume"
		} else if !priceOK {
			category, reason = "INVALID_PRICE", "missing, nonpositive or nonfinite unadjusted OHLC price"
		} else if *row.High < *row.Low {
			category, reason = "INVALID_OHLC", "high below low"
		} else if volume == 0 {
			category, reason = "ZERO_NORMAL_VOLUME", "no normal-market volume; put-through volume remains separate in raw evidence"
		}
		if category != "" {
			if _, err = tx.ExecContext(ctx, `INSERT INTO ops.alternate_bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
				VALUES($1,$2,$3,$4::date,$5,$6)`, jobID, landingID, row.SourceRow, row.Date, category, reason); err != nil {
				return summary, err
			}
		}
		if category == "INVALID_VOLUME" || category == "INVALID_PRICE" || category == "INVALID_OHLC" {
			invalid++
			continue
		}
		if !priceOK {
			continue
		}
		var adjustedO, adjustedH, adjustedL, adjustedC any
		var adjustmentVintage any
		adjustedPrices := []*float64{row.AdjustedOpen, row.AdjustedHigh, row.AdjustedLow, row.AdjustedClose}
		adjustedOK := true
		for _, price := range adjustedPrices {
			if price == nil || !finitePositive(*price) {
				adjustedOK = false
			}
		}
		if adjustedOK && *row.AdjustedHigh < *row.AdjustedLow {
			adjustedOK = false
		}
		if adjustedOK {
			adjustedO, adjustedH, adjustedL, adjustedC = *row.AdjustedOpen, *row.AdjustedHigh, *row.AdjustedLow, *row.AdjustedClose
			adjustmentVintage = fetchedAt
		}
		isTraded := volume > 0
		var referencePrice, averagePrice, exchangeCode any
		if row.ReferencePrice != nil {
			referencePrice = *row.ReferencePrice
		}
		if row.AveragePrice != nil {
			averagePrice = *row.AveragePrice
		}
		if row.ExchangeCode != "" {
			exchangeCode = row.ExchangeCode
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO core.bars_daily_sources
			(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at,
			 adjusted_o,adjusted_h,adjusted_l,adjusted_c,adjustment_vintage_at,basic_price,average_price,exchange_code)
			VALUES($1,$2::date,$3,$4,$5,$6,$7,$8,'unadjusted',$9,$10,$11,$12::uuid,$13,$14,$15,$16,$17,$18,$19,$20,$21)
			ON CONFLICT(symbol_id,trade_date,source) DO UPDATE SET
			o=EXCLUDED.o,h=EXCLUDED.h,l=EXCLUDED.l,c=EXCLUDED.c,v=EXCLUDED.v,adj_basis=EXCLUDED.adj_basis,
			is_traded=EXCLUDED.is_traded,landing_id=EXCLUDED.landing_id,source_row=EXCLUDED.source_row,
			ingest_id=EXCLUDED.ingest_id,fetched_at=EXCLUDED.fetched_at,
			adjusted_o=EXCLUDED.adjusted_o,adjusted_h=EXCLUDED.adjusted_h,adjusted_l=EXCLUDED.adjusted_l,
			adjusted_c=EXCLUDED.adjusted_c,adjustment_vintage_at=EXCLUDED.adjustment_vintage_at,
			basic_price=EXCLUDED.basic_price,average_price=EXCLUDED.average_price,exchange_code=EXCLUDED.exchange_code
			WHERE core.bars_daily_sources.fetched_at<=EXCLUDED.fetched_at`,
			symbolID, row.Date, call.Source, *row.Open, *row.High, *row.Low, *row.Close, volume, isTraded, landingID, row.SourceRow, ingestID, fetchedAt,
			adjustedO, adjustedH, adjustedL, adjustedC, adjustmentVintage, referencePrice, averagePrice, exchangeCode)
		if err != nil {
			return summary, err
		}
		if isTraded {
			summary.Traded++
		} else {
			summary.NoTrade++
		}
	}
	summary.Rows = len(rows)
	summary.Invalid = invalid
	summary.DuplicateDates = duplicateDates
	summary.LandingID = landingID
	summary.State = "COMPLETED"
	errorType := any(nil)
	callOutcome := "SUCCEEDED"
	if len(rows) == 0 {
		summary.State = "BLOCKED"
		errorType = "NoHistoryData"
		callOutcome = "EMPTY"
	} else if invalid > 0 {
		summary.State = "PARTIAL"
		errorType = "PartialInvalidVNDIRECTFrame"
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.external_market_calls SET outcome=$2,http_status=$3,response_sha256=$4,row_count=$5,landing_id=$6,finished_at=now()
		WHERE call_id=$1 AND outcome='STARTED'`, call.CallID, callOutcome, history.HTTPStatus, sha, len(rows), landingID); err != nil {
		return summary, err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state=$2,landed_id=$3,last_error_type=$4,updated_at=now()
		WHERE job_id=$1 AND state='RUNNING'`, jobID, summary.State, landingID, errorType)
	if err != nil {
		return summary, err
	}
	if n, e := res.RowsAffected(); e != nil || n != 1 {
		return summary, errors.New("VNDIRECT job state transition failed")
	}
	return summary, tx.Commit()
}

func finitePositive(value float64) bool {
	return value > 0 && !math.IsNaN(value) && !math.IsInf(value, 0)
}

func finitePositiveOrZero(value *float64) (float64, bool) {
	if value == nil || *value < 0 || math.IsNaN(*value) || math.IsInf(*value, 0) {
		return 0, false
	}
	return *value, true
}

func validAlternateSymbol(symbol string) bool {
	if symbol == "" || len(symbol) > 12 {
		return false
	}
	for _, r := range symbol {
		if !(r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

func validExternalSource(source string) bool {
	return source == "dnse" || source == "vndirect"
}

func validISODate(value string) bool {
	t, err := time.Parse("2006-01-02", value)
	return err == nil && t.Format("2006-01-02") == value
}

func reflectDeepEqualDNSERows(a, b []dnse.Bar) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		x, y := a[i], b[i]
		if x.SourceRow != y.SourceRow || x.Date != y.Date || !sameDNSEValue(x.Open, y.Open) || !sameDNSEValue(x.High, y.High) || !sameDNSEValue(x.Low, y.Low) || !sameDNSEValue(x.Close, y.Close) || !sameDNSEValue(x.Volume, y.Volume) {
			return false
		}
	}
	return true
}

func sameDNSEValue(a, b *float64) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
