package ingest

import (
    "context"
    "crypto/sha256"
    "database/sql"
    "encoding/hex"
    "encoding/json"
    "errors"
    "fmt"
    "reflect"
    "strings"
    "time"
)

// MarketLanding binds exact immutable source bytes to a row-level assessment.
type MarketLanding struct {
    Landing Landing
    Frame MarketFrame
}

// CommitMarketLanding validates every source row a second time inside the
// authoritative DB boundary. Missing/nontrade sessions remain in the raw
// archive and quality ledger, never silently rewritten into trade candles.
func (p *PostgresStore) CommitMarketLanding(ctx context.Context, item MarketLanding) (string,error) {
    land := item.Landing
    if p == nil || p.DB == nil || land.JobID == "" || land.Source != "vci" ||
        land.FetchedAt.IsZero() || !json.Valid(land.Raw) {
        return "", errors.New("invalid market landing")
    }
    analyzed,err := AnalyzeMarketBars(land.Bars.Symbol,land.Raw)
    if err != nil || !reflect.DeepEqual(analyzed,item.Frame) || !reflect.DeepEqual(analyzed.Bars,land.Bars) {
        return "", errors.New("market landing differs from source bytes")
    }
    sha := sha256.Sum256(land.Raw)
    if !strings.EqualFold(hex.EncodeToString(sha[:]),land.SHA256) {
        return "",errors.New("market landing checksum mismatch")
    }
    uuid,err := newUUID()
    if err != nil { return "",err }
    tx,err := p.DB.BeginTx(ctx,&sql.TxOptions{Isolation:sql.LevelSerializable})
    if err != nil { return "",err }
    defer tx.Rollback()
    var jobID int64
    var state,source,symbol,start,end string
    var attempts int
    err=tx.QueryRowContext(ctx,`SELECT job_id,state,source,symbol,date_from::text,date_to::text,attempts
        FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`,land.JobID).
        Scan(&jobID,&state,&source,&symbol,&start,&end,&attempts)
    if err != nil { return "",err }
    if state != "RUNNING" || source != land.Source || symbol != land.Bars.Symbol || attempts < 1 {
        return "",errors.New("no matched running vendor request")
    }
    if analyzed.FirstDate < start || analyzed.LastDate > end {
        return "",errors.New("source frame outside requested range")
    }
    var outcome string
    if err=tx.QueryRowContext(ctx,`SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`,jobID,attempts).Scan(&outcome);err != nil {
        return "",err
    }
    if outcome != "SUCCEEDED" { return "",errors.New("vendor request not audited as succeeded") }
    var landingID int64
    err=tx.QueryRowContext(ctx,`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES($1::uuid,$2,'equity_ohlcv',$3,$4,$5::jsonb,$6,$7) RETURNING landing_id`,
        uuid,land.Source,land.FetchedAt,symbol,string(land.Raw),land.SHA256,[]byte(land.Raw)).Scan(&landingID)
    if err != nil { return "",err }
    next,err:=p.applyMarketFrame(ctx,tx,jobID,landingID,symbol,land.Source,uuid,land.FetchedAt,analyzed,"RUNNING")
    if err!=nil {return "",err}
    return next,tx.Commit()
}

