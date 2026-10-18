package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func pythonForTest(t *testing.T) string {
	t.Helper()
	if p := os.Getenv("VNPIPE_PYTHON"); p != "" {
		return p
	}
	name := "python3"
	if runtime.GOOS == "windows" {
		name = "python"
	}
	p, err := exec.LookPath(name)
	if err != nil {
		t.Skipf("Python interpreter %q unavailable; set VNPIPE_PYTHON", name)
	}
	return p
}

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
	py := pythonForTest(t)
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
	err := run([]string{"probe", "--active", "--trading-days=10", "--out", output})
	if err == nil || !strings.Contains(err.Error(), "quota capacity unknown") {
		t.Fatalf("percent accepted: %v", err)
	}
	if _, err := os.Stat(output); !os.IsNotExist(err) {
		t.Fatal("wrote success report for blocked probe")
	}
}

func TestSelectProbeRequests(t *testing.T) {
	requests := probeRequests("2026-10-16")
	tests := []struct {
		name      string
		routes    string
		want      []string
		wantError bool
	}{
		{name: "all by default", want: []string{"equity_list", "equity_ohlcv", "index_ohlcv", "income_statement", "balance_sheet", "cash_flow", "market_calendar"}},
		{name: "one route", routes: "equity_list", want: []string{"equity_list"}},
		{name: "opt-in extended route", routes: "equity_trade_history", want: []string{"equity_trade_history"}},
		{name: "trim and canonical order", routes: "market_calendar, equity_list", want: []string{"equity_list", "market_calendar"}},
		{name: "unknown route", routes: "not_a_route", wantError: true},
		{name: "duplicate route", routes: "equity_list,equity_list", wantError: true},
		{name: "empty route", routes: "equity_list,", wantError: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := selectProbeRequests(requests, tt.routes)
			if (err != nil) != tt.wantError {
				t.Fatalf("selectProbeRequests error = %v, wantError %v", err, tt.wantError)
			}
			if err != nil {
				return
			}
			if len(got) != len(tt.want) {
				t.Fatalf("got %d routes, want %d", len(got), len(tt.want))
			}
			for i, request := range got {
				if route := request["op"]; route != tt.want[i] {
					t.Fatalf("route[%d] = %v, want %q", i, route, tt.want[i])
				}
			}
		})
	}
}

func TestSetProbeIndexSource(t *testing.T) {
	tests := []struct {
		name    string
		routes  []map[string]any
		source  string
		wantErr bool
	}{
		{name: "VCI selected", routes: []map[string]any{{"op": "index_ohlcv"}}, source: "vci"},
		{name: "KBS selected", routes: []map[string]any{{"op": "index_ohlcv"}}, source: "kbs"},
		{name: "unsupported source", routes: []map[string]any{{"op": "index_ohlcv"}}, source: "mas", wantErr: true},
		{name: "source without index route", routes: []map[string]any{{"op": "income_statement"}}, source: "vci", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := setProbeIndexSource(tt.routes, tt.source)
			if (err != nil) != tt.wantErr {
				t.Fatalf("setProbeIndexSource() error = %v, wantErr %v", err, tt.wantErr)
			}
			if err == nil && tt.routes[0]["source"] != tt.source {
				t.Fatalf("source = %v, want %q", tt.routes[0]["source"], tt.source)
			}
		})
	}
}

func TestSetProbeDateRange(t *testing.T) {
	tests := []struct {
		name    string
		start   string
		end     string
		wantErr bool
	}{
		{name: "valid historical range", start: "2018-10-18", end: "2019-12-31"},
		{name: "missing end", start: "2018-10-18", wantErr: true},
		{name: "invalid start", start: "2018/10/18", end: "2019-12-31", wantErr: true},
		{name: "reversed", start: "2020-01-01", end: "2019-12-31", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			requests := []map[string]any{{"op": "index_ohlcv"}}
			err := setProbeDateRange(requests, tt.start, tt.end)
			if (err != nil) != tt.wantErr {
				t.Fatalf("setProbeDateRange() error = %v, wantErr %v", err, tt.wantErr)
			}
			if err == nil && (requests[0]["start"] != tt.start || requests[0]["end"] != tt.end) {
				t.Fatalf("range set to %v..%v, want %s..%s", requests[0]["start"], requests[0]["end"], tt.start, tt.end)
			}
		})
	}
}

