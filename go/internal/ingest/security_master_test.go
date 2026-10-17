package ingest

import (
 "encoding/json"
 "testing"
)

// Parse all classifications from one complete frame. DELISTED is an observed
// category with no asserted former exchange or effective delisting date.
func TestParseFullSecurityListing(t *testing.T) {
    data,err:=json.Marshal(map[string]any{
        "columns":[]string{"symbol","exchange","organ_name","organ_short_name","icb_code_lv2"},
        "count":4,
        "rows":[]map[string]any{
            {"symbol":"AAA","exchange":"HOSE","organ_name":"A","organ_short_name":"A","icb_code_lv2":"1000"},
            {"symbol":"BBB","exchange":"HNX","organ_name":"B","organ_short_name":"B","icb_code_lv2":"2000"},
            {"symbol":"CCC","exchange":"UPCOM","organ_name":"C","organ_short_name":"C","icb_code_lv2":"3000"},
            {"symbol":"OLD","exchange":"DELISTED","organ_name":"Earlier firm","organ_short_name":"OLD","icb_code_lv2":nil},
        },
        "attributes":map[string]any{"source":"vci"},
    })
    if err!=nil{t.Fatal(err)}
    all,err:=ParseFullSecurityListing(data)
    if err!=nil||len(all)!=4{t.Fatalf("%+v %v",all,err)}
    if all[3].Symbol!="OLD"||all[3].Category!="PROVIDER_DELISTED_UNDATED"||
        all[3].Exchange!=""||all[3].Name!="Earlier firm"{
        t.Fatalf("invented old exchange or dropped provider symbol: %+v",all[3])
    }
    // Schema tampering must never become historical master evidence.
    data[0]='!'
    if _,err:=ParseFullSecurityListing(data);err==nil{
        t.Fatal("accepted corrupted listing frame")
    }
}
