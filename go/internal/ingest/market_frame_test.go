package ingest

import (
    "strings"
    "testing"
)

func TestAnalyzeMarketBarsZeroVolumeAndTradedAnomaly(t *testing.T) {
    src := payload(`[
      {"time":"2019-01-10","open":3.76,"high":3.38,"low":3.38,"close":3.38,"volume":0},
      {"time":"2019-01-11","open":10,"high":11,"low":9,"close":10.5,"volume":100},
      {"time":"2019-01-14","open":10,"high":9,"low":8,"close":9,"volume":100},
      {"time":"2019-01-15","open":10,"high":10,"low":10,"close":10,"volume":0}
    ]`,4)
    got,err:=AnalyzeMarketBars("ABR",src)
    if err!=nil{t.Fatal(err)}
    if got.SourceRows!=4 || got.Bars.Count!=1 || got.NonTrading!=2 || got.InvalidTraded!=1 ||
        len(got.Issues)!=3 || got.Issues[0].Category!="NO_TRADE" ||
        got.Issues[1].Category!="INVALID_OHLC" || got.Issues[1].Date!="2019-01-14" ||
        got.FirstDate!="2019-01-10" || got.LastDate!="2019-01-15" {
        t.Fatalf("unreconciled classifications: %+v",got)
    }
    if got.Bars.Rows[0].Date!="2019-01-11" || got.Bars.Rows[0].Volume!=100 {
        t.Fatal("invalid or nontraded price entered canonical set")
    }
    if _,err=NormalizeBars("ABR",src);err==nil {t.Fatal("strict validator should remain strict")}
}
func TestAnalyzeMarketBarsNoTradeOnlyAndRejectsUnreliableFrameShape(t *testing.T){
    valid:=payload(`[{"time":"2019-01-10","open":0,"high":0,"low":0,"close":0,"volume":0}]`,1)
    r,err:=AnalyzeMarketBars("ACE",valid)
    if err!=nil||r.Bars.Count!=0||r.NonTrading!=1||r.InvalidTraded!=0{t.Fatalf("%+v %v",r,err)}
    for _,bad:=range [][]byte{
        []byte(strings.Replace(string(valid),`"count":1`,`"count":2`,1)),
        payload(`[{"time":"2019-01-10","open":1,"high":1,"low":1,"close":1,"volume":100},
                 {"time":"2019-01-10","open":1,"high":1,"low":1,"close":1,"volume":100}]`,2),
        []byte(`{"bad":true}`),
    }{
        if _,err:=AnalyzeMarketBars("ACE",bad);err==nil{t.Fatal("accepted invalid frame structure")}
    }
}
