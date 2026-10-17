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

type CompanyInfoProbe struct {
    Symbol string
    ObservedAt time.Time
    ReportedListingDate string
    Raw json.RawMessage
    SHA256 string
}

func ParseCompanyInfoProbe(reportBytes []byte)(CompanyInfoProbe,error){
    var result CompanyInfoProbe
    if len(reportBytes)<2 || len(reportBytes)>12*1024*1024{
        return result,errors.New("company probe size invalid")
    }
    var report struct{
        Active bool `json:"active"`
        At string `json:"at"`
        Routes map[string]struct{
            Available bool `json:"available"`
            Count int `json:"count"`
            ErrorType string `json:"error_type"`
            ErrorCause string `json:"error_cause"`
        } `json:"routes"`
        CompanySymbol string `json:"company_info_symbol"`
        Frame json.RawMessage `json:"company_info_frame"`
    }
    if err:=json.Unmarshal(reportBytes,&report);err!=nil{return result,err}
    route,ok:=report.Routes["company_info"]
    if !report.Active || !ok {
        return result,errors.New("company_info not verified: missing active route proof")
    }
    if !route.Available || route.Count!=1{
        return result,fmt.Errorf("company_info unavailable: error_type=%s cause=%s count=%d",
            route.ErrorType,route.ErrorCause,route.Count)
    }
    at,err:=time.Parse(time.RFC3339Nano,report.At)
    if err!=nil{return result,err}
    symbol:=strings.ToUpper(strings.TrimSpace(report.CompanySymbol))
    if symbol==""||len(symbol)>12||symbol!=report.CompanySymbol{
        return result,errors.New("missing authenticated company profile symbol")
    }
    for _,r:=range symbol{
        if !(r>='A'&&r<='Z'||r>='0'&&r<='9'){
            return result,errors.New("invalid company symbol")
        }
    }
    dec:=json.NewDecoder(bytes.NewReader(report.Frame))
    dec.DisallowUnknownFields()
    var frame listingFrame
    if err:=dec.Decode(&frame);err!=nil{return result,err}
    if err:=dec.Decode(new(any));err!=io.EOF{return result,errors.New("trailing company profile bytes")}
    if frame.Count!=1||len(frame.Rows)!=1{return result,errors.New("company info must contain exactly one row")}
    columns:=map[string]bool{}
    for _,col:=range frame.Columns{
        if col==""||columns[col]{return result,errors.New("duplicate company column")}
        columns[col]=true
    }
    if !columns["symbol"]||!columns["listing_date"]{
        return result,errors.New("company profile lacks source fields")
    }
    for key:=range frame.Rows[0]{
        if !columns[key]{return result,errors.New("company profile contains unknown field")}
    }
    var fromSource string
    if err:=json.Unmarshal(frame.Rows[0]["symbol"],&fromSource);err!=nil||fromSource!=symbol{
        return result,errors.New("provider returned wrong security")
    }
    reported:=""
    if date,ok:=frame.Rows[0]["listing_date"];ok && string(date)!="null" {
        var value string
        if err:=json.Unmarshal(date,&value);err!=nil{return result,errors.New("bad provider listing_date type")}
        if len(value)<10{return result,errors.New("truncated provider listing_date")}
        parsed,err:=time.Parse("2006-01-02",value[:10])
        if err!=nil||parsed.Format("2006-01-02")!=value[:10] {
            return result,errors.New("invalid provider listing_date")
        }
        if len(value)>10{
            // ISO timestamp with an explicit offset or naive provider-local
            // timestamp. Never apply UTC conversion to the reported date.
            layouts:=[]string{time.RFC3339Nano,"2006-01-02T15:04:05","2006-01-02 15:04:05"}
            valid:=false
            for _,layout:=range layouts{
                if _,err:=time.Parse(layout,value);err==nil{valid=true;break}
            }
            if !valid{return result,errors.New("invalid provider listing datetime")}
        }
        reported=value[:10]
    }
    h:=sha256.Sum256(report.Frame)
    return CompanyInfoProbe{
        Symbol:symbol,ObservedAt:at.UTC(),ReportedListingDate:reported,
        Raw:append(json.RawMessage(nil),report.Frame...),
        SHA256:hex.EncodeToString(h[:]),
    },nil
}

