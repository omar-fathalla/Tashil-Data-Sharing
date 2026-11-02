package gemini

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Upload normalization helpers. Every helper either returns a deterministic value with ok=true or
// ok=false; callers must never substitute a default month/year for an unparseable value.

var arabicMonthNames = []string{"يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"}

// ArabicMonthName returns the canonical Arabic month name for 1..12 ("" otherwise).
func ArabicMonthName(m int) string {
	if m >= 1 && m <= 12 {
		return arabicMonthNames[m-1]
	}
	return ""
}

var monthNameTable = func() map[string]int {
	t := map[string]int{}
	add := func(m int, names ...string) {
		for _, n := range names {
			t[normalizeMonthKey(n)] = m
		}
	}
	add(1, "january", "jan", "يناير", "كانون الثاني", "كانون ثاني", "جانفي")
	add(2, "february", "feb", "febr", "فبراير", "شباط", "فيفري")
	add(3, "march", "mar", "مارس", "آذار", "اذار")
	add(4, "april", "apr", "أبريل", "ابريل", "إبريل", "نيسان", "افريل")
	add(5, "may", "مايو", "أيار", "ايار", "ماي")
	add(6, "june", "jun", "يونيو", "يونية", "حزيران", "جوان")
	add(7, "july", "jul", "يوليو", "يولية", "تموز", "جويلية")
	add(8, "august", "aug", "أغسطس", "اغسطس", "آب", "اب", "أوت", "اوت")
	add(9, "september", "sep", "sept", "سبتمبر", "أيلول", "ايلول")
	add(10, "october", "oct", "أكتوبر", "اكتوبر", "تشرين الأول", "تشرين اول")
	add(11, "november", "nov", "نوفمبر", "تشرين الثاني", "تشرين ثاني")
	add(12, "december", "dec", "ديسمبر", "كانون الأول", "كانون اول")
	return t
}()

func normalizeMonthKey(s string) string {
	s = strings.ToLower(strings.TrimSpace(normalizeArabicDigitsToASCII(s)))
	s = strings.NewReplacer("أ", "ا", "إ", "ا", "آ", "ا", "ة", "ه", "ى", "ي", ".", "", "ـ", "").Replace(s)
	return strings.Join(strings.Fields(s), " ")
}

var (
	reYearMonth = regexp.MustCompile(`^(20\d{2})[-/.](\d{1,2})(?:[-/.](\d{1,2}))?(?:[ T].*)?$`)
	reDayMonthY = regexp.MustCompile(`^(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})$`)
	reMonYear   = regexp.MustCompile(`^([^\d]+?)[\s\-_/]*((?:20)?\d{2})$`)
)

// ExcelSerialToDate converts an Excel 1900-system serial (e.g. 46025) to a date. ok=false outside 2000..2100.
func ExcelSerialToDate(s string) (time.Time, bool) {
	f, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil || f < 36526 || f > 73051 { // 2000-01-01 .. 2100-01-01
		return time.Time{}, false
	}
	base := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
	return base.AddDate(0, 0, int(f)), true
}

// ParseDateToken parses ISO dates, d/m/yyyy, "YYYY-MM" and Excel serials. Ambiguous d/m vs m/d is
// resolved only when one side is > 12; otherwise ok=false.
func ParseDateToken(raw string) (year, month int, ok bool) {
	s := strings.TrimSpace(normalizeArabicDigitsToASCII(raw))
	if s == "" {
		return 0, 0, false
	}
	if m := reYearMonth.FindStringSubmatch(s); m != nil {
		y, _ := strconv.Atoi(m[1])
		mo, _ := strconv.Atoi(m[2])
		if mo >= 1 && mo <= 12 {
			return y, mo, true
		}
		return 0, 0, false
	}
	if m := reDayMonthY.FindStringSubmatch(s); m != nil {
		a, _ := strconv.Atoi(m[1])
		b, _ := strconv.Atoi(m[2])
		y, _ := strconv.Atoi(m[3])
		switch {
		case a > 12 && b >= 1 && b <= 12:
			return y, b, true
		case b > 12 && a >= 1 && a <= 12:
			return y, a, true
		case a == b && a >= 1 && a <= 12:
			return y, a, true
		}
		return 0, 0, false
	}
	if t, ok := ExcelSerialToDate(s); ok && !strings.ContainsAny(s, "-/") {
		return t.Year(), int(t.Month()), true
	}
	return 0, 0, false
}

// ParseMonthToken normalizes a month cell: English full/short names, Egyptian/Levantine/Maghrebi Arabic
// names, 1..12 / 01..12, "YYYY-MM", ISO / d-m-y dates and Excel serial dates.
// year is >0 only when the token itself carries a year. ok=false for anything else (e.g. "#N/A").
func ParseMonthToken(raw string) (month, year int, ok bool) {
	s := strings.TrimSpace(normalizeArabicDigitsToASCII(raw))
	if s == "" || strings.HasPrefix(s, "#") {
		return 0, 0, false
	}
	if n, err := strconv.Atoi(s); err == nil {
		if n >= 1 && n <= 12 {
			return n, 0, true
		}
		if y, m, ok := ParseDateToken(s); ok {
			return m, y, true
		}
		return 0, 0, false
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		if f == float64(int(f)) && f >= 1 && f <= 12 {
			return int(f), 0, true
		}
		if y, m, ok := ParseDateToken(s); ok {
			return m, y, true
		}
		return 0, 0, false
	}
	if y, m, ok := ParseDateToken(s); ok {
		return m, y, true
	}
	key := normalizeMonthKey(s)
	if m, ok := monthNameTable[key]; ok {
		return m, 0, true
	}
	// "Jan-26", "يناير 2026", "Sept 2025"
	if mm := reMonYear.FindStringSubmatch(key); mm != nil {
		if m, ok := monthNameTable[strings.TrimSpace(mm[1])]; ok {
			y, _ := strconv.Atoi(mm[2])
			if y < 100 {
				y += 2000
			}
			return m, y, true
		}
	}
	return 0, 0, false
}

