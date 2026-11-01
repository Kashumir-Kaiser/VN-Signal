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

type quotaBudgetDriver struct{}
type quotaBudgetConn struct{ mode string }
type quotaBudgetRows struct {
	values [][]driver.Value
	offset int
}

func (quotaBudgetDriver) Open(name string) (driver.Conn, error) {
	return &quotaBudgetConn{mode: name}, nil
}
func (c *quotaBudgetConn) Prepare(string) (driver.Stmt, error) { return nil, errors.New("not used") }
func (c *quotaBudgetConn) Close() error                        { return nil }
func (c *quotaBudgetConn) Begin() (driver.Tx, error)           { return nil, errors.New("not used") }
func (quotaBudgetRows) Columns() []string {
	return []string{"expires_at", "day_key", "call_budget", "spent"}
}
func (r *quotaBudgetRows) Close() error { return nil }
func (r *quotaBudgetRows) Next(to []driver.Value) error {
	if r.offset >= len(r.values) {
		return io.EOF
	}
	copy(to, r.values[r.offset])
	r.offset++
	return nil
}
func (c *quotaBudgetConn) QueryContext(_ context.Context, query string, _ []driver.NamedValue) (driver.Rows, error) {
	if !strings.Contains(query, "FROM ops.quota_guard") || !strings.Contains(query, "call_budget") {
		return nil, errors.New("unexpected quota budget query")
	}
	if c.mode == "error" {
		return nil, errors.New("database unavailable")
	}
	if c.mode == "missing" {
		return &quotaBudgetRows{}, nil
	}
	expires := time.Date(2026, 10, 16, 12, 5, 0, 0, time.UTC)
	day := "2026-10-16"
	budget, spent := int64(12), int64(5)
	switch c.mode {
	case "expired":
		expires = time.Date(2026, 10, 16, 11, 59, 0, 0, time.UTC)
	case "wrong-day":
		day = "2026-10-15"
	case "invalid-spent":
		spent = 13
	case "negative-budget":
		budget = -1
	}
	return &quotaBudgetRows{values: [][]driver.Value{{expires, day, budget, spent}}}, nil
}

func init() { sql.Register("vns-quota-budget-test", quotaBudgetDriver{}) }

func TestAvailableQuotaBudgetRequiresFreshValidGuard(t *testing.T) {
	at := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	for _, tc := range []struct {
		mode    string
		want    int
		failure bool
	}{
		{"valid", 7, false}, {"expired", 0, true}, {"wrong-day", 0, true},
		{"invalid-spent", 0, true}, {"negative-budget", 0, true}, {"missing", 0, true}, {"error", 0, true},
	} {
		t.Run(tc.mode, func(t *testing.T) {
			db, err := sql.Open("vns-quota-budget-test", tc.mode)
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			store := &PostgresStore{DB: db, Now: func() time.Time { return at }}
			got, err := store.AvailableQuotaBudget(context.Background())
			if (err != nil) != tc.failure || got != tc.want {
				t.Fatalf("remaining=%d err=%v, want %d failure=%t", got, err, tc.want, tc.failure)
			}
			if tc.mode == "missing" && !errors.Is(err, ErrNoQuotaSnapshot) {
				t.Fatalf("missing guard must fail closed: %v", err)
			}
		})
	}
	if _, err := (&PostgresStore{}).AvailableQuotaBudget(context.Background()); !errors.Is(err, ErrNoQuotaSnapshot) {
		t.Fatalf("nil store did not fail closed: %v", err)
	}
}
