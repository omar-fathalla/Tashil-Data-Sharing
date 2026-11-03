package main

import (
	"os"
	"strconv"
	"strings"
)

// defaultGoMemoryLimit is used when the container limit is unknown (local runs): the old 2Gi-era value.
const defaultGoMemoryLimit int64 = 1536 << 20

// readCgroupMemoryMax returns the container memory limit in bytes (cgroup v2, then v1), or 0 if unknown.
func readCgroupMemoryMax() int64 {
	for _, f := range []string{"/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"} {
		raw, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		v, err := strconv.ParseInt(strings.TrimSpace(string(raw)), 10, 64)
		if err == nil && v > 0 && v < 1<<50 {
			return v
		}
	}
	return 0
}

// goMemoryLimit keeps the Go heap at 75% of the container limit (2Gi -> 1.5GiB as before, 4Gi -> 3GiB),
// leaving room for gcsfuse buffers and non-heap memory.
func goMemoryLimit(containerBytes int64) int64 {
	if containerBytes <= 0 {
		return defaultGoMemoryLimit
	}
	return containerBytes / 4 * 3
}
