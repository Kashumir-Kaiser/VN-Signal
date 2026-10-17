package main

import (
    "context"
    "database/sql"
    "encoding/json"
    "errors"
    "flag"
    "fmt"
    "os"
    "path/filepath"
    "regexp"
    "time"

    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
)

var safeProfileCause=regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{0,79}$`)
func profileSafeCause(cause string)string{
    if safeProfileCause.MatchString(cause){return cause}
    return "WorkerFailure"
}
func profileExitStatus(resp worker.Response, err error)string{
    if err!=nil{
        if errors.Is(err,context.DeadlineExceeded){return "WorkerTimeout"}
        if errors.Is(err,context.Canceled){return "WorkerCancelled"}
        if errors.Is(err,quota.ErrExhausted){return "QuotaExhausted"}
        return "WorkerInvocationError"
    }
    if resp.OK{return ""}
    if resp.Error==nil{return "WorkerProtocolError"}
    if resp.Error.Cause!="" && resp.Error.Cause!="UnknownAdapterError" {
        return profileSafeCause(resp.Error.Cause)
    }
    return profileSafeCause(resp.Error.Type)
}

// Distinguish an isolated symbol-level adapter exception from failures
// indicating the whole worker/provider environment is unusable. These
// classifications determine whether the *batch* continues, not whether a
// company has valid listing evidence. Any structured adapter failure remains
// ERROR until a future explicitly authorized retry.
func profileProviderFailureMayContinue(reason string) bool {
    switch reason {
    case "DataUnavailableError", "InputError", "ValueError",
        "AdapterError", "AttributeError", "TypeError", "KeyError",
        "IndexError", "RuntimeError", "ConnectionError", "TimeoutError",
        "HTTPError", "RequestException", "DataSourceError":
        return true
    default:
        // Rate-limit/entitlement, import/configuration, worker-protocol,
        // system exit and any unrecognized error fail closed.
        return false
    }
}

// A request can fail while the rest of a batch remains healthy. Break after
// three consecutive timeouts, three consecutive other worker/adapter errors,
// or five such errors inside the last 25 calls. A healthy or confirmed
// data-unavailable response resets consecutive counts, but not the rolling
// error window. This limits quota spent when an external service degrades.
type profileFailureCircuit struct {
    consecutiveTimeouts int
    consecutiveAdapters int
    recent []bool
}

func (c *profileFailureCircuit) record(reason string, failure bool) string {
    if failure && reason=="WorkerTimeout" {c.consecutiveTimeouts++} else {c.consecutiveTimeouts=0}
    if failure && reason!="WorkerTimeout" {c.consecutiveAdapters++} else {c.consecutiveAdapters=0}
    c.recent=append(c.recent,failure)
    if len(c.recent)>25 {c.recent=c.recent[len(c.recent)-25:]}
    recentFailures:=0
    for _,failed:=range c.recent {if failed {recentFailures++}}
    if c.consecutiveTimeouts>=3 {return "three consecutive worker timeouts"}
    if c.consecutiveAdapters>=3 {return "three consecutive adapter/transport errors"}
    if recentFailures>=5 {return "five transient failures within 25 calls"}
    return ""
}

// A process timeout does NOT establish that VCI rejected the symbol:
// the request may have reached the provider before the worker was killed.
// Record it as UNKNOWN, skip this ticker, and preserve the quota charge.
// Only an actual structured provider reply may be classified as ERROR.
func profileFailedCallDisposition(resp worker.Response,callErr error)(state,reason string,continueBatch bool){
    reason=profileExitStatus(resp,callErr)
    if callErr!=nil {
        return "UNKNOWN",reason,errors.Is(callErr,context.DeadlineExceeded)
    }
    return "ERROR",reason,profileProviderFailureMayContinue(reason)
}

// Each worker call has its own timeout. The batch's five-hour aggregate
// deadline must never replace the subprocess's normal bounded lifetime.
func profileWorkerCall(ctx context.Context,request map[string]any)(worker.Response,error){
    requestCtx,cancel:=context.WithTimeout(ctx,60*time.Second)
    defer cancel()
    return worker.Invoke(requestCtx,worker.Python(),worker.ScriptPath(),request)
}

// Source frames are archived BEFORE the importer or queue status is updated.
// The stored file path is reserved in PostgreSQL ahead of the actual call.
// No network interaction occurs when processing previously archived files.
func saveProfileBatchReport(path,symbol string,resp worker.Response,callErr error)error{
    route:=map[string]any{"available":false}
    report:=map[string]any{
        "active":true,
        "at":time.Now().UTC().Format(time.RFC3339Nano),
        "company_info_symbol":symbol,
    }
    if callErr!=nil{
        route["error_type"]=profileExitStatus(resp,callErr)
    } else if !resp.OK{
        route["error_type"]=profileExitStatus(resp,nil)
    } else {
        report["company_info_frame"]=json.RawMessage(resp.Data)
        var frame struct{
            Count int `json:"count"`
            Columns []string `json:"columns"`
            Attributes map[string]any `json:"attributes"`
        }
        if err:=json.Unmarshal(resp.Data,&frame);err!=nil{
            route["error_type"]="InvalidRouteFrame"
        } else {
            route["count"]=frame.Count
            route["columns"]=frame.Columns
            route["attributes"]=frame.Attributes
            route["available"]=frame.Count==1
            if frame.Count!=1{route["error_type"]="InvalidCompanyInfoCount"}
        }
    }
    report["routes"]=map[string]any{"company_info":route}
    b,err:=json.MarshalIndent(report,"","  ")
    if err!=nil{return err}
    b=append(b,'\n')
    tmp:=path+".tmp"
    f,err:=os.OpenFile(tmp,os.O_WRONLY|os.O_CREATE|os.O_EXCL,0600)
    if err!=nil{return err}
    if _,err=f.Write(b);err!=nil{f.Close();return err}
    if err=f.Sync();err!=nil{f.Close();return err}
    if err=f.Close();err!=nil{return err}
    return os.Rename(tmp,path)
}

func profileResultFromReport(ctx context.Context,store *ingest.PostgresStore,
    path,expectSymbol string)(string,error){
    b,err:=os.ReadFile(path)
    if err!=nil{return "",err}
    p,err:=ingest.ParseCompanyInfoProbe(b)
    if err!=nil{return "",err}
    if p.Symbol!=expectSymbol{return "",errors.New("saved profile belongs to another symbol")}
    _,err=store.ImportCompanyInfo(ctx,p)
    if err!=nil{return "",err}
    if p.ReportedListingDate==""{return "MISSING_DATE",nil}
    return "IMPORTED",nil
}

// Recover only source-backed files explicitly tied to previously reserved
// attempts. An interrupted call without a verifiable frame becomes UNKNOWN;
// it is not retried automatically, even if a prior worker may have billed it.
func recoverProfileAttempts(ctx context.Context,store *ingest.PostgresStore)(int,error){
    attempts,err:=store.UnfinishedProfileAttempts(ctx)
    if err!=nil{return 0,err}
    restored:=0
    for _,a:=range attempts{
        status,err:=profileResultFromReport(ctx,store,a.ReportPath,a.Symbol)
        if err!=nil{
            // A previously failed import can be fixed by new parser code.
            // Re-examine its saved source without spending another API call,
            // but do not turn the prior ERROR into an UNKNOWN failure.
            if a.State=="ERROR"{continue}
            if errors.Is(err,os.ErrNotExist){
                if e:=store.EndProfileCall(ctx,a.ID,"UNKNOWN","InterruptedWithoutSavedResponse");e!=nil{return restored,e}
                continue
            }
            if e:=store.EndProfileCall(ctx,a.ID,"UNKNOWN","UnverifiedSavedResponse");e!=nil{return restored,e}
            continue
        }
        if a.State!="ERROR"{
            if err=store.EndProfileCall(ctx,a.ID,status,"");err!=nil{return restored,err}
        }
        // A saved response from a former import error has now been safely
        // projected into raw/core. SeedProfileQueue reconciles its state.
        restored++
    }
    return restored,nil
}

func awaitProfileDispatch(ctx context.Context,at time.Time)error{
    delay:=time.Until(at)
    if delay<=0{return ctx.Err()}
    timer:=time.NewTimer(delay)
    defer timer.Stop()
    select{case <-timer.C:return ctx.Err();case <-ctx.Done():return ctx.Err()}
}

// openPostgres intentionally defaults to ONE connection for ordinary
// ingestion. A session-level advisory lock pins that connection until the
// batch ends; without another connection, the first queue query deadlocks
// waiting for the 5-hour command context. Only this batch uses two connections.
// All profile vendor calls remain strictly serial and quota-metered.
func configureProfileBatchDB(db *sql.DB) error {
    if db == nil {return errors.New("PostgreSQL required")}
    db.SetMaxOpenConns(2)
    db.SetMaxIdleConns(2)
    return nil
}

// The batch lock is session-scoped. It prevents two copies of this collector
// from racing in parallel, while the existing quota_guard row serializes
// allowances and pacing with the OHLCV backfill process.
func profileBatchLock(ctx context.Context,db *sql.DB)(func(),error){
    if db==nil {return nil,errors.New("PostgreSQL required")}
    if max:=db.Stats().MaxOpenConnections;max>0 && max<2 {
        return nil,fmt.Errorf("company profile batch requires >=2 PostgreSQL connections (one pinned for its advisory lock); configured max=%d",max)
    }
    conn,err:=db.Conn(ctx)
    if err!=nil{return nil,err}
    var locked bool
    err=conn.QueryRowContext(ctx,`SELECT pg_try_advisory_lock(2108701,2602)`).Scan(&locked)
    if err!=nil{conn.Close();return nil,err}
    if !locked{conn.Close();return nil,errors.New("another company profile batch already holds the database lock")}
    return func(){
        releaseCtx,cancel:=context.WithTimeout(context.Background(),5*time.Second)
        defer cancel()
        _,_=conn.ExecContext(releaseCtx,`SELECT pg_advisory_unlock(2108701,2602)`)
        _=conn.Close()
    },nil
}

// runProfileBatch collects real, registered vnstock v5 Community VCI metadata.
// It has no hosted/background scheduler. Each call is opt-in, database metered,
// source-archived and resumable on the user's actual Windows computer.
func runProfileBatch(args []string)(retErr error){
    f:=flag.NewFlagSet("collect-company-profiles",flag.ContinueOnError)
    active:=f.Bool("active",false,"authorize real metered VCI company_info requests")
    days:=f.Int("trading-days",0,"remaining trading sessions in account quota month")
    maxCalls:=f.Int("max-calls",50,"maximum attempted API calls in this invocation")
    retryErrors:=f.Bool("retry-errors",false,"retry previously failed provider calls (additional quota)")
    retryUnknown:=f.Bool("retry-unknown",false,"explicitly allow repeating uncertain, possibly billed calls")
    out:=f.String("out",filepath.Join("..","docs","probe","company","batch"),"archive directory for source reports")
    if err:=f.Parse(args);err!=nil{return err}
    if len(f.Args())!=0||!*active||*days<1||*days>31||*maxCalls<1||*maxCalls>100000{
        return errors.New("collect-company-profiles requires --active --trading-days 1..31 and --max-calls 1..100000")
    }
    if os.Getenv("VNPIPE_DISABLE_LIVE")=="1"{return live.ErrDisabled}
    if _,err:=config.Load(configPath());err!=nil{return err}
    absOut,err:=filepath.Abs(*out)
    if err!=nil{return err}
    if err:=os.MkdirAll(absOut,0700);err!=nil{return err}
    ctx,cancel:=context.WithTimeout(context.Background(),5*time.Hour)
    defer cancel()
    fmt.Fprintln(os.Stdout,"Profile batch: opening PostgreSQL (no vendor calls yet)")
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{return err}
    defer db.Close()
    // openPostgres normally caps connections at one. Do not hold that sole
    // connection for a long-lived session advisory lock.
    if err=configureProfileBatchDB(db);err!=nil{return err}
    fmt.Fprintln(os.Stdout,"Profile batch: acquiring single-run advisory lock")
    lockCtx,lockCancel:=context.WithTimeout(ctx,10*time.Second)
    defer lockCancel()
    unlock,err:=profileBatchLock(lockCtx,db)
    if err!=nil{return err}
    defer unlock()
    store,err:=ingest.NewPostgresStore(db)
    if err!=nil{return err}
    fmt.Fprintln(os.Stdout,"Profile batch: loading queue and recovering archived responses (offline)")
    setupCtx,setupCancel:=context.WithTimeout(ctx,30*time.Second)
    defer setupCancel()
    if err=store.SeedProfileQueue(setupCtx);err!=nil{return fmt.Errorf("seed profile queue: %w",err)}
    corrected,err:=store.ReclassifyLegacyProfileTimeouts(setupCtx)
    if err!=nil{return fmt.Errorf("reclassify legacy uncertain timeouts: %w",err)}
    if corrected>0 {fmt.Fprintf(os.Stdout,"Profile batch: reclassified %d previous WorkerTimeout results as UNKNOWN (no retry)\n",corrected)}
    restored,err:=recoverProfileAttempts(setupCtx,store)
    if err!=nil{return err}
    if err=store.SeedProfileQueue(setupCtx);err!=nil{return err}
    candidates,err:=store.ProfileQueue(setupCtx)
    if err!=nil{return err}
    summary:=ingest.ProfileBatchSummary{Candidates:len(candidates),MaxCalls:*maxCalls}
    eligible:=make([]string,0,len(candidates))
    for _,r:=range candidates{
        switch r.State{
        case "PENDING":eligible=append(eligible,r.Symbol)
        case "ERROR":
            if *retryErrors{eligible=append(eligible,r.Symbol)}else{summary.SkippedErrors++}
        case "UNKNOWN":
            if *retryUnknown{eligible=append(eligible,r.Symbol)}else{summary.SkippedUnknown++}
        case "IMPORTED","MISSING_DATE":summary.SkippedExisting++
        case "IN_FLIGHT":summary.SkippedUnknown++
        default:return fmt.Errorf("invalid database profile state %q",r.State)
        }
    }
    id,err:=store.StartProfileBatch(ctx,*maxCalls)
    if err!=nil{return err}
    summary.BatchID=id
    defer func(){
        summary.Deferred=len(eligible)-summary.Attempted
        finishCtx,finishCancel:=context.WithTimeout(context.Background(),10*time.Second)
        defer finishCancel()
        if e:=store.FinishProfileBatch(finishCtx,summary);e!=nil && retErr==nil{retErr=e}
        fmt.Fprintf(os.Stdout,"Recovered saved profiles: %d\n",restored)
        _=json.NewEncoder(os.Stdout).Encode(summary)
    }()
    fmt.Fprintf(os.Stdout,"Profile batch: %d securities, %d pending/retryable, %d already archived, %d skipped errors, %d skipped unknowns; recovered=%d\n",
        len(candidates),len(eligible),summary.SkippedExisting,summary.SkippedErrors,summary.SkippedUnknown,restored)
    if len(eligible)==0{return nil}
    fmt.Fprintln(os.Stdout,"Profile batch: checking registered vnstock allowance (no market-data call)")
    // Passive CLI usage is FREE of market-data calls, and reading it
    // confirms authenticated tier, absolute daily/monthly quota and RPM.
    quotaSnap,err:=observeAbsoluteQuota(ctx,*days,func(ctx context.Context,req map[string]any)(worker.Response,error){
        return profileWorkerCall(ctx,req)
    })
    if err!=nil{summary.LastErrorType="QuotaPreflight";return err}
    budget,err:=quota.Budget(quotaSnap.DailyRemaining,quotaSnap.MonthlyRemaining,*days)
    if err!=nil{summary.LastErrorType="QuotaPreflight";return err}
    if budget==0{summary.LastErrorType="QuotaExhausted";return quota.ErrExhausted}
    if err=store.InstallQuota(ctx,quotaSnap);err!=nil{
        summary.LastErrorType="QuotaInstall";return err
    }
    pacer,err:=quota.NewPacer(quotaSnap.VerifiedRPM,budget)
    if err!=nil{return err}
    gateway,err:=live.New(pacer,func(ctx context.Context,req map[string]any)(worker.Response,error){
        return profileWorkerCall(ctx,req)
    })
    if err!=nil{return err}
    quotaReader:=func(ctx context.Context)(ingest.QuotaSnapshot,error){
        return observeAbsoluteQuota(ctx,*days,func(ctx context.Context,req map[string]any)(worker.Response,error){
            return profileWorkerCall(ctx,req)
        })
    }
    count:=min(len(eligible),*maxCalls,budget)
    var failureCircuit profileFailureCircuit
    fmt.Fprintf(os.Stdout,"Profile batch: up to %d metered VCI calls (max requested=%d; verified budget=%d; RPM=%d)\n",
        count,*maxCalls,budget,quotaSnap.VerifiedRPM)
    for _,symbol:=range eligible[:count]{
        fmt.Fprintf(os.Stdout,"Profile batch: starting %s (%d/%d), verifying quota\n",symbol,summary.Attempted+1,count)
        if err=ensureFreshQuota(ctx,store,quotaSnap.VerifiedRPM,quotaReader);err!=nil{
            summary.LastErrorType="QuotaRefresh";return err
        }
        attempt,when,e:=store.ReserveProfileCall(ctx,symbol,absOut,*retryErrors,*retryUnknown)
        if e!=nil{
            summary.LastErrorType="QuotaOrReservation"
            return fmt.Errorf("profile %s reservation failed: %w",symbol,e)
        }
        summary.Attempted++
        fmt.Fprintf(os.Stdout,"Profile batch: reserved %s attempt=%d; dispatch after %s\n",
            symbol,attempt.ID,when.In(time.FixedZone("ICT",7*3600)).Format("15:04:05 MST"))
        // The durable reservation exists before any possible vendor call.
        if err=awaitProfileDispatch(ctx,when);err!=nil{
            if e=store.EndProfileCall(context.Background(),attempt.ID,"UNKNOWN","CancelledBeforeWorker");e!=nil{return e}
            summary.Errors++
            summary.LastErrorType="CancelledBeforeWorker"
            return err
        }
        req:=map[string]any{"id":fmt.Sprintf("profile-%d",attempt.ID),
            "op":"company_info","symbol":symbol,"source":"vci"}
        reply,callErr:=gateway.Call(ctx,req)
        fmt.Fprintf(os.Stdout,"Profile batch: %s worker completed (ok=%v); preserving response\n",symbol,reply.OK && callErr==nil)
        if saveErr:=saveProfileBatchReport(attempt.ReportPath,symbol,reply,callErr);saveErr!=nil{
            // The vendor may already have charged the call. Do not retry it.
            summary.Errors++
            summary.LastErrorType="SourceArchiveFailed"
            return fmt.Errorf("unable to archive %s source result: %w",symbol,saveErr)
        }
        if callErr!=nil||!reply.OK{
            state,reason,canContinue:=profileFailedCallDisposition(reply,callErr)
            // The original request already has a durable reservation and
            // its failed worker envelope has been archived. This transition
            // never refunds or automatically repeats the potentially billed call.
            finishCtx,finishCancel:=context.WithTimeout(context.Background(),10*time.Second)
            e=store.EndProfileCall(finishCtx,attempt.ID,state,reason)
            finishCancel()
            if e!=nil{return fmt.Errorf("persist outcome %s %s: %w",symbol,state,e)}
            summary.Errors++
            summary.LastErrorType=reason
            fmt.Fprintf(os.Stdout,"Profile batch: %s %s (%s); evidence saved; no automatic retry\n",
                symbol,state,reason)
            // Data-unavailable is an explicit per-security response; its
            // outcome stays ERROR for audit but is not a systemic failure.
            transient:=reason!="DataUnavailableError" && reason!="InputError" &&
                reason!="ValueError"
            trip:=failureCircuit.record(reason,transient)
            if !canContinue || ctx.Err()!=nil {
                return fmt.Errorf("profile %s outcome=%s cause=%s; evidence=%s (batch stopped to avoid further quota spending)",
                    symbol,state,reason,attempt.ReportPath)
            }
            if trip!="" {
                return fmt.Errorf("profile batch circuit breaker: %s; last symbol=%s cause=%s evidence=%s",
                    trip,symbol,reason,attempt.ReportPath)
            }
            continue
        }
        failureCircuit.record("",false)
        status,importErr:=profileResultFromReport(ctx,store,attempt.ReportPath,symbol)
        if importErr!=nil{
            // A schema/import regression affects every remaining symbol.
            // Stop rather than burn the whole verified API allowance.
            if e=store.EndProfileCall(ctx,attempt.ID,"ERROR","ProfileValidationOrImport");e!=nil{return e}
            summary.Errors++
            summary.LastErrorType="ProfileValidationOrImport"
            return fmt.Errorf("profile %s validation/import failed; archived at %s: %w",
                symbol,attempt.ReportPath,importErr)
        }
        if e=store.EndProfileCall(ctx,attempt.ID,status,"");e!=nil{return e}
        if status=="MISSING_DATE"{summary.MissingDate++}else{summary.Imported++}
        fmt.Fprintf(os.Stdout,"Profile saved and imported: %s (%s)\n",symbol,status)
    }
    return nil
}

// Read-only status of durable queue and source-backed OHLCV coverage flags.
func runProfileStatus(args []string)error{
    f:=flag.NewFlagSet("company-profile-status",flag.ContinueOnError)
    limit:=f.Int("limit",20,"number of interesting coverage rows to preview")
    if err:=f.Parse(args);err!=nil{return err}
    if len(f.Args())!=0||*limit<1||*limit>200{return errors.New("company-profile-status requires --limit 1..200")}
    ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
    defer cancel()
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{return err}
    defer db.Close()
    rows,err:=db.QueryContext(ctx,`SELECT symbol,profile_job_state,
       reported_listing_date::text,first_traded_bar::text,source_zero_unverified,
       to_json(review_flags)::text FROM ops.company_profile_coverage_review
       ORDER BY CASE WHEN 'ZERO_VOLUME_LIFECYCLE_UNVERIFIED'=ANY(review_flags) THEN 0 ELSE 1 END,
          source_zero_unverified DESC,symbol LIMIT $1`,*limit)
    if err!=nil{return err}
    defer rows.Close()
    result:=[]map[string]any{}
    for rows.Next(){
        var sym,state string
        var listing,first sql.NullString
        var z int64
        var rawFlags string
        if err:=rows.Scan(&sym,&state,&listing,&first,&z,&rawFlags);err!=nil{return err}
        var flags []string
        if err:=json.Unmarshal([]byte(rawFlags),&flags);err!=nil{return err}
        result=append(result,map[string]any{
            "symbol":sym,"state":state,"reported_listing_date":listing.String,
            "first_traded_bar":first.String,"source_zero_unverified":z,
            "flags":flags})
    }
    if err=rows.Err();err!=nil{return err}
    return json.NewEncoder(os.Stdout).Encode(result)
}
