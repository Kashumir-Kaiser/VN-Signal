package ingest

import (
    "context"
    "database/sql"
    "errors"
    "fmt"
    "strings"
)

// RequeueUnarchivedLegacy is deliberately not a generic unblock API.
// The old A32/ABC-style invalid frames had no archived source bytes, so a
// subsequent controlled fresh vendor call is the only honest recovery.
// This method reserves no new quota and never mutates prior audit records.
func (p *PostgresStore) RequeueUnarchivedLegacy(ctx context.Context, symbol,start,end,source string) error {
    if p==nil||p.DB==nil||symbol==""||start==""||end==""||source!="vci" {
        return errors.New("invalid legacy requeue")
    }
    tx,err:=p.DB.BeginTx(ctx,&sql.TxOptions{Isolation:sql.LevelSerializable})
    if err!=nil{return err}
    defer tx.Rollback()
    var jobID int64
    var errorType string
    var attempts int
    key:=fmt.Sprintf("equity_ohlcv:%s:%s:%s:%s",symbol,source,start,end)
    err=tx.QueryRowContext(ctx,`SELECT j.job_id,j.attempts,j.last_error_type
      FROM ops.ingest_jobs j JOIN core.symbols s ON s.symbol=j.symbol
      WHERE j.idempotency_key=$1 AND j.route='equity_ohlcv' AND j.source=$2
        AND j.symbol=$3 AND j.date_from=$4::date AND j.date_to=$5::date
        AND j.state='BLOCKED' AND j.landed_id IS NULL
        AND j.attempts>=1 AND s.active=true
      FOR UPDATE OF j`,key,source,symbol,start,end).
        Scan(&jobID,&attempts,&errorType)
    if err!=nil{return fmt.Errorf("unarchived blocked job not eligible: %w",err)}
    if !strings.HasPrefix(errorType,"InvalidFrame") {
        return errors.New("only previous invalid-frame legacy blocks can be requeued")
    }
    _,err=tx.ExecContext(ctx,`INSERT INTO ops.ingest_requeue_audit(job_id,prior_attempt,prior_error_type,reason)
        VALUES($1,$2,$3,'UNARCHIVED_LEGACY_FRAME')`,jobID,attempts,errorType)
    if err!=nil{return err}
    updated,err:=tx.ExecContext(ctx,`UPDATE ops.ingest_jobs SET state='PENDING',updated_at=now()
        WHERE job_id=$1 AND state='BLOCKED' AND landed_id IS NULL`,jobID)
    if err!=nil{return err}
    n,err:=updated.RowsAffected()
    if err!=nil||n!=1{return errors.New("unarchived requeue failed state transition")}
    return tx.Commit()
}
