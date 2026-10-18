//go:build postgres_integration

package dq

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestPostgresSelectCrossSourceReplaysAndPersistsExactlyThirty(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL is mandatory for postgres integration")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx := context.Background()
	if err = db.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	var databaseName string
	if err = db.QueryRowContext(ctx, `SELECT current_database()`).Scan(&databaseName); err != nil {
		t.Fatal(err)
	}
	if databaseName != "vnsignal_test" {
		t.Fatalf("refusing fixtures outside disposable vnsignal_test database (connected database %q)", databaseName)
	}
	var day time.Time
	if err = db.QueryRowContext(ctx, `SELECT date '2098-01-01'+n FROM generate_series(0,300) AS g(n)
		WHERE NOT EXISTS (SELECT 1 FROM core.calendar c WHERE c.trade_date IN (date '2098-01-01'+n-1,date '2098-01-01'+n,date '2098-01-01'+n+1))
		AND NOT EXISTS (SELECT 1 FROM core.calendar_overrides o WHERE o.trade_date IN (date '2098-01-01'+n-1,date '2098-01-01'+n,date '2098-01-01'+n+1))
		ORDER BY n LIMIT 1`).Scan(&day); err != nil {
		t.Fatal(err)
	}
	dayText := day.Format("2006-01-02")
	fixture := fmt.Sprintf("%d", time.Now().UnixNano())
	prefix := "DQSEL" + fixture
	if _, err = db.ExecContext(ctx, `INSERT INTO core.calendar_overrides(trade_date,is_session,reason) VALUES($1,true,$2)`, dayText, "synthetic selector integration fixture"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(), `DELETE FROM ops.dq_cross_source_samples WHERE trade_date=$1`, dayText)
		_, _ = db.ExecContext(context.Background(), `DELETE FROM ops.dq_tier_a_symbols WHERE trade_date=$1`, dayText)
		_, _ = db.ExecContext(context.Background(), `DELETE FROM core.bars_daily WHERE symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol LIKE $1)`, prefix+"%")
		_, _ = db.ExecContext(context.Background(), `DELETE FROM core.symbols WHERE symbol LIKE $1`, prefix+"%")
		_, _ = db.ExecContext(context.Background(), `DELETE FROM core.calendar_overrides WHERE trade_date=$1`, dayText)
	})
	insertSymbols := func(start, count int) {
		t.Helper()
		for i := 0; i < count; i++ {
			symbol := fmt.Sprintf("%s%02d", prefix, start+i)
			if _, err := db.ExecContext(ctx, `INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at,active)
				VALUES($1,'HOSE',now(),now(),true)`, symbol); err != nil {
				t.Fatal(err)
			}
			if _, err := db.ExecContext(ctx, `INSERT INTO ops.dq_tier_a_symbols(trade_date,symbol_id)
				SELECT $1::date,symbol_id FROM core.symbols WHERE symbol=$2`, dayText, symbol); err != nil {
				t.Fatal(err)
			}
			if _, err := db.ExecContext(ctx, `INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,traded_value,adj_basis,source,ingest_id,fetched_at)
				SELECT symbol_id,$1::date,10,11,9,10.5,100,1000,'unadjusted','vci',gen_random_uuid(),now()
				FROM core.symbols WHERE symbol=$2`, dayText, symbol); err != nil {
				t.Fatal(err)
			}
			insertLandedSelectorFrame(t, ctx, db, symbol, "vci", "Organisation VCI", dayText, 10.5)
			insertLandedSelectorFrame(t, ctx, db, symbol, "kbs", "Organisation KBS", dayText, 10.5)
		}
	}
	insertSymbols(0, 29)
	if _, err = SelectCrossSourceFromPostgres(ctx, db, day); err == nil {
		t.Fatal("29 candidates unexpectedly materialized")
	}
	var selected int
	if err = db.QueryRowContext(ctx, `SELECT count(*) FROM ops.dq_cross_source_samples WHERE trade_date=$1 AND selected_for_gate`, dayText).Scan(&selected); err != nil || selected != 0 {
		t.Fatalf("incomplete selection wrote rows: selected=%d err=%v", selected, err)
	}
	insertSymbols(29, 1)
	result, err := SelectCrossSourceFromPostgres(ctx, db, day)
	if err != nil || result.Selected != RequiredCrossSourcePairs {
		t.Fatalf("selection result=%+v err=%v", result, err)
	}
	if err = db.QueryRowContext(ctx, `SELECT count(*) FROM ops.dq_cross_source_samples
		WHERE trade_date=$1 AND selected_for_gate`, dayText).Scan(&selected); err != nil || selected != RequiredCrossSourcePairs {
		t.Fatalf("selected rows=%d err=%v", selected, err)
	}
	var minPrimaryRow, minSecondaryRow, missingLineage int
	if err = db.QueryRowContext(ctx, `SELECT min(primary_source_row),min(secondary_source_row),
		count(*) FILTER (WHERE primary_landing_id IS NULL OR secondary_landing_id IS NULL)
		FROM ops.dq_cross_source_samples WHERE trade_date=$1 AND selected_for_gate`, dayText).
		Scan(&minPrimaryRow, &minSecondaryRow, &missingLineage); err != nil {
		t.Fatal(err)
	}
	if minPrimaryRow != 1 || minSecondaryRow != 1 || missingLineage != 0 {
		t.Fatalf("replayed lineage primary=%d secondary=%d missing=%d", minPrimaryRow, minSecondaryRow, missingLineage)
	}
}

func insertLandedSelectorFrame(t *testing.T, ctx context.Context, db *sql.DB, symbol, source, organisation, day string, closeValue float64) {
	t.Helper()
	previous := time.Date(2098, 1, 1, 0, 0, 0, 0, time.UTC)
	parsed, err := time.Parse("2006-01-02", day)
	if err != nil {
		t.Fatal(err)
	}
	previous = parsed.AddDate(0, 0, -1)
	frame := struct {
		Columns    []string                   `json:"columns"`
		Count      int                        `json:"count"`
		Rows       []map[string]any           `json:"rows"`
		Attributes map[string]json.RawMessage `json:"attributes"`
	}{
		Columns: []string{"time", "open", "high", "low", "close", "volume"}, Count: 2,
		Rows: []map[string]any{
			{"time": previous.Format("2006-01-02"), "open": closeValue, "high": closeValue + 1, "low": closeValue - 1, "close": closeValue, "volume": 100},
			{"time": day, "open": closeValue, "high": closeValue + 1, "low": closeValue - 1, "close": closeValue, "volume": 100},
		},
		Attributes: map[string]json.RawMessage{
			"source":       json.RawMessage(fmt.Sprintf(`%q`, source)),
			"organisation": json.RawMessage(fmt.Sprintf(`%q`, organisation)),
			"route":        json.RawMessage(`"market.equity.ohlcv"`),
		},
	}
	raw, err := json.Marshal(frame)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(raw)
	if _, err = db.ExecContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES(gen_random_uuid(),$1,'equity_ohlcv',now(),$2,$3::jsonb,$4,$5)`,
		source, symbol, string(raw), hex.EncodeToString(digest[:]), raw); err != nil {
		t.Fatal(err)
	}
}
