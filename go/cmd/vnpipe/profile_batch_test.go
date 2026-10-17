package main

import (
    "context"
    "errors"
    "fmt"
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

func TestProfileTimeoutIsUncertainAndSkippable(t *testing.T){
    state,reason,continueBatch:=profileFailedCallDisposition(
        worker.Response{},fmt.Errorf("timed out: %w",context.DeadlineExceeded))
    if state!="UNKNOWN"||reason!="WorkerTimeout"||!continueBatch{
        t.Fatalf("timeout must skip, not fail batch: state=%s reason=%s continue=%t",state,reason,continueBatch)
    }
    state,reason,continueBatch=profileFailedCallDisposition(
        worker.Response{},fmt.Errorf("cancelled: %w",context.Canceled))
    if state!="UNKNOWN"||reason!="WorkerCancelled"||continueBatch{
        t.Fatalf("outer cancellation must stop: %s %s %v",state,reason,continueBatch)
    }
    state,reason,continueBatch=profileFailedCallDisposition(
        worker.Response{},errors.New("unknown worker failure"))
    if state!="UNKNOWN"||reason!="WorkerInvocationError"||continueBatch{
        t.Fatalf("transport failure must fail closed: %s %s %v",state,reason,continueBatch)
    }
    var circuit profileFailureCircuit
    if circuit.record("WorkerTimeout",true)!="" {t.Fatal("first timeout prematurely trips")}
    if circuit.record("",false)!="" {t.Fatal("success must reset consecutive timeout count")}
    if circuit.record("WorkerTimeout",true)!="" {t.Fatal("second isolated timeout prematurely trips")}
    if circuit.record("WorkerTimeout",true)!="" {t.Fatal("still only two consecutive timeouts")}
    if got:=circuit.record("WorkerTimeout",true);got!="three consecutive worker timeouts" {
        t.Fatalf("timeout breaker failed: %s",got)
    }
}
func TestProfileStructuredProviderErrorsAreDistinct(t *testing.T){
    newResp:=func(cause string)worker.Response{
        return worker.Response{ID:"x",OK:false,Error:&struct{
            Type string `json:"type"`
            Message string `json:"message"`
            Cause string `json:"cause,omitempty"`
        }{Type:cause,Message:"redacted"}}
    }
    for _,tc:=range []struct{
        name,expectedState string
        canContinue bool
    }{
        {"DataUnavailableError","ERROR",true},
        {"InputError","ERROR",true},
        {"RateLimitedError","ERROR",false},
        {"AttributeError","ERROR",true},
        {"AdapterError","ERROR",true},
        {"ModuleNotFoundError","ERROR",false},
        {"ImportError","ERROR",false},
        {"WorkerSystemExit","ERROR",false},
    }{
        state,reason,cont:=profileFailedCallDisposition(newResp(tc.name),nil)
        if state!=tc.expectedState||reason!=tc.name||cont!=tc.canContinue{
            t.Fatalf("%s: got state=%s reason=%s continue=%v",tc.name,state,reason,cont)
        }
    }
}

func TestProfileCircuitBreaksRepeatedAdapterFailuresNotSingleTicker(t *testing.T){
    var c profileFailureCircuit
    if got:=c.record("AdapterError",true);got!=""{t.Fatalf("single failed symbol stopped batch: %s",got)}
    if got:=c.record("",false);got!=""{t.Fatal(got)}
    if got:=c.record("AttributeError",true);got!=""{t.Fatal(got)}
    if got:=c.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=c.record("",false);got!=""{t.Fatal(got)}
    if got:=c.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=c.record("",false);got!=""{t.Fatal(got)}
    if got:=c.record("AdapterError",true);got!="five transient failures within 25 calls"{
        t.Fatalf("clustered adapter failures did not stop batch: %s",got)
    }
    var consecutive profileFailureCircuit
    if got:=consecutive.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=consecutive.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=consecutive.record("AdapterError",true);got!="three consecutive adapter/transport errors"{
        t.Fatalf("consecutive adapter breaker: %s",got)
    }
}
