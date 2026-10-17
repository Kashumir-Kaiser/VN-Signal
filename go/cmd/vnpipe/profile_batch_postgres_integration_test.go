//go:build postgres && postgres_integration

package main

import (
    "context"
    "os"
    "strings"
    "testing"
    "time"
)

// Uses the actual openPostgres production factory with MaxOpenConns=1.
// This once deadlocked for five hours immediately after acquiring its
// session-scoped lock, before the first profile request.
func TestProfileBatchSessionLockDoesNotExhaustConnectionPool(t *testing.T) {
    ctx,cancel:=context.WithTimeout(context.Background(),15*time.Second)
    defer cancel()
    db,err:=openPostgres(ctx,os.Getenv("DATABASE_URL"))
    if err!=nil{t.Fatal(err)}
    defer db.Close()
    if actual:=db.Stats().MaxOpenConnections;actual!=1{
        t.Fatalf("expected to reproduce one-connection production default; got %d",actual)
    }
    _,err=profileBatchLock(ctx,db)
    if err==nil||!strings.Contains(err.Error(),"requires >=2 PostgreSQL connections"){
        t.Fatalf("unconfigured pool did not fail immediately: %v",err)
    }
    if err=configureProfileBatchDB(db);err!=nil{t.Fatal(err)}
    if actual:=db.Stats().MaxOpenConnections;actual!=2{
        t.Fatalf("collector pool not expanded: %d",actual)
    }
    unlock,err:=profileBatchLock(ctx,db)
    if err!=nil{t.Fatal(err)}
    defer unlock()
    queryCtx,stop:=context.WithTimeout(ctx,3*time.Second)
    defer stop()
    var count int
    if err=db.QueryRowContext(queryCtx,"SELECT 1").Scan(&count);err!=nil||count!=1{
        t.Fatalf("first DB query starved while lock held (old 5-hour freeze): got=%d err=%v",count,err)
    }
    tx,err:=db.BeginTx(queryCtx,nil)
    if err!=nil{t.Fatalf("importer transaction starved behind lock: %v",err)}
    if err=tx.Rollback();err!=nil{t.Fatal(err)}
}
