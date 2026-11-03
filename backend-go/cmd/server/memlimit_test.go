package main

import "testing"

func TestGoMemoryLimitFollowsContainer(t *testing.T) {
	cases := map[int64]int64{0: 1536 << 20, 2 << 30: 1536 << 20, 4 << 30: 3 << 30}
	for in, want := range cases {
		if got := goMemoryLimit(in); got != want {
			t.Fatalf("goMemoryLimit(%d) = %d, want %d", in, got, want)
		}
	}
}
