package config

import (
	"strings"
	"testing"
)

func TestLoadTrimsGeminiSecretNewlines(t *testing.T) {
	t.Setenv("GEMINI_API_KEY", "AIzaSyTestKeyWithNewline\n")
	t.Setenv("GEMINI_MODEL", " gemini-3.8-flash\n")
	t.Setenv("GEMINI_TIER2_MODEL", "gemini-pro-latest\r\n")
	t.Setenv("USE_MOCK_SERVICES", "true")

	cfg := Load()
	if cfg.GeminiAPIKey != "AIzaSyTestKeyWithNewline" {
		t.Fatalf("GEMINI_API_KEY not trimmed: %q", cfg.GeminiAPIKey)
	}
	if strings.ContainsAny(cfg.GeminiAPIKey, "\r\n\t ") {
		t.Fatalf("GEMINI_API_KEY still has whitespace: %q", cfg.GeminiAPIKey)
	}
	if cfg.GeminiModel != "gemini-3.8-flash" {
		t.Fatalf("GEMINI_MODEL not trimmed: %q", cfg.GeminiModel)
	}
	if cfg.GeminiTier2Model != "gemini-pro-latest" {
		t.Fatalf("GEMINI_TIER2_MODEL not trimmed: %q", cfg.GeminiTier2Model)
	}
}
