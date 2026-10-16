// Package worker supervises the JSON-lines Python adapter with strict IDs.
package worker

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const MaxFrameBytes = 10 * 1024 * 1024
const defaultTimeout = 45 * time.Second

// One process at a time on the single-user machine. A future persistent
// supervisor may replace this but must retain bounded concurrent workers.
var workerSlots = make(chan struct{}, 1)

type Response struct {
	ID    string          `json:"id"`
	OK    bool            `json:"ok"`
	Data  json.RawMessage `json:"data"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// Invoke expects exactly one JSON frame. Worker library logs must go to stderr.
// A missing deadline is bounded so a hung adapter cannot stall the scheduler forever.
func Invoke(ctx context.Context, interpreter, script string, job map[string]any) (Response, error) {
	var response Response
	if interpreter == "" || script == "" {
		return response, errors.New("missing worker path")
	}
	id, ok := job["id"].(string)
	if !ok || id == "" {
		return response, errors.New("missing request id")
	}
	select {
	case workerSlots <- struct{}{}:
		defer func() { <-workerSlots }()
	case <-ctx.Done():
		return response, ctx.Err()
	}
	payload, err := json.Marshal(job)
	if err != nil {
		return response, err
	}
	if len(payload) > 65535 {
		return response, errors.New("worker request too large")
	}
	if _, ok := ctx.Deadline(); !ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, defaultTimeout)
		defer cancel()
	}
	cmd := exec.CommandContext(ctx, interpreter, script)
	cmd.Env = safeEnv()
	cmd.Stdin = bytes.NewReader(append(payload, '\n'))
	// Never forward untrusted subprocess output to the terminal. stderr is capped.
	var stderr cappedWriter
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return response, err
	}
	if err := cmd.Start(); err != nil {
		return response, fmt.Errorf("worker start: %w", err)
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 4096), MaxFrameBytes+1)
	frames := 0
	var raw []byte
	for scanner.Scan() {
		frames++
		if frames == 1 {
			raw = bytes.Clone(scanner.Bytes())
		}
		if frames > 1 {
			break
		}
	}
	scanErr := scanner.Err()
	// Closing the pipe explicitly prevents Wait from blocking when a misbehaving
	// worker floods stdout after the first frame. Kill it on protocol faults.
	if scanErr != nil || frames > 1 {
		_ = cmd.Process.Kill()
		_ = stdout.Close()
	}
	waitErr := cmd.Wait()
	if ctx.Err() != nil {
		return response, fmt.Errorf("worker timeout/cancel: %w", ctx.Err())
	}
	if scanErr != nil {
		return response, fmt.Errorf("worker frame: %w", scanErr)
	}
	if frames != 1 {
		if waitErr != nil {
			return response, fmt.Errorf("worker exit: %w; stderr: %s", waitErr, stderr.String())
		}
		return response, fmt.Errorf("worker returned %d frames (want exactly one); stderr: %s", frames, stderr.String())
	}
	if len(raw) >= MaxFrameBytes {
		return response, errors.New("worker frame exceeds maximum")
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&response); err != nil {
		return Response{}, fmt.Errorf("malformed worker frame: %w", err)
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return Response{}, errors.New("worker frame contains trailing data")
	}
	if response.ID != id {
		return Response{}, errors.New("worker response id mismatch")
	}
	if response.OK && (response.Error != nil || len(response.Data) == 0) {
		return Response{}, errors.New("invalid success envelope")
	}
	if !response.OK && (response.Error == nil || response.Error.Type == "") {
		return Response{}, errors.New("invalid failure envelope")
	}
	if waitErr != nil {
		return Response{}, fmt.Errorf("worker exit: %w; stderr: %s", waitErr, stderr.String())
	}
	return response, nil
}

type cappedWriter struct{ b bytes.Buffer }

func (c *cappedWriter) Write(p []byte) (int, error) {
	n := len(p)
	if c.b.Len() < 4096 {
		_, _ = c.b.Write(p[:min(len(p), 4096-c.b.Len())])
	}
	return n, nil
}
func (c *cappedWriter) String() string { return strings.TrimSpace(c.b.String()) }

func ScriptPath() string {
	if v := os.Getenv("VNPIPE_WORKER"); v != "" {
		return v
	}
	return filepath.Join("..", "py", "vnstock_worker.py")
}
func Python() string {
	if v := os.Getenv("VNPIPE_PYTHON"); v != "" {
		return v
	}
	return "python3"
}

// Prevent accidental forwarding of unrelated tokens (GH_TOKEN, cloud keys,
// database passwords) into third-party vnstock code. Keep required local
// runtime directories; vnstock account registration lives in user config.
func safeEnv() []string {
	allowed := map[string]bool{
		"PATH": true, "HOME": true, "USERPROFILE": true, "APPDATA": true, "LOCALAPPDATA": true,
		"SYSTEMROOT": true, "WINDIR": true, "TMP": true, "TEMP": true, "TMPDIR": true,
		"LANG": true, "LC_ALL": true, "VIRTUAL_ENV": true, "VNPIPE_DISABLE_LIVE": true,
		"SSL_CERT_FILE": true, "REQUESTS_CA_BUNDLE": true, "TZ": true,
	}
	var env []string
	for _, entry := range os.Environ() {
		k, _, ok := strings.Cut(entry, "=")
		if ok && allowed[strings.ToUpper(k)] {
			env = append(env, entry)
		}
	}
	return env
}
