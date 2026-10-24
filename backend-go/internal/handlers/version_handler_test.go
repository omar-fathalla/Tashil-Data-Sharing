package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestVersion(t *testing.T) {
	t.Setenv("K_REVISION", "rev-1")
	t.Setenv("GIT_COMMIT", "abc123")
	rr := httptest.NewRecorder()
	Version(rr, httptest.NewRequest(http.MethodGet, "/api/v1/version", nil))
	if rr.Code != http.StatusOK {
		t.Fatalf("status %d", rr.Code)
	}
	var v VersionResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &v); err != nil {
		t.Fatal(err)
	}
	if v.Release != ReleaseName || v.Revision != "rev-1" || v.GitCommit != "abc123" || v.BackendVersion == "" {
		t.Fatalf("unexpected %+v", v)
	}
}
