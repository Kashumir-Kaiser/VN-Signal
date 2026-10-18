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

// CommitIndexLanding archives a verified source response and canonical index
// bars in one transaction, linked to the successful durable API reservation.
func (p *PostgresStore) CommitIndexLanding(ctx context.Context, item IndexLanding) error {
	if p == nil || p.DB == nil || item.JobID == "" || item.Symbol != "VNINDEX" || (item.Source != "kbs" && item.Source != "vci") || item.FetchedAt.IsZero() || !json.Valid(item.Raw) || len(item.Frame.Rows) == 0 {
		return errors.New("invalid index landing")
	}
	f, err := AnalyzeIndexBarsForSource(item.Symbol, item.Source, item.Raw)
	if err != nil || !reflect.DeepEqual(f, item.Frame) {
		return errors.New("index landing differs from source bytes")
	}
	h := sha256.Sum256(item.Raw)
	if !strings.EqualFold(hex.EncodeToString(h[:]), item.SHA256) {
		return errors.New("index landing checksum mismatch")
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
	var state, source, symbol, start, end string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,source,symbol,date_from::text,date_to::text,attempts FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, item.JobID).Scan(&jobID, &state, &source, &symbol, &start, &end, &attempts)
	if err != nil {
		return err
	}
	if state != "RUNNING" || source != item.Source || symbol != "VNINDEX" || attempts < 1 || f.FirstDate < start || f.LastDate > end {
		return errors.New("no matched running index request")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, jobID, attempts).Scan(&outcome); err != nil {
		return err
	}
	if outcome != "SUCCEEDED" {
		return errors.New("index request not audited as succeeded")
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes) VALUES($1::uuid,$2,'index_ohlcv',$3,$4,$5::jsonb,$6,$7) RETURNING landing_id`, uuid, item.Source, item.FetchedAt, item.Symbol, string(item.Raw), item.SHA256, []byte(item.Raw)).Scan(&landingID)
	if err != nil {
		return err
	}
	for _, b := range f.Rows {
		if _, err = tx.ExecContext(ctx, `INSERT INTO core.index_bars(index_symbol,trade_date,o,h,l,c,v,source,ingest_id,fetched_at) VALUES($1,$2::date,$3,$4,$5,$6,$7,$8,$9::uuid,$10) ON CONFLICT(index_symbol,trade_date,source) DO UPDATE SET o=EXCLUDED.o,h=EXCLUDED.h,l=EXCLUDED.l,c=EXCLUDED.c,v=EXCLUDED.v,ingest_id=EXCLUDED.ingest_id,fetched_at=EXCLUDED.fetched_at WHERE core.index_bars.fetched_at<=EXCLUDED.fetched_at`, item.Symbol, b.Date, b.Open, b.High, b.Low, b.Close, b.Volume, item.Source, uuid, item.FetchedAt); err != nil {
			return err
		}
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='COMPLETED',landed_id=$2,last_error_type=NULL,updated_at=now() WHERE job_id=$1 AND state='RUNNING'`, jobID, landingID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("index landing state transition failed")
	}
	return tx.Commit()
}

// QuarantineIndexFrame preserves a successful but unusable provider response
// and blocks the job atomically, without touching canonical index bars.
func (p *PostgresStore) QuarantineIndexFrame(ctx context.Context, key, source, reason string, raw json.RawMessage) error {
	if p == nil || p.DB == nil || key == "" || (source != "kbs" && source != "vci") || reason == "" || len(raw) == 0 || len(raw) > 10*1024*1024 || !json.Valid(raw) {
		return errors.New("invalid index quarantine")
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
	var state, symbol, jobSource string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,symbol,source,attempts FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, key).Scan(&id, &state, &symbol, &jobSource, &attempts)
	if err != nil {
		return err
	}
	if state != "RUNNING" || symbol != "VNINDEX" || jobSource != source || attempts < 1 {
		return errors.New("no matched running index quarantine job")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, id, attempts).Scan(&outcome); err != nil {
		return err
	}
	if outcome != "SUCCEEDED" {
		return errors.New("index response not audited as succeeded")
	}
	var landing int64
	if err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes) VALUES($1::uuid,$2,'index_ohlcv_quarantine',now(),$3,$4::jsonb,$5,$6) RETURNING landing_id`, uuid, source, symbol, string(raw), digest, []byte(raw)).Scan(&landing); err != nil {
		return err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='BLOCKED',landed_id=$2,last_error_type=$3,updated_at=now() WHERE job_id=$1 AND state='RUNNING'`, id, landing, reason)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("index quarantine state transition failed")
	}
	return tx.Commit()
}