func TestProbeFailureType(t *testing.T) {
	tests := []struct {
		err  error
		want string
	}{
		{err: context.DeadlineExceeded, want: "WorkerTimeout"},
		{err: context.Canceled, want: "WorkerCanceled"},
		{err: errors.New("worker returned 0 frames (want exactly one); stderr: Python was not found"), want: "WorkerPythonUnavailable"},
		{err: errors.New("worker returned 0 frames (want exactly one); stderr: traceback"), want: "WorkerNoFrame"},
		{err: errors.New("worker frame: bufio.Scanner: token too long"), want: "WorkerFrameTooLarge"},
		{err: errors.New("worker response id mismatch"), want: "WorkerProtocolError"},
		{err: errors.New("worker start: executable not found"), want: "WorkerStartError"},
		{err: errors.New("worker exit: exit status 1; stderr: private output"), want: "WorkerExitError"},
	}
	for _, tt := range tests {
		if got := probeFailureType(tt.err); got != tt.want {
			t.Errorf("probeFailureType(%q) = %q, want %q", tt.err, got, tt.want)
		}
	}
}

func TestProbeFailureDetailsCauseCategoriesAreSafe(t *testing.T) {
	tests := []struct {
		stderr string
		want   string
	}{
		{stderr: "SystemExit: private output", want: "PythonSystemExit"},
		{stderr: "MemoryError: private output", want: "PythonMemoryError"},
		{stderr: "Traceback (most recent call last):\n  File \"vendor.py\", line 1\nAttributeError: private output", want: "PythonUnhandledAttributeError"},
		{stderr: "ModuleNotFoundError: No module named 'vnstock'", want: "PythonDependencyError"},
		{stderr: "ImportError: private output", want: "PythonImportError"},
		{stderr: "PermissionError: private output", want: "PythonPermissionError"},
		{stderr: "Fatal Python error: private output", want: "PythonProcessCrash"},
		{stderr: "Traceback (most recent call last): private output", want: "PythonUnhandledException"},
		{stderr: "Traceback (most recent call last):\n  File \"vendor.py\", line 1\nOddVendorError: private output", want: "PythonUnhandledOddVendorError"},
		{stderr: "private output", want: "UnknownWorkerExit"},
	}
	for _, tt := range tests {
		err := errors.New("worker exit: exit status 1; stderr: " + tt.stderr)
		details := probeFailureDetails(err)
		if got := details["worker_cause"]; got != tt.want {
			t.Errorf("worker_cause = %v, want %q", got, tt.want)
		}
		if strings.Contains(fmt.Sprint(details), "private output") {
			t.Fatalf("private stderr leaked into report fields: %v", details)
		}
	}

	noFrame := errors.New("worker returned 0 frames (want exactly one); stderr: Python was not found")
	if got := probeFailureDetails(noFrame)["worker_cause"]; got != "PythonUnavailable" {
		t.Errorf("no-frame worker cause = %v, want PythonUnavailable", got)
	}
}

func TestProbeFailureDetailsExitCodeIsSafe(t *testing.T) {
	py := pythonForTest(t)
	script := filepath.Join(t.TempDir(), "exit.py")
	if err := os.WriteFile(script, []byte("import sys\nprint('SystemExit: private output', file=sys.stderr)\nsys.exit(23)\n"), 0600); err != nil {
		t.Fatal(err)
	}
	processErr := exec.Command(py, script).Run()
	if processErr == nil {
		t.Fatal("fixture process unexpectedly succeeded")
	}
	details := probeFailureDetails(fmt.Errorf("worker exit: %w; stderr: SystemExit: private output", processErr))
	if details["error_type"] != "WorkerExitError" || details["exit_code"] != 23 || details["worker_cause"] != "PythonSystemExit" {
		t.Fatalf("unexpected diagnostic fields: %v", details)
	}
	if strings.Contains(fmt.Sprint(details), "private output") {
		t.Fatalf("private stderr leaked into report fields: %v", details)
	}
}

func TestCompanyProbeRouteErrorPreservesSafeDiagnostics(t *testing.T) {
	cases := []struct {
		payload string
		want    string
	}{
		{`{"company_info":{"available":false,"error_type":"AdapterError","error_cause":"AttributeError"}}`, "AttributeError"},
		{`{"company_info":{"available":false,"count":0,"error_type":"EmptyCompanyInfo"}}`, "EmptyCompanyInfo"},
		{`{"company_info":{"available":false,"error_type":"InvalidCompanyInfoFrame"}}`, "InvalidCompanyInfoFrame"},
		{`{"company_info":{"available":true,"count":1}}`, ""},
	}
	for _, c := range cases {
		err := companyProbeRouteError(json.RawMessage(c.payload))
		if c.want == "" {
			if err != nil {
				t.Fatalf("valid route rejected: %v", err)
			}
		} else if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Fatalf("route error lost %q: %v", c.want, err)
		}
	}
}
