package main

import (
    "context"
    "encoding/json"
    "os"
    "path/filepath"
    "strings"
    "testing"
    "time"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)
func TestProfileBatchArchiveMatchesImporter(t *testing.T){
    raw,_:=json.Marshal(map[string]any{
       "count":1,"columns":[]string{"symbol","name","listing_date"},
       "rows":[]map[string]any{{"symbol":"ABR","name":"ABR","listing_date":"2018-06-12T00:00:00+07:00"}},
       "attributes":map[string]any{"source":"vci","route":"fundamental.company.info"},
    })
    path:=filepath.Join(t.TempDir(),"ABR-00001.json")
    if err:=saveProfileBatchReport(path,"ABR",worker.Response{ID:"profile",OK:true,Data:raw},nil);err!=nil{t.Fatal(err)}
    saved,err:=os.ReadFile(path)
    if err!=nil{t.Fatal(err)}
    p,err:=ingest.ParseCompanyInfoProbe(saved)
    if err!=nil||p.Symbol!="ABR"||p.ReportedListingDate!="2018-06-12"{
        t.Fatalf("failed to re-import saved source: %+v %v",p,err)
    }
}
func TestProfileBatchErrorArchiveExcludesVendorMessage(t *testing.T){
    reason:=worker.Response{ID:"profile",OK:false,Error:&struct{
        Type string `json:"type"`
        Message string `json:"message"`
        Cause string `json:"cause,omitempty"`
    }{Type:"AdapterError",Message:"private vendor secret",Cause:"AttributeError"}}
    path:=filepath.Join(t.TempDir(),"ABR-fail.json")
    if err:=saveProfileBatchReport(path,"ABR",reason,nil);err!=nil{t.Fatal(err)}
    b,err:=os.ReadFile(path)
    if err!=nil{t.Fatal(err)}
    if strings.Contains(string(b),"private vendor secret") || !strings.Contains(string(b),"AttributeError"){
        t.Fatal("incorrect safe error archive")
    }
    if _,err:=ingest.ParseCompanyInfoProbe(b);err==nil{t.Fatal("failed route accepted as positive profile evidence")}
    if profileSafeCause("../secret")!="WorkerFailure"{t.Fatal("bad error cause not sanitized")}
}
func TestProfileBatchCancelledWaitDoesNotDispatch(t *testing.T){
    ctx,cancel:=context.WithCancel(context.Background())
    cancel()
    if err:=awaitProfileDispatch(ctx,time.Now().Add(time.Second));err!=context.Canceled{
        t.Fatalf("cancelled dispatch wait: %v",err)
    }
}
