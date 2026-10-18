package migrate

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSplitterPreservesPLpgSQLAndQuotedSemicolons(t *testing.T) {
	sql := `-- header; ignored
      BEGIN; CREATE FUNCTION foo() RETURNS void AS $$ BEGIN RAISE NOTICE 'hello; world'; END; $$ LANGUAGE plpgsql;
      /* block ; */ INSERT INTO bar VALUES ('semi;colon', 'it''s ok'); COMMIT;`
	got, err := Split(sql)
	if err != nil || len(got) != 4 {
		t.Fatalf("got=%q error=%v", got, err)
	}
	if !strings.Contains(got[1], "RAISE NOTICE 'hello; world'; END;") {
		t.Fatal("split inside dollar quotation")
	}
	if !strings.Contains(got[2], "'it''s ok'") {
		t.Fatal("split inside escaped string")
	}
}
func TestSplitActualMigrations(t *testing.T) {
	for _, name := range []string{"001_init.sql", "002_ingest_state.sql", "003_quota_guard.sql", "016_raw_landings_append_only.sql", "018_bar_quality_reprocess_audit.sql", "019_vietnam_auction_ohlc.sql"} {
		data, err := os.ReadFile(filepath.Join("..", "..", "..", "sql", "migrations", name))
		if err != nil {
			t.Fatal(err)
		}
		stmts, err := Split(string(data))
		if err != nil || len(stmts) < 3 {
			t.Fatalf("%s %d statements: %v", name, len(stmts), err)
		}
		if strings.TrimSpace(stmts[0]) != "BEGIN" || strings.TrimSpace(stmts[len(stmts)-1]) != "COMMIT" {
			t.Fatalf("%s lost transaction boundary: %q .. %q", name, stmts[0], stmts[len(stmts)-1])
		}
	}
}
func TestBadSQLRefused(t *testing.T) {
	for _, sample := range []string{"SELECT 'oops;", "SELECT $$unterminated;", "/* unclosed"} {
		if _, e := Split(sample); e == nil {
			t.Fatalf("accepted %s", sample)
		}
	}
}
