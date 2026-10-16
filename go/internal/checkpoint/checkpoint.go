// Package checkpoint persists resume state with crash-safe rename and fail-closed locks.
package checkpoint

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
)

type Progress struct {
	RunID         string `json:"run_id"`
	LastCompleted string `json:"last_completed"`
	CallsUsed     int    `json:"calls_used"`
}

var ErrLocked = errors.New("checkpoint is locked; inspect abandoned lock before recovery")
var ErrCorrupt = errors.New("checkpoint invalid or corrupt; refusing automatic reset")

// Injected only by package-local tests. No global mutation needed in production.
type fileOps struct {
	rename func(string, string) error
	sync   func(*os.File) error
}

func defaultOps() fileOps                    { return fileOps{rename: os.Rename, sync: (*os.File).Sync} }
func valid(p Progress) bool                  { return p.RunID != "" && p.CallsUsed >= 0 }
func Save(path string, state Progress) error { return save(path, state, defaultOps()) }
func save(path string, state Progress, ops fileOps) error {
	if !valid(state) {
		return ErrCorrupt
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	lock := path + ".lock"
	if err := os.Mkdir(lock, 0700); err != nil {
		if os.IsExist(err) {
			return ErrLocked
		}
		return err
	}
	defer os.Remove(lock)
	// Aborted writes are never promoted; clean orphaned files ONLY under the lock.
	matches, _ := filepath.Glob(filepath.Join(dir, "."+filepath.Base(path)+".tmp-*"))
	for _, m := range matches {
		if err := os.Remove(m); err != nil {
			return fmt.Errorf("cleanup orphan temp: %w", err)
		}
	}
	payload, err := json.Marshal(state)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if err := f.Chmod(0600); err != nil {
		return err
	}
	if _, err := f.Write(append(payload, '\n')); err != nil {
		return err
	}
	if err := ops.sync(f); err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := ops.rename(f.Name(), path); err != nil {
		return err
	}
	// Flush directory entry when supported. On platforms that reject directory
	// fsync, do not report success as fully crash-durable; surface the error.
	if runtime.GOOS == "windows" {
		return nil
	} // Windows rename durability is filesystem-managed.
	if d, e := os.Open(dir); e == nil {
		defer d.Close()
		if e = d.Sync(); e != nil {
			return fmt.Errorf("sync checkpoint directory: %w", e)
		}
	} else {
		return e
	}
	return nil
}
func Load(path string) (Progress, error) {
	var state Progress
	content, err := os.ReadFile(path)
	if err != nil {
		return state, err
	}
	if err := json.Unmarshal(content, &state); err != nil {
		return Progress{}, fmt.Errorf("%w: %v", ErrCorrupt, err)
	}
	if !valid(state) {
		return Progress{}, ErrCorrupt
	}
	return state, nil
}
