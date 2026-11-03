package fsutil

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestWriteFileIfChangedKeepsMtimeForIdenticalBytes(t *testing.T) {
	path := filepath.Join(t.TempDir(), "a.json")
	if wrote, err := WriteFileIfChanged(path, []byte("x"), 0o644); err != nil || !wrote {
		t.Fatalf("first write: wrote=%v err=%v", wrote, err)
	}
	old := time.Now().Add(-time.Hour).Truncate(time.Second)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	if wrote, err := WriteFileIfChanged(path, []byte("x"), 0o644); err != nil || wrote {
		t.Fatalf("identical bytes must not be rewritten: wrote=%v err=%v", wrote, err)
	}
	if info, _ := os.Stat(path); !info.ModTime().Equal(old) {
		t.Fatalf("mtime changed on identical write: %v", info.ModTime())
	}
	if wrote, err := WriteFileIfChanged(path, []byte("y"), 0o644); err != nil || !wrote {
		t.Fatalf("changed bytes must be written: wrote=%v err=%v", wrote, err)
	}
	if b, _ := os.ReadFile(path); string(b) != "y" {
		t.Fatalf("got %q", b)
	}
}
