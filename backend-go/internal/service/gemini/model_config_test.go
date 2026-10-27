package gemini

import "testing"

func TestNewAgentKeepsFlashModelAsIs(t *testing.T) {
	c := NewAgent("", "gemini-3.8-flash", true)
	if c.Model() != "gemini-3.8-flash" {
		t.Fatalf("flash model was remapped: got %q", c.Model())
	}
	if c.Tier2Model() != DefaultModel {
		t.Fatalf("tier2 default: got %q, want %q", c.Tier2Model(), DefaultModel)
	}
}

func TestNewAgentDefaultsToProLatest(t *testing.T) {
	c := NewAgent("", "  ", true)
	if c.Model() != "gemini-pro-latest" {
		t.Fatalf("default model: got %q", c.Model())
	}
}

func TestWithTier2ModelOverride(t *testing.T) {
	c := NewAgent("", "gemini-3.8-flash", true).WithTier2Model(" gemini-pro-latest ")
	if c.Tier2Model() != "gemini-pro-latest" {
		t.Fatalf("tier2 override: got %q", c.Tier2Model())
	}
	c.WithTier2Model("")
	if c.Tier2Model() != "gemini-pro-latest" {
		t.Fatalf("empty override should keep previous: got %q", c.Tier2Model())
	}
}
