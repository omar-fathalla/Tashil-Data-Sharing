package handlers

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
)

// ReleaseName is the human-readable name of the current release.
const ReleaseName = "ميكول"

// BackendVersion is the semantic version of the backend service.
const BackendVersion = "1.1.0"

// buildCommitFile is written into the clean source export at deploy time.
var buildCommitFile = "data/build_commit.txt"

// VersionResponse is returned by GET /api/v1/version.
type VersionResponse struct {
	Release        string `json:"release"`
	BackendVersion string `json:"backend_version"`
	GitCommit      string `json:"git_commit"`
	Revision       string `json:"revision"`
}

func buildCommit() string {
	if c := strings.TrimSpace(os.Getenv("GIT_COMMIT")); c != "" {
		return c
	}
	if b, err := os.ReadFile(buildCommitFile); err == nil {
		if c := strings.TrimSpace(string(b)); c != "" {
			return c
		}
	}
	return "unknown"
}

// Version serves public, read-only build information.
func Version(w http.ResponseWriter, r *http.Request) {
	rev := os.Getenv("K_REVISION")
	if rev == "" {
		rev = "local"
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(VersionResponse{
		Release:        ReleaseName,
		BackendVersion: BackendVersion,
		GitCommit:      buildCommit(),
		Revision:       rev,
	})
}
