package ingest

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
    "strings"
    "time"
)

// SecurityObservation is a provider-reported category on one observation date,
// NOT a claim about an issuer's initial listing, IPO, delisting effective date,
// legal identity across symbol changes, or historical tradability.
type SecurityObservation struct {
    Symbol string
    Category string
    Exchange string
    Name string
    ShortName string
    Industry string
    SourceRow int
}
type SecurityMasterSummary struct {
    Frames int `json:"frames"`
    ObservationsAdded int `json:"observations_added"`
    ProviderDelistedAdded int `json:"provider_delisted_added"`
    ListedAdded int `json:"listed_added"`
    AlreadyPresent int `json:"already_present"`
}

// ParseFullSecurityListing reuses the existing verified listing contract, but
// retains *every* provider row, including DELISTED. This is a classification
// observed at fetch time, never a reconstructed historical exchange.
func ParseFullSecurityListing(raw []byte) ([]SecurityObservation,error) {
    if _,err:=decodeListingFrame(raw,3);err!=nil{return nil,err}
    dec:=json.NewDecoder(bytes.NewReader(raw))
    dec.DisallowUnknownFields()
    var f listingFrame
    if err:=dec.Decode(&f);err!=nil{return nil,err}
    if err:=dec.Decode(new(any));err!=io.EOF{return nil,ErrInvalidListing}
    result:=make([]SecurityObservation,0,len(f.Rows))
    for i,row:=range f.Rows{
        var sym,ex string
        if json.Unmarshal(row["symbol"],&sym)!=nil || json.Unmarshal(row["exchange"],&ex)!=nil {
            return nil,fmt.Errorf("%w: row %d symbol/exchange",ErrInvalidListing,i)
        }
        sym,ex=strings.ToUpper(strings.TrimSpace(sym)),strings.ToUpper(strings.TrimSpace(ex))
        out:=SecurityObservation{Symbol:sym,SourceRow:i}
        if ex=="DELISTED"{
            out.Category="PROVIDER_DELISTED_UNDATED"
        }else{
            out.Category="EXCHANGE_LISTED"
            out.Exchange=ex
        }
        for _,p:=range []struct{key string;target *string}{
            {"organ_name",&out.Name},{"organ_short_name",&out.ShortName},
        }{
            if b,ok:=row[p.key];ok && string(b)!="null" {
                if err:=json.Unmarshal(b,p.target);err!=nil||len(*p.target)>1024{
                    return nil,fmt.Errorf("%w: row %d invalid %s",ErrInvalidListing,i,p.key)
                }
            }
        }
        if b,ok:=row["icb_code_lv2"];ok && string(b)!="null" {
            if err:=json.Unmarshal(b,&out.Industry);err!=nil {
                var n json.Number
                if err:=json.Unmarshal(b,&n);err!=nil{return nil,fmt.Errorf("%w: invalid industry",ErrInvalidListing)}
                out.Industry=n.String()
            }
        }
        result=append(result,out)
    }
    if len(result)!=f.Count{return nil,ErrInvalidListing}
    return result,nil
}

// RebuildSecurityMaster is an offline projection of already-imported, full
// provider listing landings. It never invokes the worker or quota gateway.
func (p *PostgresStore) RebuildSecurityMaster(ctx context.Context)(SecurityMasterSummary,error){
    var result SecurityMasterSummary
    if p==nil||p.DB==nil{return result,errors.New("PostgreSQL required")}
    rows,err:=p.DB.QueryContext(ctx,`SELECT landing_id FROM raw.landings
        WHERE route='equity_list' AND source='vci'
        ORDER BY fetched_at,landing_id`)
    if err!=nil{return result,err}
    ids:=[]int64{}
    for rows.Next(){var id int64;if err:=rows.Scan(&id);err!=nil{rows.Close();return result,err};ids=append(ids,id)}
    if err:=rows.Err();err!=nil{rows.Close();return result,err}
    if err:=rows.Close();err!=nil{return result,err}
    if len(ids)==0{return result,errors.New("no previously imported equity listing landings")}
    for _,id:=range ids{
        newCount,oldCount,listCount,err:=p.syncSecurityLanding(ctx,id)
        if err!=nil{return result,fmt.Errorf("security master source landing %d: %w",id,err)}
        result.Frames++
        result.ObservationsAdded+=newCount
        result.ProviderDelistedAdded+=oldCount
        result.ListedAdded+=listCount
        // The number of provider symbols per frame is counted again in the
        // projection; a repeated call must not duplicate existing evidence.
    }
    return result,nil
}

