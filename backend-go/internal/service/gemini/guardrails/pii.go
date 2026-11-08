package guardrails

import (
	"regexp"
	"strings"
	"unicode/utf8"
)

var (
	emailRE = regexp.MustCompile(`(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}`)
	// Egypt mobile / international-ish phone fragments.
	phoneRE = regexp.MustCompile(`(?i)(?:\+?20|0)?1[0125]\d{8}`)
	apiKeyRE = regexp.MustCompile(`(?i)(?:AIza[0-9A-Za-z\-_]{20,}|sk-[A-Za-z0-9]{20,})`)
)

// MaxCellRunes is the max length kept for any single cell sent to Gemini or logged.
const MaxCellRunes = 40

// MaxSampleRows is the max leading rows allowed in a mapping sample (matches mappingSampleRows).
const MaxSampleRows = 15

// RedactString strips emails, phones, and API-key-shaped tokens from log/error text.
func RedactString(s string) string {
	s = apiKeyRE.ReplaceAllString(s, "[redacted-key]")
	s = emailRE.ReplaceAllString(s, "[redacted-email]")
	s = phoneRE.ReplaceAllString(s, "[redacted-phone]")
	return s
}

// TruncateCell shortens a cell for prompts/logs without inventing content.
func TruncateCell(s string) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= MaxCellRunes {
		return s
	}
	runes := []rune(s)
	return string(runes[:MaxCellRunes])
}

// SanitizeSampleRows returns a deep copy of at most MaxSampleRows, with truncated cells.
// It never expands the sample — callers must already limit what they send to Gemini.
func SanitizeSampleRows(rows [][]string) [][]string {
	return SanitizeSampleRowsLimit(rows, MaxSampleRows)
}

// SanitizeSampleRowsLimit truncates cells and caps row count for any Gemini sample path
// (column-mapping or full-normalize).
func SanitizeSampleRowsLimit(rows [][]string, maxRows int) [][]string {
	if maxRows <= 0 {
		maxRows = MaxSampleRows
	}
	if len(rows) > maxRows {
		rows = rows[:maxRows]
	}
	out := make([][]string, len(rows))
	for i, r := range rows {
		cp := make([]string, len(r))
		for j, c := range r {
			cp[j] = TruncateCell(RedactString(c))
		}
		out[i] = cp
	}
	return out
}

// FilenameForLog returns a basename-safe label for logs (no paths, truncated).
func FilenameForLog(name string) string {
	name = strings.ReplaceAll(name, "\\", "/")
	if i := strings.LastIndex(name, "/"); i >= 0 {
		name = name[i+1:]
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return "unknown"
	}
	if utf8.RuneCountInString(name) > 120 {
		return string([]rune(name)[:120])
	}
	return name
}
