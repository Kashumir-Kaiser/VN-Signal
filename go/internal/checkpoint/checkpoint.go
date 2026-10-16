// Package checkpoint provides atomic local resume-state persistence.
package checkpoint

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Progress struct {
	RunID         string `json:"run_id"`
	LastCompleted string `json:"last_completed"`
	CallsUsed     int    `json:"calls_used"`
}

func Save(path string, state Progress) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	payload, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), "checkpoint-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	defer f.Close()
	if err = f.Chmod(0600); err != nil {
		return err
	}
	if _, err = f.Write(payload); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}
func Load(path string) (Progress, error) {
	var state Progress
	content, err := os.ReadFile(path)
	if err != nil {
		return state, err
	}
	err = json.Unmarshal(content, &state)
	return state, err
}
