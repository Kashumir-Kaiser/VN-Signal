package checkpoint

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func progress() Progress { return Progress{RunID: "run-1", LastCompleted: "FPT", CallsUsed: 20} }
func TestRoundTrip(t *testing.T) {
	p := filepath.Join(t.TempDir(), "nested", "checkpoint.json")
	if err := Save(p, progress()); err != nil {
		t.Fatal(err)
	}
	got, err := Load(p)
	if err != nil || got != progress() {
		t.Fatalf("%+v %v", got, err)
	}
}
func TestMissingCorruptAndInvalid(t *testing.T) {
	p := filepath.Join(t.TempDir(), "state.json")
	if _, e := Load(p); !errors.Is(e, os.ErrNotExist) {
		t.Fatal(e)
	}
	for _, v := range []string{"{corrupt", "{}", "{\"run_id\":\"ok\",\"calls_used\":-10}"} {
		if e := os.WriteFile(p, []byte(v), 0600); e != nil {
			t.Fatal(e)
		}
		if _, e := Load(p); !errors.Is(e, ErrCorrupt) {
			t.Fatal(e)
		}
	}
}
func TestAtomicFaultsPreservePrevious(t *testing.T) {
	p := filepath.Join(t.TempDir(), "state.json")
	if e := Save(p, progress()); e != nil {
		t.Fatal(e)
	}
	for _, kind := range []string{"write-sync", "rename"} {
		t.Run(kind, func(t *testing.T) {
			o := defaultOps()
			if kind == "write-sync" {
				o.sync = func(*os.File) error { return errors.New("ENOSPC") }
			} else {
				o.rename = func(string, string) error { return errors.New("rename failed") }
			}
			changed := progress()
			changed.CallsUsed = 99
			if e := save(p, changed, o); e == nil {
				t.Fatal("fault ignored")
			}
			actual, e := Load(p)
			if e != nil || actual != progress() {
				t.Fatalf("old state lost: %+v %v", actual, e)
			}
		})
	}
}
func TestOrphanCleanupAndLock(t *testing.T) {
	p := filepath.Join(t.TempDir(), "checkpoint.json")
	orphan := filepath.Join(filepath.Dir(p), "."+filepath.Base(p)+".tmp-old")
	os.WriteFile(orphan, []byte("partial"), 0600)
	if e := Save(p, progress()); e != nil {
		t.Fatal(e)
	}
	if _, e := os.Stat(orphan); !errors.Is(e, os.ErrNotExist) {
		t.Fatal("orphan retained")
	}
	if e := os.Mkdir(p+".lock", 0700); e != nil {
		t.Fatal(e)
	}
	if e := Save(p, progress()); !errors.Is(e, ErrLocked) {
		t.Fatal(e)
	}
}
func TestConcurrentWritersNoCorruption(t *testing.T) {
	p := filepath.Join(t.TempDir(), "state.json")
	var wg sync.WaitGroup
	for i := 0; i < 30; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			e := Save(p, progress())
			if e != nil && !errors.Is(e, ErrLocked) {
				t.Errorf("save: %v", e)
			}
		}()
	}
	wg.Wait()
	if _, e := Load(p); e != nil {
		t.Fatal(e)
	}
}
func TestPermissions(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores directory permissions")
	}
	dir := filepath.Join(t.TempDir(), "readonly")
	os.Mkdir(dir, 0500)
	defer os.Chmod(dir, 0700)
	if e := Save(filepath.Join(dir, "state"), progress()); e == nil {
		t.Fatal("read-only directory accepted")
	}
}
