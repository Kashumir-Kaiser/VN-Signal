package worker

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestPythonInterpreterSelection(t *testing.T) {
	t.Setenv("VNPIPE_PYTHON", "")
	want := "python3"
	if runtime.GOOS == "windows" {
		want = "python"
	}
	if got := Python(); got != want {
		t.Fatalf("default=%q want=%q", got, want)
	}
	t.Setenv("VNPIPE_PYTHON", "explicit-interpreter-path")
	if got := Python(); got != "explicit-interpreter-path" {
		t.Fatalf("override lost: %q", got)
	}
}

func python(t *testing.T) string {
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
func fake(t *testing.T, script string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "fake.py")
	if err := os.WriteFile(p, []byte(script), 0600); err != nil {
		t.Fatal(err)
	}
	return p
}
func invoke(t *testing.T, body string) (Response, error) {
	t.Helper()
	return Invoke(context.Background(), python(t), fake(t, body), map[string]any{"id": "q1", "op": "health"})
}
func TestCappedWriterPreservesBoundedTracebackTail(t *testing.T) {
	var stderr cappedWriter
	_, _ = stderr.Write([]byte("Traceback (most recent call last):\n"))
	_, _ = stderr.Write([]byte(strings.Repeat("x", 6000)))
	_, _ = stderr.Write([]byte("\nOddVendorError: private message"))

	got := stderr.String()
	if len(got) > stderrMaxBytes {
		t.Fatalf("stderr length %d exceeds %d", len(got), stderrMaxBytes)
	}
	if !strings.Contains(got, "Traceback (most recent call last):") ||
		!strings.Contains(got, "OddVendorError: private message") {
		t.Fatalf("stderr head/tail lost diagnostic markers: %q", got)
	}
	if !strings.Contains(got, stderrTruncatedMarker) {
		t.Fatalf("truncation marker missing: %q", got)
	}
}

func TestRejectMissingID(t *testing.T) {
	if _, err := Invoke(context.Background(), "unused", "unused", map[string]any{"op": "health"}); err == nil {
		t.Fatal("missing ID accepted")
	}
}
func TestWorkerFailureModes(t *testing.T) {
	ok := "import json,sys\nprint(json.dumps({'id':'q1','ok':True,'data':{}}))\n"
	cases := []struct{ name, body, want string }{
		{"valid", ok, ""},
		{"warning_stdout", "print('vendor warning')\n" + ok, "frames"},
		{"malformed", "print('{broken')\n", "malformed"},
		{"multiple", ok + ok, "frames"},
		{"id", "print('{\"id\":\"not-q1\",\"ok\":true,\"data\":{}}')\n", "id mismatch"},
		{"extra_tokens", "print('{\"id\":\"q1\",\"ok\":true,\"data\":{}} trailing')\n", "trailing"},
		{"exit_nonzero", ok + "sys.exit(2)\n", "worker exit"},
		{"no_frame", "import sys\nsys.exit(0)\n", "0 frames"},
		{"no_frame_exit_nonzero", "import sys\nsys.exit(23)\n", "worker exit"},
		{"large", "print('x'*(10*1024*1024+2))\n", "frame"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := invoke(t, tc.body)
			if tc.want == "" && err != nil {
				t.Fatal(err)
			}
			if tc.want != "" && (err == nil || !strings.Contains(err.Error(), tc.want)) {
				t.Fatalf("want %q got %v", tc.want, err)
			}
		})
	}
}
func TestTimeoutKillsWorker(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	_, err := Invoke(ctx, python(t), fake(t, "import time\ntime.sleep(30)\n"), map[string]any{"id": "q1", "op": "health"})
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("timeout: %v", err)
	}
}
func TestMissingInterpreterAndScript(t *testing.T) {
	_, err := Invoke(context.Background(), filepath.Join(t.TempDir(), "missing-python"), "script", map[string]any{"id": "q1"})
	if err == nil {
		t.Fatal("missing interpreter accepted")
	}
	_, err = Invoke(context.Background(), python(t), filepath.Join(t.TempDir(), "missing.py"), map[string]any{"id": "q1"})
	if err == nil {
		t.Fatal("missing script accepted")
	}
	if runtime.GOOS != "windows" {
		_, err = Invoke(context.Background(), "/dev/null", "any", map[string]any{"id": "q1"})
		if err == nil {
			t.Fatal("non-executable interpreter accepted")
		}
	}
}
func TestActualPythonHealth(t *testing.T) {
	script := filepath.Join("..", "..", "..", "py", "vnstock_worker.py")
	r, err := Invoke(context.Background(), python(t), script, map[string]any{"id": "test-real-health", "op": "health"})
	if err != nil {
		t.Fatal(err)
	}
	if !r.OK || r.ID != "test-real-health" || !strings.Contains(string(r.Data), "protocol") {
		t.Fatalf("response %+v", r)
	}
}

func TestSecretsNotInherited(t *testing.T) {
	t.Setenv("SUPER_SECRET_SENTINEL", "must-never-leak")
	body := "import json,os\nprint(json.dumps({'id':'q1','ok':True,'data':{'leaked':bool(os.getenv('SUPER_SECRET_SENTINEL'))}}))\n"
	r, err := invoke(t, body)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(r.Data), `true`) {
		t.Fatalf("secret environment was inherited: %s", r.Data)
	}
}

func TestVNStockHomeIsInheritedWithoutForwardingOtherSecrets(t *testing.T) {
	stateDir := t.TempDir()
	t.Setenv("VNSTOCK_HOME", stateDir)
	t.Setenv("OTHER_SECRET_SENTINEL", "must-never-leak")
	got := map[string]string{}
	for _, entry := range safeEnv() {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			got[strings.ToUpper(key)] = value
		}
	}
	if got["VNSTOCK_HOME"] != stateDir {
		t.Fatalf("VNSTOCK_HOME not forwarded: %q", got["VNSTOCK_HOME"])
	}
	if _, ok := got["OTHER_SECRET_SENTINEL"]; ok {
		t.Fatal("unrelated secret environment was forwarded")
	}
}

func TestSingleWorkerProcessAtATime(t *testing.T) {
	py := python(t)
	script := fake(t, "import json,time\ntime.sleep(.25)\nprint(json.dumps({'id':'q1','ok':True,'data':{}}))\n")
	begin := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := Invoke(context.Background(), py, script, map[string]any{"id": "q1"}); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if time.Since(begin) < 450*time.Millisecond {
		t.Fatal("unbounded worker process execution")
	}
}
