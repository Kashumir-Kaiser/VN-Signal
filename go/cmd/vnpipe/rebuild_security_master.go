package main

import (
    "context"
    "encoding/json"
    "errors"
    "flag"
    "os"
    "time"

    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/config"
    "github.com/Kashumir-Kaiser/VN-Signal/go/internal/ingest"
)

// Imports already stored, checksum-verifiable VCI listing frames. No worker
// calls, no API keys, no spending or refunding provider quota.
func runRebuildSecurityMaster(args []string) error {
    f:=flag.NewFlagSet("rebuild-security-master",flag.ContinueOnError)
    if err:=f.Parse(args);err!=nil{return err}
    if len(f.Args())!=0{return errors.New("rebuild-security-master accepts no arguments")}
    if _,err:=config.Load(configPath());err!=nil{return err}
    ctx,cancel:=context.WithTimeout(context.Background(),5*time.Minute)
    defer cancel()
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{return err}
    defer db.Close()
    store,err:=ingest.NewPostgresStore(db)
    if err!=nil{return err}
    summary,err:=store.RebuildSecurityMaster(ctx)
    if err!=nil{return err}
    return json.NewEncoder(os.Stdout).Encode(summary)
}
