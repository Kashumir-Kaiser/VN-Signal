
package main
import (
    "os"
    "path/filepath"
    "strings"
    "testing"
)
func TestUserIgnoreList(t *testing.T){
    path:=filepath.Join("..","..","..","config","ignored_symbols.txt")
    ignored,err:=readIgnoredSymbols(path)
    if err!=nil{t.Fatal(err)}
    expected:=[]string{"BPW","CT5","DKH","DPD","HGA","HGC","IPH","MXC","PYU","T12","TAC","TS5"}
    if len(ignored)!=len(expected){t.Fatalf("expected %d ignored symbols, got %d",len(expected),len(ignored))}
    for _,symbol:=range expected{if !ignored[symbol]{t.Fatalf("missing %s",symbol)}}
    if ignored["FPT"]||ignored["HPG"]{t.Fatal("unexpected blue-chip exclusion")}
    got,skipped:=filterIgnoredSymbols([]string{"BPW","FPT","DPD","HPG","TS5"},ignored)
    if skipped!=3||strings.Join(got,",")!="FPT,HPG"{t.Fatalf("bad skip: %v skipped %d",got,skipped)}
}
func TestIgnoreListRejectsBadInput(t *testing.T){
    for _,raw:=range []string{"BPW\nBPW\n","bpw\n","BPW;FPT\n","../etc\n","FPT HPG\n"}{
        path:=filepath.Join(t.TempDir(),"ignored_symbols.txt")
        if err:=os.WriteFile(path,[]byte(raw),0600);err!=nil{t.Fatal(err)}
        if _,err:=readIgnoredSymbols(path);err==nil{t.Fatalf("accepted bad list %q",raw)}
    }
    if _,err:=readIgnoredSymbols(filepath.Join(t.TempDir(),"missing"));err==nil{t.Fatal("missing list accepted")}
}