// applyMarketFrame is shared by live dispatch and offline archived recovery.
// Its SQL writes clean positive-volume candles and records every other row.
// The whole operation must be inside the caller's single transaction.
func (p *PostgresStore) applyMarketFrame(ctx context.Context,tx *sql.Tx,jobID,landingID int64,
    symbol,source,ingestID string,fetchedAt time.Time, f MarketFrame,expected string)(string,error) {
    var symbolID int64
    err:=tx.QueryRowContext(ctx,`SELECT symbol_id FROM core.symbols WHERE symbol=$1 AND active=true`,symbol).Scan(&symbolID)
    if err!=nil {return "",fmt.Errorf("verified active stock required: %w",err)}
    for _,bar:=range f.Bars.Rows {
        if bar.Volume<=0 {return "",errors.New("nontraded bar in canonical trade set")}
        _,err=tx.ExecContext(ctx,`INSERT INTO core.bars_daily
            (symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at,is_traded)
            VALUES($1,$2::date,$3,$4,$5,$6,$7,'unknown',$8,$9::uuid,$10,true)
            ON CONFLICT(symbol_id,trade_date) DO UPDATE SET
            o=EXCLUDED.o,h=EXCLUDED.h,l=EXCLUDED.l,c=EXCLUDED.c,v=EXCLUDED.v,
            adj_basis=EXCLUDED.adj_basis,source=EXCLUDED.source,ingest_id=EXCLUDED.ingest_id,
            fetched_at=EXCLUDED.fetched_at,is_traded=true
            WHERE core.bars_daily.fetched_at<=EXCLUDED.fetched_at`,
            symbolID,bar.Date,bar.Open,bar.High,bar.Low,bar.Close,bar.Volume,source,ingestID,fetchedAt)
        if err!=nil {return "",fmt.Errorf("upsert %s/%s: %w",symbol,bar.Date,err)}
    }
    for _,issue:=range f.Issues {
        _,err=tx.ExecContext(ctx,`INSERT INTO ops.bar_quality_issues
            (job_id,landing_id,source_row,trade_date,category,reason)
            VALUES($1,$2,$3,$4::date,$5,$6)`,
            jobID,landingID,issue.Row,issue.Date,issue.Category,issue.Reason)
        if err!=nil {return "",fmt.Errorf("audit issue %s/%s: %w",symbol,issue.Date,err)}
    }
    next:="COMPLETED"
    var errorType any
    if f.InvalidTraded>0 {next="PARTIAL";errorType="PartialInvalidTradedBars"}
    res,err:=tx.ExecContext(ctx,`UPDATE ops.ingest_jobs SET state=$3,
        landed_id=$4,last_error_type=$5,updated_at=now()
        WHERE job_id=$1 AND state=$2`,jobID,expected,next,landingID,errorType)
    if err!=nil{return "",err}
    n,err:=res.RowsAffected()
    if err!=nil || n!=1 {return "",errors.New("market landing state transition failed")}
    return next,nil
}

// RecoverArchivedFrame rehabilitates only frames that were already fetched,
// metered and archived. It never performs an API call or refunds quota.
// Structural faults remain blocked rather than fabricated into valid rows.
func (p *PostgresStore) RecoverArchivedFrame(ctx context.Context,key string)(string,error) {
    if p==nil || p.DB==nil || key=="" {return "",errors.New("database and key required")}
    tx,err:=p.DB.BeginTx(ctx,&sql.TxOptions{Isolation:sql.LevelSerializable})
    if err!=nil{return "",err}
    defer tx.Rollback()
    var jobID,landingID int64
    var symbol,source,start,end,archiveRoute,expectedSHA string
    var raw []byte
    var fetchedAt time.Time
    err=tx.QueryRowContext(ctx,`SELECT j.job_id,j.landed_id,j.symbol,j.source,j.date_from::text,j.date_to::text,
        l.route,l.payload_bytes,l.payload_sha256,l.fetched_at
        FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id
        WHERE j.idempotency_key=$1 AND j.state='BLOCKED' FOR UPDATE OF j`,key).
        Scan(&jobID,&landingID,&symbol,&source,&start,&end,&archiveRoute,&raw,&expectedSHA,&fetchedAt)
    if err!=nil{return "",err}
    if archiveRoute!="equity_ohlcv_quarantine" || source!="vci" ||
        len(raw)==0 || len(raw)>10*1024*1024 || !json.Valid(raw) {
        return "",errors.New("unverified quarantined source frame")
    }
    digest:=sha256.Sum256(raw)
    if !strings.EqualFold(hex.EncodeToString(digest[:]),expectedSHA) {
        return "",errors.New("quarantine byte provenance mismatch")
    }
    analyzed,err:=AnalyzeMarketBars(symbol,raw)
    if err!=nil{return "",err}
    if analyzed.FirstDate<start || analyzed.LastDate>end {
        return "",errors.New("quarantined frame outside original history range")
    }
    // Reuse the exact originally archived vendor bytes and ingest identifier.
    var uuid string
    err=tx.QueryRowContext(ctx,`SELECT ingest_id::text FROM raw.landings WHERE landing_id=$1`,landingID).Scan(&uuid)
    if err!=nil{return "",err}
    next,err:=p.applyMarketFrame(ctx,tx,jobID,landingID,symbol,source,uuid,fetchedAt,analyzed,"BLOCKED")
    if err!=nil{return "",err}
    return next,tx.Commit()
}
