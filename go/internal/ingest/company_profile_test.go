package ingest

import (
    "encoding/json"
    "bytes"
    "crypto/sha256"
    "encoding/hex"
    "testing"
    "strings"
)

func companyProbeFixture(symbol,date string) []byte {
    frame:=map[string]any{
        "columns":[]string{"symbol","name","listing_date"},
        "count":1,
        "rows":[]map[string]any{{"symbol":symbol,"name":"Test issuer","listing_date":date}},
        "attributes":map[string]any{"source":"vci","route":"company_info"},
    }
    p,_:=json.Marshal(map[string]any{
        "active":true,"at":"2026-10-17T03:20:00+07:00",
        "company_info_symbol":symbol,
        "company_info_frame":frame,
        "routes":map[string]any{"company_info":map[string]any{"available":true,"count":1}},
    })
    return p
}
func TestCompanyInfoProbeSourceSemantics(t *testing.T) {
    for _,date:=range []string{"2018-10-01","2018-10-01T00:00:00+07:00","2018-10-01T00:00:00"}{
        p,err:=ParseCompanyInfoProbe(companyProbeFixture("AAA",date))
        if err!=nil||p.Symbol!="AAA"||p.ReportedListingDate!="2018-10-01"||p.SHA256==""{
            t.Fatalf("parsed %+v error %v",p,err)
        }
    }
    for _,bad:=range []string{"invalid","2018-02-31","2018-10-01Tgarbage"}{
        if _,err:=ParseCompanyInfoProbe(companyProbeFixture("AAA",bad));err==nil{
            t.Fatalf("invalid %s date accepted",bad)
        }
    }
    // A profile date is not a verified initial trading date.
    empty,err:=ParseCompanyInfoProbe(companyProbeFixture("AAA",""))
    if err==nil || empty.ReportedListingDate!=""{
        t.Fatal("empty provider date should not become historical evidence")
    }
    p,err:=ParseCompanyInfoProbe(companyProbeFixture("AAA","2020-02-01"))
    if err!=nil{t.Fatal(err)}
    p.Symbol="BBB"
    if _,err=parseCompanyInfoFrame(p.Raw,p.Symbol);err==nil{
        t.Fatal("swapped symbol accepted")
    }
}

func TestCompanyInfoProbeReportsSavedRouteCause(t *testing.T) {
    raw,_:=json.Marshal(map[string]any{
        "active":true,"at":"2026-10-17T08:32:00+07:00",
        "routes":map[string]any{"company_info":map[string]any{
            "available":false,"count":0,
            "error_type":"AdapterError","error_cause":"AttributeError",
        }},
    })
    _,err:=ParseCompanyInfoProbe(raw)
    if err==nil || !strings.Contains(err.Error(),"AdapterError") ||
        !strings.Contains(err.Error(),"AttributeError"){
        t.Fatalf("lost verified route failure cause: %v",err)
    }
}

// Real saved active probes are written with json.MarshalIndent. Their embedded
// json.RawMessage has whitespace that json.Marshal would erase, changing
// source SHA-256. This regression previously rejected valid ABR profile data.
func TestPrettyPrintedCompanyProfileKeepsOriginalSourceChecksum(t *testing.T){
    compact:=companyProbeFixture("ABR","2018-06-20T00:00:00+07:00")
    var pretty bytes.Buffer
    if err:=json.Indent(&pretty,compact,"","  ");err!=nil{t.Fatal(err)}
    profile,err:=ParseCompanyInfoProbe(pretty.Bytes())
    if err!=nil{t.Fatal(err)}
    if profile.Symbol!="ABR"||profile.ReportedListingDate!="2018-06-20"{
        t.Fatalf("wrong parsed company profile: %+v",profile)
    }
    h:=sha256.Sum256(profile.Raw)
    if profile.SHA256!=hex.EncodeToString(h[:]){t.Fatal("source SHA-256 mismatch")}
    reencoded,err:=json.Marshal(profile.Raw)
    if err!=nil{t.Fatal(err)}
    if bytes.Equal(reencoded,profile.Raw){
        t.Fatal("fixture does not demonstrate whitespace-different source bytes")
    }
    if hash:=sha256.Sum256(reencoded);hash==h {
        t.Fatal("fixture unexpectedly has identical digest after re-encoding")
    }
    date,err:=parseCompanyInfoFrame(profile.Raw,profile.Symbol)
    if err!=nil||date!="2018-06-20"{t.Fatalf("direct source validation: %s %v",date,err)}
    // A caller still cannot forge the extracted date or company identity.
    if _,err:=parseCompanyInfoFrame(profile.Raw,"BAD");err==nil{
        t.Fatal("wrong security identity accepted")
    }
}
