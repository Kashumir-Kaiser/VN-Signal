package ingest

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
)

// CommitCrossSourceLanding archives a successfully metered KBS equity frame.
// It deliberately writes no canonical/core market data: reconciliation decides
// whether a cross-source frame is suitable for any downstream projection.
func (p *PostgresStore) CommitCrossSourceLanding(ctx context.Context, item MarketLanding) (string, error) {
	land := item.Landing
	land.JobID = strings.TrimSpace(land.JobID)
	land.Source = "kbs"
	if land.JobID == "" || land.FetchedAt.IsZero() || !json.Valid(land.Raw) {
		return "", errors.New("invalid cross-source landing")
	}
	analyzed, err := AnalyzeMarketBarsForSource(land.Bars.Symbol, land.Source, land.Raw)
	if err != nil || !reflect.DeepEqual(analyzed, item.Frame) || !reflect.DeepEqual(analyzed.Bars, land.Bars) {
		return "", errors.New("cross-source landing differs from source bytes")
	}
	digest := sha256.Sum256(land.Raw)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), land.SHA256) {
		return "", errors.New("cross-source landing checksum mismatch")
	}
	if p == nil || p.DB == nil {
		return "", errors.New("invalid cross-source store")
	}
	uuid, err := newUUID()
	if err != nil {
		return "", err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()

	var jobID int64
	var state, source, route, symbol, start, end string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,source,route,symbol,date_from::text,date_to::text,attempts
		FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, land.JobID).
		Scan(&jobID, &state, &source, &route, &symbol, &start, &end, &attempts)
	if err != nil {
		return "", err
	}
	if state != "RUNNING" || source != "kbs" || route != "equity_ohlcv" || symbol != land.Bars.Symbol || attempts < 1 {
		return "", errors.New("no matched running KBS equity request")
	}
	if analyzed.FirstDate < start || analyzed.LastDate > end {
		return "", errors.New("KBS source frame outside requested range")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, jobID, attempts).Scan(&outcome); err != nil {
		return "", err
	}
	if outcome != "SUCCEEDED" {
		return "", errors.New("KBS request not audited as succeeded")
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings
		(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES($1::uuid,'kbs','equity_ohlcv',$2,$3,$4::jsonb,$5,$6) RETURNING landing_id`,
		uuid, land.FetchedAt, symbol, string(land.Raw), land.SHA256, []byte(land.Raw)).Scan(&landingID)
	if err != nil {
		return "", err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='COMPLETED',landed_id=$2,last_error_type=NULL,updated_at=now()
		WHERE job_id=$1 AND state='RUNNING'`, jobID, landingID)
	if err != nil {
		return "", err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return "", errors.New("cross-source landing state transition failed")
	}
	if err = tx.Commit(); err != nil {
		return "", err
	}
	return uuid, nil
}