// ParseYearToken accepts 2000..2100 (also "2026.0" and Arabic digits).
func ParseYearToken(raw string) (int, bool) {
	s := strings.TrimSpace(normalizeArabicDigitsToASCII(raw))
	if s == "" {
		return 0, false
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || f != float64(int(f)) {
		return 0, false
	}
	y := int(f)
	if y >= 2000 && y <= 2100 {
		return y, true
	}
	return 0, false
}

var reFileYear = regexp.MustCompile(`(?:^|[^\d])(20[2-3]\d)(?:[^\d]|$)`)
var reFileYY = regexp.MustCompile(`(?i)(?:^|[^a-z\d])(?:in|out|sales|sell[-_ ]?in|sell[-_ ]?out)[-_ ]?([2-3]\d)(?:[^\d]|$)`)

// YearFromFilename returns a year only when the filename names exactly one (2026, or "in26").
func YearFromFilename(filename string) (int, bool) {
	base := strings.ToLower(normalizeArabicDigitsToASCII(filename))
	found := map[int]bool{}
	for _, m := range reFileYear.FindAllStringSubmatch(base, -1) {
		y, _ := strconv.Atoi(m[1])
		found[y] = true
	}
	if len(found) == 0 {
		for _, m := range reFileYY.FindAllStringSubmatch(base, -1) {
			y, _ := strconv.Atoi(m[1])
			found[2000+y] = true
		}
	}
	if len(found) != 1 {
		return 0, false
	}
	for y := range found {
		return y, true
	}
	return 0, false
}

// UncachedFormulaReport lists formula cells that have no saved (cached) value. Such cells read as
// empty/0, so their sheet must be re-saved in Excel before upload.
type UncachedFormulaReport struct {
	Count int      `json:"count"`
	Cells []string `json:"cells"` // up to 10, "Sheet1!M12"
}

var reCellOpen = regexp.MustCompile(`<c\b([^>]*?)(/?)>`)
var reCellRef = regexp.MustCompile(`\br="([A-Z]+\d+)"`)

// FindUncachedFormulaCells scans every worksheet of an XLSX for <c><f>..</f></c> without a <v> value.
func FindUncachedFormulaCells(raw []byte) UncachedFormulaReport {
	var rep UncachedFormulaReport
	if !isZipArchive(raw) {
		return rep
	}
	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return rep
	}
	names := []*zip.File{}
	for _, f := range zr.File {
		n := strings.ToLower(f.Name)
		if strings.HasPrefix(n, "xl/worksheets/sheet") && strings.HasSuffix(n, ".xml") {
			names = append(names, f)
		}
	}
	sort.Slice(names, func(i, j int) bool { return names[i].Name < names[j].Name })
	for _, f := range names {
		rc, err := f.Open()
		if err != nil {
			continue
		}
		data, _ := io.ReadAll(rc)
		_ = rc.Close()
		if !bytes.Contains(data, []byte("<f")) {
			continue
		}
		sheet := strings.TrimSuffix(strings.TrimPrefix(f.Name, "xl/worksheets/"), ".xml")
		locs := reCellOpen.FindAllSubmatchIndex(data, -1)
		for _, loc := range locs {
			if loc[5] > loc[4] { // self-closing: no formula
				continue
			}
			bodyStart := loc[1]
			end := bytes.Index(data[bodyStart:], []byte("</c>"))
			if end < 0 {
				break
			}
			body := data[bodyStart : bodyStart+end]
			if !bytes.Contains(body, []byte("<f")) {
				continue
			}
			if bytes.Contains(body, []byte("<v>")) || bytes.Contains(body, []byte("<v ")) || bytes.Contains(body, []byte("<is>")) {
				continue
			}
			rep.Count++
			if len(rep.Cells) < 10 {
				ref := ""
				if m := reCellRef.FindSubmatch(data[loc[2]:loc[3]]); m != nil {
					ref = string(m[1])
				}
				rep.Cells = append(rep.Cells, fmt.Sprintf("%s!%s", sheet, ref))
			}
		}
	}
	return rep
}

// UncachedFormulaMessageAR is the Arabic rejection text for UncachedFormulaReport.
func UncachedFormulaMessageAR(rep UncachedFormulaReport) string {
	return fmt.Sprintf("الملف فيه %d خلية معادلة من غير قيمة محفوظة (زي %s)، فقيمتها هتتقري صفر. افتح الملف في إكسل واحفظه مرة تانية، وبعدين ارفعه.",
		rep.Count, strings.Join(rep.Cells, "، "))
}
