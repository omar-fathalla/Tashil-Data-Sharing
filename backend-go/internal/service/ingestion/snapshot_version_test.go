package ingestion

import (
	"strings"
	"testing"
)

// The snapshot key must depend on schema + parser version only, so a redeploy of an
// unrelated change keeps the startup snapshot valid.
func TestSnapshotBuildIDIsVersionNotBinaryHash(t *testing.T) {
	id := currentBuildID()
	if !strings.Contains(id, SnapshotParserVersion) || !strings.HasPrefix(id, "schema-") {
		t.Fatalf("unexpected snapshot key %q", id)
	}
}