func (p *PostgresStore) syncSecurityLanding(ctx context.Context,landingID int64)(int,int,int,error){
    tx,err:=p.DB.BeginTx(ctx,&sql.TxOptions{Isolation:sql.LevelSerializable})
    if err!=nil{return 0,0,0,err}
    defer tx.Rollback()
    if _,err:=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(2108701,2601)`);err!=nil{return 0,0,0,err}
    n,d,l,err:=syncSecurityLandingTx(ctx,tx,landingID)
    if err!=nil{return 0,0,0,err}
    return n,d,l,tx.Commit()
}

// syncSecurityLandingTx is also called by the normal current-listing importer,
// so every FUTURE verified listing call includes DELISTED observations as well.
func syncSecurityLandingTx(ctx context.Context,tx *sql.Tx,landingID int64)(int,int,int,error){
    var raw []byte
    var expected,route,source string
    var fetched time.Time
    err:=tx.QueryRowContext(ctx,`SELECT payload_bytes,payload_sha256,route,source,fetched_at
      FROM raw.landings WHERE landing_id=$1`,landingID).
      Scan(&raw,&expected,&route,&source,&fetched)
    if err!=nil{return 0,0,0,err}
    if route!="equity_list"||source!="vci"||len(raw)<2||len(raw)>10*1024*1024{
        return 0,0,0,errors.New("not an archived verified vci equity listing frame")
    }
    h:=sha256.Sum256(raw)
    if hex.EncodeToString(h[:])!=strings.ToLower(expected){return 0,0,0,errors.New("archived frame SHA-256 mismatch")}
    symbols,err:=ParseFullSecurityListing(raw)
    if err!=nil{return 0,0,0,err}
    observed:=fetched.In(time.FixedZone("Asia/Ho_Chi_Minh",7*3600)).Format("2006-01-02")
    // An archive cannot manufacture new historical membership: all currently
    // listed entries must match their independently committed daily snapshot.
    verification,err:=tx.QueryContext(ctx,`SELECT s.symbol,l.exchange,coalesce(l.industry,'')
       FROM core.listing_snapshots l JOIN core.symbols s ON s.symbol_id=l.symbol_id
       WHERE l.snapshot_date=$1::date ORDER BY s.symbol`,observed)
    if err!=nil{return 0,0,0,err}
    actual:=map[string]Listing{}
    for verification.Next(){
        var row Listing
        if err=verification.Scan(&row.Symbol,&row.Exchange,&row.Industry);err!=nil{break}
        actual[row.Symbol]=row
    }
    if err==nil{err=verification.Err()}
    if closeErr:=verification.Close();err==nil{err=closeErr}
    if err!=nil{return 0,0,0,err}
    listed:=0
    for _,r:=range symbols{
        if r.Category!="EXCHANGE_LISTED"{continue}
        listed++
        expectedRow,ok:=actual[r.Symbol]
        if !ok||expectedRow.Exchange!=r.Exchange||expectedRow.Industry!=r.Industry{
            return 0,0,0,fmt.Errorf("source differs from imported listing snapshot %s/%s",r.Symbol,observed)
        }
    }
    if listed!=len(actual){return 0,0,0,errors.New("archived market membership incomplete")}
    added,delisted,listedAdded:=0,0,0
    for _,r:=range symbols{
        var securityID int64
        err=tx.QueryRowContext(ctx,`INSERT INTO core.security_master(symbol,first_observed_at,last_observed_at)
           VALUES($1,$2,$2)
           ON CONFLICT(symbol) DO UPDATE SET
             first_observed_at=LEAST(core.security_master.first_observed_at,EXCLUDED.first_observed_at),
             last_observed_at=GREATEST(core.security_master.last_observed_at,EXCLUDED.last_observed_at)
           RETURNING security_id`,r.Symbol,fetched).Scan(&securityID)
        if err!=nil{return 0,0,0,err}
        var name,short,industry any
        if r.Name!=""{name=r.Name}
        if r.ShortName!=""{short=r.ShortName}
        if r.Industry!=""{industry=r.Industry}
        var rowID int64
        err=tx.QueryRowContext(ctx,`INSERT INTO core.security_observations
          (security_id,landing_id,provider_row_index,observed_on,observed_at,
           source,category,exchange,legal_name,short_name,icb_lv2)
          VALUES($1,$2,$3,$4::date,$5,'vci',$6,$7,$8,$9,$10)
          ON CONFLICT(landing_id,provider_row_index) DO NOTHING
          RETURNING observation_id`,securityID,landingID,r.SourceRow,observed,fetched,
          r.Category,nullIfEmpty(r.Exchange),name,short,industry).Scan(&rowID)
        if errors.Is(err,sql.ErrNoRows){continue}
        if err!=nil{return 0,0,0,err}
        added++
        if r.Category=="PROVIDER_DELISTED_UNDATED"{delisted++}else{listedAdded++}
    }
    return added,delisted,listedAdded,nil
}
func nullIfEmpty(s string) any {if s==""{return nil};return s}
