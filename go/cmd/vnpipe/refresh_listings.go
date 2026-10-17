package main

import (
    "errors"
    "flag"
    "fmt"
    "os"
    "path/filepath"
    "time"
)

// refresh-listings is a deliberately explicit one-call live operation on the
// registered computer. It uses the existing metered probe, writes a unique
// immutable report path, then imports its exact captured VCI bytes into
// PostgreSQL (including the observed DELISTED provider rows).
func runRefreshListings(args []string) error {
    flags:=flag.NewFlagSet("refresh-listings",flag.ContinueOnError)
    active:=flags.Bool("active",false,"explicitly authorize one metered equity_list request")
    days:=flags.Int("trading-days",0,"remaining trading sessions used for quota allocation")
    out:=flags.String("out",filepath.Join("..","docs","probe","refresh"),"parent report directory")
    if err:=flags.Parse(args);err!=nil{return err}
    if len(flags.Args())!=0 || !*active || *days<1 || *days>31 {
        return errors.New("refresh-listings requires --active and --trading-days 1..31")
    }
    // The existing active probe already enforces VNPIPE_DISABLE_LIVE, tier
    // verification, rate pacing and conservative provider-usage checks.
    now:=time.Now().UTC()
    session:=filepath.Join(*out,now.Format("20060102T150405.000000000Z"))
    if err:=os.MkdirAll(session,0700);err!=nil{return err}
    if err:=run([]string{"probe","--active","--routes","equity_list",
        "--trading-days",fmt.Sprint(*days),"--out",session});err!=nil{return err}
    // Resolve the exact file produced by the probe, even across a Vietnam
    // midnight boundary. Failed imports leave the evidence file intact.
    matches,err:=filepath.Glob(filepath.Join(session,"*.json"))
    if err!=nil{return err}
    if len(matches)!=1{return fmt.Errorf("expected exactly one saved active probe, got %d",len(matches))}
    fmt.Printf("Saved unique source report: %s\n",matches[0])
    if err:=runImportListings([]string{"--probe",matches[0]});err!=nil{
        return fmt.Errorf("source report saved but listing import rejected (review the saved evidence; do not overwrite): %w",err)
    }
    return nil
}
