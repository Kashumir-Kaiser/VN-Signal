// Package worker supervises the JSON-lines Python adapter with strict IDs.
package worker

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type Response struct {
	ID    string          `json:"id"`
	OK    bool            `json:"ok"`
	Data  json.RawMessage `json:"data"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error"`
}

// Invoke launches a worker for one job with a timeout controlled by ctx.
// Long-lived supervision is a later phase; do not imply it exists yet.
func Invoke(ctx context.Context, interpreter, script string, job map[string]any) (Response, error) {
	var response Response
	if interpreter == "" || script == "" {
		return response, errors.New("missing worker path")
	}
	id, ok := job["id"].(string)
	if !ok || id == "" {
		return response, errors.New("missing request id")
	}
	payload, err := json.Marshal(job)
	if err != nil {
		return response, err
	}
	cmd := exec.CommandContext(ctx, interpreter, script)
	cmd.Env = os.Environ()
	cmd.Stdin = bytes.NewReader(append(payload, '\n'))
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return response, err
	}
	if err = cmd.Start(); err != nil {
		return response, err
	}
	scan := bufio.NewScanner(stdout)
	scan.Buffer(make([]byte, 4096), 10*1024*1024)
	if !scan.Scan() {
		_ = cmd.Wait()
		return response, fmt.Errorf("worker returned no frame: %s", strings.TrimSpace(stderr.String()))
	}
	if err = scan.Err(); err != nil {
		_ = cmd.Wait()
		return response, err
	}
	if err = json.Unmarshal(scan.Bytes(), &response); err != nil {
		_ = cmd.Wait()
		return response, err
	}
	if response.ID != id {
		_ = cmd.Wait()
		return response, errors.New("worker response id mismatch")
	}
	if err = cmd.Wait(); err != nil {
		return response, fmt.Errorf("worker exit: %w", err)
	}
	if !response.OK && response.Error == nil {
		return response, errors.New("worker failed without error type")
	}
	return response, nil
}

func ScriptPath() string {
	if val := os.Getenv("VNPIPE_WORKER"); val != "" {
		return val
	}
	// Executing under go/ is expected; path can be overridden from any cwd.
	return filepath.Join("..", "py", "vnstock_worker.py")
}

func Python() string {
	if val := os.Getenv("VNPIPE_PYTHON"); val != "" {
		return val
	}
	return "python3"
}
