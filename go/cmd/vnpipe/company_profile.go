package main

import (
    "context"
    "encoding/json"
    "errors"
    "flag"
    "fmt"
    "io"
    "os"
    "path/filepath"
    "time"

    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

func runImportCompanyInfo(args []string) error {
    f:=flag.NewFlagSet("import-company-info",flag.ContinueOnError)
    path:=f.String("probe","","saved verified active company_info probe")
    if err:=f.Parse(args);err!=nil{return err}
    if len(f.Args())!=0 || *path==""{
        return errors.New("import-company-info requires --probe FILE")
    }
    file,err:=os.Open(*path)
    if err!=nil{return err}
    defer file.Close()
    b,err:=io.ReadAll(io.LimitReader(file,12*1024*1024+1))
    if err!=nil{return err}
    frame,err:=ingest.ParseCompanyInfoProbe(b)
    if err!=nil{return err}
    ctx,cancel:=context.WithTimeout(context.Background(),time.Minute)
    defer cancel()
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{return err}
    defer db.Close()
    store,err:=ingest.NewPostgresStore(db)
    if err!=nil{return err}
    inserted,err:=store.ImportCompanyInfo(ctx,frame)
    if err!=nil{return err}
    return json.NewEncoder(os.Stdout).Encode(map[string]any{
        "symbol":frame.Symbol,"source":"vci","reported_listing_date":frame.ReportedListingDate,
        "inserted":inserted,
        "date_semantics":"PROVIDER_CURRENT_PROFILE_UNVERIFIED",
    })
}

func runRefreshCompanyInfo(args []string) error {
    f:=flag.NewFlagSet("refresh-company-info",flag.ContinueOnError)
    active:=f.Bool("active",false,"explicit authorization of one company-info vendor call")
    days:=f.Int("trading-days",0,"remaining month trading sessions")
    symbol:=f.String("symbol","","observed equity ticker")
    out:=f.String("out",filepath.Join("..","docs","probe","company"),"unique source report parent")
    if err:=f.Parse(args);err!=nil{return err}
    if !*active || *days<1 || *days>31 || *symbol=="" || len(f.Args())!=0 {
        return errors.New("refresh-company-info requires --active --trading-days 1..31 --symbol TICKER")
    }
    folder:=filepath.Join(*out,time.Now().UTC().Format("20060102T150405.000000000Z"))
    if err:=os.MkdirAll(folder,0700);err!=nil{return err}
    if err:=run([]string{"probe","--active","--routes","company_info",
        "--symbol",*symbol,"--trading-days",fmt.Sprint(*days),"--out",folder});err!=nil{return err}
    reports,err:=filepath.Glob(filepath.Join(folder,"*.json"))
    if err!=nil{return err}
    if len(reports)!=1{return errors.New("expected one persisted company probe report")}
    fmt.Printf("Saved company profile evidence: %s\n",reports[0])
    return runImportCompanyInfo([]string{"--probe",reports[0]})
}
