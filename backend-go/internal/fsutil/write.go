// Package fsutil holds small file helpers shared by the services.
package fsutil

import (
	"bytes"
	"os"
)

// WriteFileIfChanged writes data to path only when the file is missing or its contents differ.
//
// Files under the shared archive mount (GCS) feed the startup snapshot manifest by size and mtime.
// Rewriting identical bytes (e.g. during an archive replay) bumped the mtime and made every other
// instance's snapshot look stale, which forced repeated full replays. Skipping identical writes keeps
// the snapshot valid. It reports whether a write happened.
func WriteFileIfChanged(path string, data []byte, perm os.FileMode) (bool, error) {
	if cur, err := os.ReadFile(path); err == nil && bytes.Equal(cur, data) {
		return false, nil
	}
	if err := os.WriteFile(path, data, perm); err != nil {
		return false, err
	}
	return true, nil
}
