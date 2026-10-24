package ingest

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
)

// CommitFundamentalLanding stores the immutable source frame and its period
// slices atomically, tied to the successful CallRecorded reservation.
func (p *PostgresStore) CommitFundamentalLanding(ctx context.Context, item FundamentalLanding) error {
	if p == nil || p.DB == nil || item.JobID == "" || item.Source != "vci" || item.FetchedAt.IsZero() || !json.Valid(item.Raw) || len(item.Periods) == 0 {
		return errors.New("invalid fundamental landing")
	}
	f, periods, err := AnalyzeFundamentalFrame(item.Symbol, item.StatementType, item.Periods[0].Type, item.Raw)
	if err != nil || len(f.Rows) != len(item.Frame.Rows) {
		return errors.New("fundamental frame differs from source bytes")
	}
	h := sha256.Sum256(item.Raw)
	if !strings.EqualFold(hex.EncodeToString(h[:]), item.SHA256) {
		return errors.New("fundamental checksum mismatch")
	}
	if len(periods) != len(item.Periods) {
		return errors.New("fundamental period set mismatch")
	}
	for i := range periods {
		if periods[i] != item.Periods[i] {
			return errors.New("fundamental period set mismatch")
		}
	}
	uuid, err := newUUID()
	if err != nil {
		return err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var jobID int64
	var state, source, symbol, route string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,source,symbol,route,attempts FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, item.JobID).Scan(&jobID, &state, &source, &symbol, &route, &attempts)
	if err != nil {
		return err
	}
	if state != "RUNNING" || source != "vci" || symbol != item.Symbol || route != item.StatementType || attempts < 1 {
		return errors.New("no matched running fundamental request")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, jobID, attempts).Scan(&outcome); err != nil {
		return err
	}
	if outcome != "SUCCEEDED" {
		return errors.New("fundamental request not audited as succeeded")
	}
	var landingID, symbolID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes) VALUES($1::uuid,$2,$3,$4,$5,$6::jsonb,$7,$8) RETURNING landing_id`, uuid, item.Source, "fundamental.equity."+item.StatementType, item.FetchedAt, item.Symbol, string(item.Raw), item.SHA256, []byte(item.Raw)).Scan(&landingID)
	if err != nil {
		return err
	}
	if err = tx.QueryRowContext(ctx, `SELECT symbol_id FROM core.symbols WHERE symbol=$1 AND active=true`, item.Symbol).Scan(&symbolID); err != nil {
		return err
	}
	rows, err := json.Marshal(item.Frame.Rows)
	if err != nil {
		return err
	}
	for _, period := range periods {
		if _, err = tx.ExecContext(ctx, `SELECT core.archive_fundamental_rows($1,$2,$3,$4,$5::date,$6,$7::jsonb,$8)`, landingID, symbolID, item.StatementType, period.Type, period.End.Format("2006-01-02"), period.Key, string(rows), item.Mode); err != nil {
			return err
		}
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='COMPLETED',landed_id=$2,last_error_type=NULL,updated_at=now() WHERE job_id=$1 AND state='RUNNING'`, jobID, landingID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("fundamental landing state transition failed")
	}
	return tx.Commit()
}

func (p *PostgresStore) QuarantineFundamentalFrame(ctx context.Context, key, source, reason string, raw json.RawMessage) error {
	if p == nil || p.DB == nil || key == "" || source != "vci" || reason == "" || len(raw) == 0 || len(raw) > 10<<20 || !json.Valid(raw) {
		return errors.New("invalid fundamental quarantine")
	}
	if len(reason) > 120 {
		reason = reason[:120]
	}
	h := sha256.Sum256(raw)
	digest := hex.EncodeToString(h[:])
	uuid, err := newUUID()
	if err != nil {
		return err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var id int64
	var state, symbol, jobSource, route string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,symbol,source,route,attempts FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, key).Scan(&id, &state, &symbol, &jobSource, &route, &attempts)
	if err != nil {
		return err
	}
	if state != "RUNNING" || jobSource != source || attempts < 1 {
		return errors.New("no matched fundamental quarantine job")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, id, attempts).Scan(&outcome); err != nil {
		return err
	}
	if outcome != "SUCCEEDED" {
		return errors.New("fundamental response not audited as succeeded")
	}
	var landing int64
	if err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes) VALUES($1::uuid,$2,$3,now(),$4,$5::jsonb,$6,$7) RETURNING landing_id`, uuid, source, "fundamental.equity."+route+"_quarantine", symbol, string(raw), digest, []byte(raw)).Scan(&landing); err != nil {
		return err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='BLOCKED',landed_id=$2,last_error_type=$3,updated_at=now() WHERE job_id=$1 AND state='RUNNING'`, id, landing, reason)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("fundamental quarantine transition failed")
	}
	return tx.Commit()
}
