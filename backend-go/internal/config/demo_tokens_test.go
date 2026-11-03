package config

import "testing"

func TestDemoTokensRefusedInProduction(t *testing.T) {
	cases := []struct {
		env, allow string
		on, fail   bool
	}{
		{"production", "true", false, true},
		{"Production", "true", false, true},
		{"production", "false", false, false}, // the current prod setting starts fine
		{"production", "", false, false},
		{"development", "true", true, false},
		{"", "true", true, false},
	}
	for _, c := range cases {
		on, err := DemoTokensAllowed(c.env, c.allow)
		if on != c.on || (err != nil) != c.fail {
			t.Fatalf("%+v: got on=%v err=%v", c, on, err)
		}
	}
}
