package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestRejectInvalidConfigInCLI(t *testing.T) {
	p := filepath.Join(t.TempDir(), "bad.toml")
	os.WriteFile(p, []byte("[schedule]\ntimezone = \"Bad\"\n"), 0600)
	t.Setenv("VNPIPE_CONFIG", p)
	if e := run([]string{"budget", "--daily=100", "--monthly=100", "--days=2", "--rpm=60"}); e == nil || !strings.Contains(e.Error(), "config") {
		t.Fatal(e)
	}
}
func TestActiveProbeDisabledCI(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	t.Setenv("VNPIPE_CONFIG", filepath.Join("..", "..", "..", "config", "default.toml"))
	if e := run([]string{"probe", "--active", "--trading-days=5"}); e == nil {
		t.Fatal("live probe ran in CI")
	}
}

func TestPercentageUsageStopsActiveProbe(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	t.Setenv("VNPIPE_CONFIG", filepath.Join("..", "..", "..", "config", "default.toml"))
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("python3 unavailable")
	}
	script := filepath.Join(t.TempDir(), "mock_worker.py")
	fixture := `import sys,json
r=json.loads(sys.stdin.readline())
print(json.dumps({"id":r["id"],"ok":True,"data":{"active":False,"status":{"tier":"community"},"usage":{"daily_remaining":"80%","monthly_remaining":"70%"},"routes":{}}}))
`
	if err := os.WriteFile(script, []byte(fixture), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("VNPIPE_PYTHON", py)
	t.Setenv("VNPIPE_WORKER", script)
	output := filepath.Join(t.TempDir(), "report")
	err = run([]string{"probe", "--active", "--trading-days=10", "--out", output})
	if err == nil || !strings.Contains(err.Error(), "quota capacity unknown") {
		t.Fatalf("percent accepted: %v", err)
	}
	if _, err := os.Stat(output); !os.IsNotExist(err) {
		t.Fatal("wrote success report for blocked probe")
	}
}
