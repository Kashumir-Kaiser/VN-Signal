package checkpoint

import (
	"path/filepath"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "checkpoint.json")
	want := Progress{RunID: "run-1", LastCompleted: "FPT", CallsUsed: 20}
	if err := Save(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := Load(path)
	if err != nil || got != want {
		t.Fatalf("got %+v err %v", got, err)
	}
}
