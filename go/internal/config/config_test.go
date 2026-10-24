package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func source(t *testing.T) string {
	t.Helper()
	b, e := os.ReadFile(filepath.Join("..", "..", "..", "config", "default.toml"))
	if e != nil {
		t.Fatal(e)
	}
	return string(b)
}
func loadText(t *testing.T, s string) error {
	t.Helper()
	p := filepath.Join(t.TempDir(), "conf.toml")
	if e := os.WriteFile(p, []byte(s), 0600); e != nil {
		t.Fatal(e)
	}
	_, e := Load(p)
	return e
}
func TestDefaultConfig(t *testing.T) {
	if e := loadText(t, source(t)); e != nil {
		t.Fatal(e)
	}
}
func TestInvalidConfig(t *testing.T) {
	s := source(t)
	for _, tc := range []struct{ old, new string }{
		{"risk_off_gross_cap = 0.50", "risk_off_gross_cap = 5.0"},
		{"HOSE = 0.07", "HOSE = -2.0"},
		{"Asia/Ho_Chi_Minh", "Invalid/Timezone"},
		{"max_positions = 15", "max_positions = 500"},
		{"investable_n = 400", "investable_n = oops"},
		{"entry_ceiling_weight = 0.0", "entry_ceiling_weight = NaN"},
		{"multiple_locked_weight = 0.5", "multiple_locked_weight = +Inf"},
		{"entry_ceiling_weight = 0.0", "entry_ceiling_weight = -0.1"},
		{"multiple_locked_weight = 0.5", "multiple_locked_weight = 1.1"},
		{"max_weight = 0.12", ""},
		{"timezone = \"Asia/Ho_Chi_Minh\"", "timezone = unquoted"},
		{"[portfolio]", "[portfolio]\nfoo = 1"},
		{"[schedule]", "[schedule]\n[schedule]"},
	} {
		if e := loadText(t, strings.Replace(s, tc.old, tc.new, 1)); e == nil {
			t.Errorf("accepted invalid %q -> %q", tc.old, tc.new)
		}
	}
}
