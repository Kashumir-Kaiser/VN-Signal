package ingest

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"io"
	"strings"
	"testing"
	"time"
)

type guardDriver struct{}
type guardConn struct{ label string }
type guardRows struct {
	values [][]driver.Value
	offset int
}

func (guardDriver) Open(name string) (driver.Conn, error) { return &guardConn{label: name}, nil }
func (c *guardConn) Prepare(string) (driver.Stmt, error)  { return nil, errors.New("not used") }
func (c *guardConn) Close() error                         { return nil }
func (c *guardConn) Begin() (driver.Tx, error)            { return nil, errors.New("not used") }
func (r *guardRows) Columns() []string                    { return []string{"expires_at", "day_key"} }
func (r *guardRows) Close() error                         { return nil }
func (r *guardRows) Next(to []driver.Value) error {
	if r.offset >= len(r.values) {
		return io.EOF
	}
	copy(to, r.values[r.offset])
	r.offset++
	return nil
}
func (c *guardConn) QueryContext(_ context.Context, q string, _ []driver.NamedValue) (driver.Rows, error) {
	if !strings.Contains(q, "FROM ops.quota_guard") {
		return nil, errors.New("unexpected SQL")
	}
	if c.label == "fail" {
		return nil, errors.New("DB connection lost")
	}
	if c.label == "missing" {
		return &guardRows{}, nil
	}
	at := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	exp := at.Add(5 * time.Minute)
	day := "2026-10-16"
	if c.label == "expired" {
		exp = at.Add(-time.Second)
	}
	if c.label == "soon" {
		exp = at.Add(70 * time.Second)
	}
	if c.label == "yesterday" {
		day = "2026-10-15"
	}
	return &guardRows{values: [][]driver.Value{{exp, day}}}, nil
}
func init() { sql.Register("vns-guard-test", guardDriver{}) }
func TestQuotaRefreshRequired(t *testing.T) {
	at := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		label   string
		due     bool
		failure bool
	}{
		{"good", false, false}, {"soon", true, false}, {"expired", true, false},
		{"missing", false, true}, {"yesterday", false, true}, {"fail", false, true},
	} {
		t.Run(tc.label, func(t *testing.T) {
			db, e := sql.Open("vns-guard-test", tc.label)
			if e != nil {
				t.Fatal(e)
			}
			defer db.Close()
			store := &PostgresStore{DB: db, Now: func() time.Time { return at }}
			due, e := store.QuotaRefreshRequired(context.Background(), 90*time.Second)
			if (e != nil) != tc.failure || due != tc.due {
				t.Fatalf("got due=%t err=%v", due, e)
			}
			if tc.label == "missing" && !errors.Is(e, ErrNoQuotaSnapshot) {
				t.Fatal("missing guard must fail closed")
			}
		})
	}
	if _, e := (&PostgresStore{}).QuotaRefreshRequired(context.Background(), 90*time.Second); !errors.Is(e, ErrNoQuotaSnapshot) {
		t.Fatal(e)
	}
	db, _ := sql.Open("vns-guard-test", "good")
	defer db.Close()
	store := &PostgresStore{DB: db, Now: func() time.Time { return at }}
	if _, e := store.QuotaRefreshRequired(context.Background(), 3*time.Minute); !errors.Is(e, ErrNoQuotaSnapshot) {
		t.Fatal("invalid lead accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, e := store.QuotaRefreshRequired(ctx, 90*time.Second); !errors.Is(e, context.Canceled) {
		t.Fatal(e)
	}
}