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
    // Batch 5 had five isolated timeouts across 22 calls with successful
    // profiles between them: a 20% rolling-25 failure rate must NOT stop an
    // otherwise healthy vendor route. Those failures stay UNKNOWN and billed.
    var sparse profileFailureCircuit
    for i:=0;i<22;i++{
        fail:=i==0||i==2||i==13||i==18||i==21
        cause:=""
        if fail{cause="WorkerTimeout"}
        if trip:=sparse.record(cause,fail);trip!=""{
            t.Fatalf("five scattered timeouts across 22 requests incorrectly stopped at %d: %s",i,trip)
        }
    }
    // A genuine severe cluster of at least half the last ten requests
    // still halts before consuming more quota.
    var concentrated profileFailureCircuit
    for i:=0;i<10;i++{
        fail:=i%2==0
        cause:=""
        if fail{cause="AdapterError"}
        trip:=concentrated.record(cause,fail)
        if i<8 && trip!=""{t.Fatalf("premature trip at %d: %s",i,trip)}
        if i==8 && trip!="five transient failures within 10 calls"{
            t.Fatalf("cluster circuit should trip at fifth failure: %s",trip)
        }
    }
    var consecutive profileFailureCircuit
    if got:=consecutive.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=consecutive.record("AdapterError",true);got!=""{t.Fatal(got)}
    if got:=consecutive.record("AdapterError",true);got!="three consecutive adapter/transport errors"{
        t.Fatalf("consecutive adapter breaker: %s",got)
    }
}

func TestProfileSymbolTargetingIsStrictAndOffline(t *testing.T){
    for _,tc:=range []string{"A32,,BPW","BPW,BPW","BPW,../../secrets","-1"," "}{
        if _,err:=parseProfileSymbols(tc);err==nil{t.Fatalf("accepted unsafe filter %q",tc)}
    }
    selected,err:=parseProfileSymbols(" bpw, ct5 ")
    if err!=nil||!selected["BPW"]||!selected["CT5"]||len(selected)!=2{
        t.Fatalf("failed normalizing symbols %+v %v",selected,err)
    }
    got,err:=selectProfileSymbols([]string{"A32","BPW","CT5"},selected)
    if err!=nil||len(got)!=2||got[0]!="BPW"||got[1]!="CT5"{
        t.Fatalf("wrong targeted queue: %+v %v",got,err)
    }
    if _,err=selectProfileSymbols([]string{"A32","BPW"},selected);err==nil{
        t.Fatal("selected noneligible ticker must fail before reserving quota")
    }
    all,err:=selectProfileSymbols([]string{"A32","BPW"},nil)
    if err!=nil||len(all)!=2{t.Fatalf("normal queue altered: %v %+v",err,all)}
}
func TestProfileNewVendorExceptionClassDoesNotBypassSafety(t *testing.T){
    response:=worker.Response{ID:"x",OK:false,Error:&struct{
        Type string `json:"type"`
        Message string `json:"message"`
        Cause string `json:"cause,omitempty"`
    }{Type:"AdapterError",Message:"private vendor text",Cause:"VciLegacyProfileFailure"}}
    if reason:=profileExitStatus(response,nil);reason!="AdapterError"{
        t.Fatalf("unknown exception class bypassed fail policy: %s",reason)
    }
    path:=filepath.Join(t.TempDir(),"BPW-archive.json")
    if err:=saveProfileBatchReport(path,"BPW",response,nil);err!=nil{t.Fatal(err)}
    raw,err:=os.ReadFile(path)
    if err!=nil{t.Fatal(err)}
    if strings.Contains(string(raw),"private vendor text"){t.Fatal("private worker message leaked")}
    var data struct{Routes map[string]struct{
        ErrorType string `json:"error_type"`
        ErrorClass string `json:"error_class"`
    } `json:"routes"`}
    if err=json.Unmarshal(raw,&data);err!=nil{t.Fatal(err)}
    observed:=data.Routes["company_info"]
    if observed.ErrorType!="AdapterError"||observed.ErrorClass!="VciLegacyProfileFailure"{
        t.Fatalf("unsafe/uninformative error evidence: %+v",observed)
    }
    if profileSafeCause("../token")!="WorkerFailure"{t.Fatal("unexpected unsafe class accepted")}
}

func TestProfileProviderErrorSafeMetadataArchive(t *testing.T){
    status:=502
    retryable:=false
    resp:=worker.Response{ID:"x",OK:false,Error:&struct{
        Type string `json:"type"`
        Message string `json:"message"`
        Cause string `json:"cause,omitempty"`
    }{Type:"AdapterError",Message:"supersecret vendor payload",Cause:"ProviderError"},
    Diagnostic:&worker.ErrorDiagnostic{Code:"VNSTOCK_SOURCE_NOT_FOUND",
        Kind:"provider",Route:"reference.company.info",Provider:"vci",
        HTTPStatus:&status,Retryable:&retryable}}
    path:=filepath.Join(t.TempDir(),"BPW.json")
    if err:=saveProfileBatchReport(path,"BPW",resp,nil);err!=nil{t.Fatal(err)}
    data,err:=os.ReadFile(path)
    if err!=nil{t.Fatal(err)}
    if strings.Contains(string(data),"supersecret"){t.Fatal("vendor message leaked into persisted failure")}
    var decoded struct{Routes map[string]struct{
        ErrorType string `json:"error_type"`
        ErrorClass string `json:"error_class"`
        Diagnostic struct{
            Code string `json:"code"`
            Kind string `json:"kind"`
            HTTPStatus int `json:"http_status"`
            Retryable *bool `json:"retryable"`
        } `json:"diagnostic"`
    } `json:"routes"`}
    if err:=json.Unmarshal(data,&decoded);err!=nil{t.Fatal(err)}
    observed:=decoded.Routes["company_info"]
    if observed.ErrorType!="AdapterError"||observed.ErrorClass!="ProviderError"||
       observed.Diagnostic.Code!="VNSTOCK_SOURCE_NOT_FOUND"||
       observed.Diagnostic.Kind!="provider"||observed.Diagnostic.HTTPStatus!=502||
       observed.Diagnostic.Retryable==nil||*observed.Diagnostic.Retryable{
        t.Fatalf("invalid safe metadata %+v",observed)
    }
    // Do not accept plausible but non-standard identifiers or injected
    // free-text messages from untrusted worker frames.
    x:=safeProfileDiagnostic(&worker.ErrorDiagnostic{
       Code:"account_5678:private",Kind:"secret=foo",Route:"https://secret/path",
       Provider:"malicious",HTTPStatus:func()*int{n:=999;return &n}(),
    })
    if x!=nil{t.Fatalf("unsafe diagnostic persisted: %+v",x)}
}