func (p *PostgresStore) ImportCompanyInfo(ctx context.Context,profile CompanyInfoProbe)(bool,error){
    if p==nil||p.DB==nil{return false,errors.New("database not configured")}
    if len(profile.Raw)==0||profile.ObservedAt.IsZero(){return false,errors.New("missing source bytes")}
    // Reparse a synthetic active probe frame at the same boundary so caller
    // cannot substitute a forged symbol or normalized listing date.
    verified,err:=ParseCompanyInfoProbe(mustMarshalProfileProbe(profile))
    if err!=nil || verified.Symbol!=profile.Symbol ||
        verified.ReportedListingDate!=profile.ReportedListingDate ||
        verified.SHA256!=profile.SHA256{
        return false,errors.New("company profile differs from vendor bytes")
    }
    tx,err:=p.DB.BeginTx(ctx,&sql.TxOptions{Isolation:sql.LevelSerializable})
    if err!=nil{return false,err}
    defer tx.Rollback()
    if _,err=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(2108701,2601)`);err!=nil{return false,err}
    var id int64
    if err=tx.QueryRowContext(ctx,`SELECT security_id FROM core.security_master WHERE symbol=$1`,profile.Symbol).Scan(&id);err!=nil{
        return false,fmt.Errorf("security not in observed master: %w",err)
    }
    var existingID int64
    var existingRaw []byte
    err=tx.QueryRowContext(ctx,`SELECT landing_id,payload_bytes FROM raw.landings
       WHERE route='company_info' AND source='vci' AND symbol=$1 AND fetched_at=$2
       ORDER BY landing_id LIMIT 1`,profile.Symbol,profile.ObservedAt).
       Scan(&existingID,&existingRaw)
    if err==nil{
        if !bytes.Equal(existingRaw,profile.Raw) {return false,errors.New("same-time provider profile conflict")}
        var observedDate sql.NullString
        err=tx.QueryRowContext(ctx,`SELECT reported_listing_date::text FROM core.company_profile_observations
         WHERE landing_id=$1 AND security_id=$2`,existingID,id).Scan(&observedDate)
        if err!=nil{return false,fmt.Errorf("existing company projection missing: %w",err)}
        if observedDate.String!=profile.ReportedListingDate {
            return false,errors.New("stored listing date differs from archived source")
        }
        return false,tx.Commit()
    }
    if !errors.Is(err,sql.ErrNoRows){return false,err}
    uuid,err:=newUUID()
    if err!=nil{return false,err}
    var landingID int64
    err=tx.QueryRowContext(ctx,`INSERT INTO raw.landings
      (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
      VALUES($1::uuid,'vci','company_info',$2,$3,$4::jsonb,$5,$6)
      RETURNING landing_id`,uuid,profile.ObservedAt,profile.Symbol,
      string(profile.Raw),profile.SHA256,[]byte(profile.Raw)).Scan(&landingID)
    if err!=nil{return false,err}
    var date any
    if profile.ReportedListingDate!=""{date=profile.ReportedListingDate}
    _,err=tx.ExecContext(ctx,`INSERT INTO core.company_profile_observations
       (security_id,landing_id,observed_at,source,reported_listing_date)
       VALUES($1,$2,$3,'vci',$4::date)`,id,landingID,profile.ObservedAt,date)
    if err!=nil{return false,err}
    return true,tx.Commit()
}

// Recreate a minimal active probe envelope for boundary revalidation.
// All relevant fields come from the original profile object; raw itself is
// parsed and matched again, including its symbol and date.
func mustMarshalProfileProbe(p CompanyInfoProbe) []byte {
    body,_:=json.Marshal(map[string]any{
        "active":true,"at":p.ObservedAt.Format(time.RFC3339Nano),
        "routes":map[string]any{"company_info":map[string]any{"available":true,"count":1}},
        "company_info_symbol":p.Symbol,
        "company_info_frame":p.Raw,
    })
    return body
}
