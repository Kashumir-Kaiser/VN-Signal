package main

import(
    "context"
    "errors"
    "flag"
    "fmt"
    "os"
    "strings"
    "time"

    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

// This is an offline metadata operation. It only allows an old blocked,
 // unarchived response to be attempted again later via normal guarded backfill.
func runRequeueUnarchived(args []string) error {
    f:=flag.NewFlagSet("requeue-unarchived",flag.ContinueOnError)
    symbol:=f.String("symbol","","verified listed ticker (one at a time)")
    start:=f.String("from","","original history start")
    end:=f.String("to","","original history end")
    source:=f.String("source","vci","original source")
    if err:=f.Parse(args);err!=nil{return err}
    s:=strings.ToUpper(strings.TrimSpace(*symbol))
    if len(f.Args())!=0||s==""||s!=*symbol||len(s)>12||*start==""||*end==""||
        *start>*end||*source!="vci" {
        return errors.New("requeue-unarchived requires --symbol SYMBOL --from DATE --to DATE --source vci")
    }
    for _,r:=range s {
        if !(r>='A'&&r<='Z'||r>='0'&&r<='9') {
            return errors.New("invalid ticker symbol")
        }
    }
    for _,d:=range []string{*start,*end} {
        v,err:=time.Parse("2006-01-02",d)
        if err!=nil||v.Format("2006-01-02")!=d||
            d>time.Now().In(time.FixedZone("Asia/Ho_Chi_Minh",7*3600)).Format("2006-01-02"){
            return errors.New("invalid or future history date")
        }
    }
    if _,err:=config.Load(configPath());err!=nil{return err}
    ctx,cancel:=context.WithTimeout(context.Background(),30*time.Second)
    defer cancel()
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{return err}
    defer db.Close()
    // Confirm existing archive-backed universe before touching a job state.
    if _,err=ingest.LoadVerifiedBackfillUniverse(ctx,db,time.Now(),*start,*end,*source);err!=nil {
        return fmt.Errorf("current source universe not verified: %w",err)
    }
    store,err:=ingest.NewPostgresStore(db)
    if err!=nil{return err}
    if err=store.RequeueUnarchivedLegacy(ctx,s,*start,*end,*source);err!=nil{return err}
    fmt.Printf("Requeued unarchived legacy frame: %s (no vendor calls; no quota refunded; future backfill still requires --active)\n",s)
    return nil
}
