package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRefuseInsideGitTree(t *testing.T) {
	root := t.TempDir()
	repo := filepath.Join(root, "repo")
	if err := os.MkdirAll(filepath.Join(repo, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := refuseInsideGitTree(filepath.Join(repo, "docs", "mapping.csv")); err == nil {
		t.Fatal("path inside a git work tree must be refused")
	}
	if err := refuseInsideGitTree(filepath.Join(root, "outside", "mapping.csv")); err != nil {
		t.Fatalf("path outside the repo must be allowed: %v", err)
	}
	if err := refuseInsideGitTree(""); err != nil {
		t.Fatal(err)
	}
}
