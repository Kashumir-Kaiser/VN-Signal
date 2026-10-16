package ingest

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"database/sql/driver"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
	"testing"
	"time"
)

// This fake provides a real database/sql transaction with a fixed read
// snapshot, making the resume selection executable in standard-library CI.
type universeDriver struct{}
type universeConn struct{ tampered bool }
type universeTx struct{}
type universeRows struct {
	cols    []string
	records [][]driver.Value
	offset  int
}

func (universeDriver) Open(name string) (driver.Conn, error) {
	return &universeConn{tampered: name == "tampered"}, nil
}
func (*universeConn) Prepare(string) (driver.Stmt, error) { return nil, errors.New("not supported") }
func (*universeConn) Close() error                        { return nil }
func (*universeConn) Begin() (driver.Tx, error)           { return universeTx{}, nil }
func (*universeConn) BeginTx(context.Context, driver.TxOptions) (driver.Tx, error) {
	return universeTx{}, nil
}
func (universeTx) Commit() error          { return nil }
func (universeTx) Rollback() error        { return nil }
func (r *universeRows) Columns() []string { return r.cols }
func (r *universeRows) Close() error      { return nil }
func (r *universeRows) Next(dest []driver.Value) error {
	if r.offset >= len(r.records) {
		return io.EOF
	}
	copy(dest, r.records[r.offset])
	r.offset++
	return nil
}
func (c *universeConn) QueryContext(ctx context.Context, query string, _ []driver.NamedValue) (driver.Rows, error) {
	switch {
	case strings.Contains(query, "max(snapshot_date)"):
		return &universeRows{cols: []string{"max"}, records: [][]driver.Value{{"2026-10-16"}}}, nil
	case strings.Contains(query, "count(DISTINCT exchange)"):
		return &universeRows{cols: []string{"count", "active", "matched", "exchanges"}, records: [][]driver.Value{{int64(1002), int64(1002), int64(1002), int64(3)}}}, nil
	case strings.Contains(query, "SELECT payload_bytes,payload_sha256"):
		bytes := []byte(`{"count":1002,"rows":[]}`)
		h := sha256.Sum256(bytes)
		digest := hex.EncodeToString(h[:])
		if c.tampered {
			digest = strings.Repeat("0", 64)
		}
		return &universeRows{cols: []string{"bytes", "sha"}, records: [][]driver.Value{{bytes, digest}}}, nil
	case strings.Contains(query, "COALESCE(j.state,'')"):
		items := make([][]driver.Value, 0, 1002)
		for i := 0; i < 1002; i++ {
			symbol := fmt.Sprintf("X%04d", i)
			state := ""
			var update driver.Value = nil
			if i == 0 {
				state = "COMPLETED"
			}
			if i == 1 {
				state = "BLOCKED"
			}
			if i == 2 {
				state = "RUNNING"
				update = time.Date(2026, 10, 16, 11, 59, 0, 0, time.UTC)
			}
			items = append(items, []driver.Value{symbol, state, update})
		}
		return &universeRows{cols: []string{"symbol", "state", "updated"}, records: items}, nil
	default:
		return nil, fmt.Errorf("unexpected SQL %q", query)
	}
}

func init() { sql.Register("universe-test", universeDriver{}) }
func TestUniverseResumeQueueViaSQL(t *testing.T) {
	db, err := sql.Open("universe-test", "")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	at := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	queue, err := LoadVerifiedBackfillUniverse(context.Background(), db, at, "2018-10-01", "2026-10-16", "vci")
	if err != nil {
		t.Fatal(err)
	}
	if queue.Total != 1002 || queue.Completed != 1 || queue.Blocked != 1 || queue.Leased != 1 || len(queue.Pending) != 999 || queue.Pending[0] != "X0003" {
		t.Fatalf("bad resume queue %+v", queue)
	}
}
func TestUniverseRejectsBadProvenanceViaSQL(t *testing.T) {
	db, err := sql.Open("universe-test", "tampered")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	_, err = LoadVerifiedBackfillUniverse(context.Background(), db, time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC), "2018-10-01", "2026-10-16", "vci")
	if !errors.Is(err, ErrUnverifiedUniverse) {
		t.Fatalf("tampered digest accepted: %v", err)
	}
}