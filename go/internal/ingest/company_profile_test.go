package ingest

import (
    "encoding/json"
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
    if _,err=ParseCompanyInfoProbe(mustMarshalProfileProbe(p));err==nil{
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
