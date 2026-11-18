package gemini

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"hash/fnv"
	"io"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/branchnorm"
)

type xlsxWorkbookXML struct {
	Sheets []xlsxWorkbookSheet `xml:"sheets>sheet"`
}

type xlsxWorkbookSheet struct {
	Name    string `xml:"name,attr"`
	SheetID string `xml:"sheetId,attr"`
	State   string `xml:"state,attr"`
	RID     string `xml:"http://schemas.openxmlformats.org/officeDocument/2006/relationships id,attr"`
}

type xlsxRelsXML struct {
	Relationships []xlsxRelationship `xml:"Relationship"`
}

type xlsxRelationship struct {
	ID     string `xml:"Id,attr"`
	Target string `xml:"Target,attr"`
}

// BlankWideMatrixCategory is used when «المجموعة» is empty and Product Master
// does not supply a category. Competitor rows always keep it.
const BlankWideMatrixCategory = "منظفات وعناية منزلية"

// wideMatrixRecordCategory is the category stored on a Sell-Out, pricing, or OOS row.
// A non-empty «المجموعة» cell is kept for every supplier (already normalized).
// An empty cell stays empty on own-brand rows so ingestion can fall back to the
// Product Master category; competitor rows keep the shared placeholder.
func wideMatrixRecordCategory(normalizedSheetCategory string, ownBrand bool) string {
	if normalizedSheetCategory != "" {
		return normalizedSheetCategory
	}
	if ownBrand {
		return ""
	}
	return BlankWideMatrixCategory
}

type wideMatrixLayout struct {
	categoryIdx int
	supplierIdx int
	barcodeIdx  int
	skuIdx      int
	totalRevIdx int
	totalQtyIdx int // اجمالى كميات (file qty total; informational — branch qty cols are truth)
	monthIdx    int
	yearIdx     int
	dateIdx     int
	branches    []branchColumnPair
}

type branchColumnPair struct {
	rawBranchName string
	storeID       string
	displayName   string
	revColIdx     int
	qtyColIdx     int
}

type parsedSheetSummary struct {
	sheetName  string
	sheetDate  string
	state      string
	rows       [][]string
	layout     wideMatrixLayout
	isWide     bool
	adcoRev    float64
	adcoUnits  int
	marketRev  float64
	storeCount int
	// preferOverFullYear marks summaries from a month-named physical tab; those
	// win period-coverage dedupe against overlapping full-year / split periods.
	preferOverFullYear bool
}

// parseWideMatrixXLSX inspects an .xlsx archive for the Fathalla / Adco Wide Branch-Pivot Matrix structure
// (المجموعة | المورد | الباركود | الصنف | <Branches...> | الاجمالى | كمية <Branches...>).
// If matched, it extracts all branches, categories, competing suppliers, market share, unit selling prices,
// RRP prices, OOS alerts, and multi-sheet MoM/YoY trends.
func parseWideMatrixXLSX(filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, bool) {
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil, false
	}

	var sharedStrings []string
	fileByName := make(map[string]*zip.File)
	for _, f := range zr.File {
		lower := strings.ToLower(f.Name)
		fileByName[lower] = f
		if lower == "xl/sharedstrings.xml" {
			sharedStrings = readSharedStringsXML(f)
		}
	}

	sheetEntries := listOrderedWorkbookSheets(zr, fileByName)
	if len(sheetEntries) == 0 {
		return nil, false
	}

	sheetNames := make([]string, 0, len(sheetEntries))
	for _, entry := range sheetEntries {
		sheetNames = append(sheetNames, entry.name)
	}
	selection := buildSheetSelectionPlan(filename, sheetNames)

	var visibleWideSheets []parsedSheetSummary
	var allWideSheets []parsedSheetSummary
	var virtualEntries []wbSheetEntry

	for _, entry := range sheetEntries {
		// Open-sheet gate only: leftover other-year full-year dumps. Same-year
		// monthly vs yearly overlap is resolved by period coverage after parse.
		if !selection.shouldIncludeSheet(entry.name) {
			continue
		}
		sampleRows, err := readWorksheetSampleRows(entry.file, sharedStrings, wideMatrixHeaderScanRows+2)
		if err != nil || len(sampleRows) < 2 {
			continue
		}
		if _, _, ok := findWideMatrixHeaderRow(sampleRows, "fathalla"); !ok {
			continue
		}
		rows, err := readWorksheetXML(entry.file, sharedStrings)
		if err != nil {
			continue
		}
		// Exported pivot details often start with a title row ("Details for Sum of ...") and a blank row
		// before the real header, so locate the header and drop everything above it.
		layout, headerIdx, ok := findWideMatrixHeaderRow(rows, "fathalla")
		if !ok {
			continue
		}
		rows = rows[headerIdx:]
		if len(rows) < 2 {
			continue
		}

		// Smart AI Column-Content Inference: scan sample rows to auto-detect Year, Month, or Date columns
		// even if their headers were unlabeled, non-standard, or placed anywhere in the sheet.
		inferTemporalColumnsFromData(rows, &layout)

		preferMonthly := isMonthNamedSheetName(entry.name)

		// If a single wide sheet contains multiple months/years across rows (e.g. "2025 out.xlsx" with MONTH=jan,feb,mar,apr and YEAR=2025),
		// split it into virtual chronological monthly sheets so every month is preserved with 100% accuracy!
		splitSummaries := splitWideSheetByRowPeriods(filename, entry.name, entry.state, rows, layout)
		if len(splitSummaries) > 0 {
			for _, sub := range splitSummaries {
				sub.preferOverFullYear = preferMonthly
				allWideSheets = append(allWideSheets, sub)
				if entry.state != "hidden" {
					visibleWideSheets = append(visibleWideSheets, sub)
				}
				virtualEntries = append(virtualEntries, wbSheetEntry{
					name:  sub.sheetName,
					state: sub.state,
					file:  entry.file,
				})
			}
			continue
		}

		fileYear := inferYearFromText(entry.name, inferYearFromText(filename, 0))
		sheetDate := tryParseArabicSheetMonthDate(entry.name, fileYear)
		if sheetDate == "" {
			sheetDate = tryParseArabicSheetMonthDate(filename, fileYear)
		}
		if sheetDate == "" {
			if fileYear >= 2020 && fileYear <= 2035 {
				sheetDate = fmt.Sprintf("%04d-01-31", fileYear)
			} else {
				sheetDate = time.Now().Format("2006-01-02")
			}
		}

		summary := parsedSheetSummary{
			sheetName:          entry.name,
			sheetDate:          sheetDate,
			state:              entry.state,
			rows:               rows,
			layout:             layout,
			isWide:             true,
			storeCount:         len(layout.branches),
			preferOverFullYear: preferMonthly,
		}
		// Compute quick monthly totals for trend & MoM/YoY
		computeQuickSheetTotals(&summary)
		allWideSheets = append(allWideSheets, summary)
		if entry.state != "hidden" {
			visibleWideSheets = append(visibleWideSheets, summary)
		}
		virtualEntries = append(virtualEntries, entry)
	}

	if len(allWideSheets) == 0 {
		return nil, false
	}

	// Prefer valid month-named periods; keep uncovered months from full-year dumps.
	allWideSheets = dedupeSheetsByPeriodCoverage(allWideSheets)
	visibleWideSheets = dedupeSheetsByPeriodCoverage(visibleWideSheets)
	if len(allWideSheets) == 0 {
		return nil, false
	}

	// Include all wide monthly sheets (2024, 2025, 2026) so every year/month filter has complete records
	activeSheets := allWideSheets

	// Primary sheet is the latest visible monthly sheet in the workbook (e.g., يناير 26)
	primary := activeSheets[len(activeSheets)-1]
	if len(visibleWideSheets) > 0 {
		primary = visibleWideSheets[len(visibleWideSheets)-1]
	}
	effectiveEntries := sheetEntries
	if len(virtualEntries) > len(sheetEntries) {
		effectiveEntries = virtualEntries
	}
	return buildPayloadFromWideMatrix(filename, primary, activeSheets, allWideSheets, effectiveEntries)
}

// parseWideMatrixCSV checks if a CSV/TSV table uses the Wide Branch-Pivot Matrix format and parses it.
func parseWideMatrixCSV(filename string, rows [][]string) (*domain.NormalizedRetailIngestionPayload, bool) {
	if len(rows) < 2 {
		return nil, false
	}
	layout, headerIdx, ok := findWideMatrixHeaderRow(rows, "fathalla")
	if !ok {
		return nil, false
	}
	rows = rows[headerIdx:]
	if len(rows) < 2 {
		return nil, false
	}
	inferTemporalColumnsFromData(rows, &layout)
	splitSummaries := splitWideSheetByRowPeriods(filename, "Sheet1", "visible", rows, layout)
	if len(splitSummaries) > 0 {
		var entries []wbSheetEntry
		for _, sub := range splitSummaries {
			entries = append(entries, wbSheetEntry{name: sub.sheetName, state: "visible"})
		}
		primary := splitSummaries[len(splitSummaries)-1]
		return buildPayloadFromWideMatrix(filename, primary, splitSummaries, splitSummaries, entries)
	}
	fileYear := inferYearFromText(filename, 0)
	sheetDate := tryParseArabicSheetMonthDate(filename, fileYear)
	if sheetDate == "" {
		if fileYear >= 2020 && fileYear <= 2035 {
			sheetDate = fmt.Sprintf("%04d-01-31", fileYear)
		} else {
			sheetDate = time.Now().Format("2006-01-02")
		}
	}
	primary := parsedSheetSummary{
		sheetName:  "Sheet1",
		sheetDate:  sheetDate,
		state:      "visible",
		rows:       rows,
		layout:     layout,
		isWide:     true,
		storeCount: len(layout.branches),
	}
	computeQuickSheetTotals(&primary)
	return buildPayloadFromWideMatrix(filename, primary, []parsedSheetSummary{primary}, []parsedSheetSummary{primary}, []wbSheetEntry{{name: "Sheet1", state: "visible"}})
}

// wideMatrixHeaderScanRows is how many leading rows are searched for the wide-matrix header.
const wideMatrixHeaderScanRows = 10

// findWideMatrixHeaderRow returns the layout and index of the first row (within the first
// wideMatrixHeaderScanRows rows) that looks like a wide branch-pivot header.
func findWideMatrixHeaderRow(rows [][]string, retailer string) (wideMatrixLayout, int, bool) {
	for i := 0; i < len(rows) && i < wideMatrixHeaderScanRows; i++ {
		if layout, ok := detectWideMatrixHeader(rows[i], retailer); ok {
			return layout, i, true
		}
	}
	return wideMatrixLayout{}, -1, false
}

type wbSheetEntry struct {
	name  string
	state string
	file  *zip.File
}

func listOrderedWorkbookSheets(zr *zip.Reader, fileByName map[string]*zip.File) []wbSheetEntry {
	wbFile := fileByName["xl/workbook.xml"]
	relsFile := fileByName["xl/_rels/workbook.xml.rels"]
	if wbFile != nil && relsFile != nil {
		wbBytes := readZipBytes(wbFile)
		relsBytes := readZipBytes(relsFile)
		var wb xlsxWorkbookXML
		var rels xlsxRelsXML
		if xml.Unmarshal(wbBytes, &wb) == nil && xml.Unmarshal(relsBytes, &rels) == nil {
			ridMap := make(map[string]string)
			for _, r := range rels.Relationships {
				target := strings.TrimPrefix(strings.ToLower(r.Target), "/")
				if !strings.HasPrefix(target, "xl/") {
					target = "xl/" + target
				}
				ridMap[r.ID] = target
			}
			var result []wbSheetEntry
			for _, s := range wb.Sheets {
				target := ridMap[s.RID]
				if f, ok := fileByName[target]; ok {
					state := strings.ToLower(strings.TrimSpace(s.State))
					if state == "" {
						state = "visible"
					}
					result = append(result, wbSheetEntry{
						name:  strings.TrimSpace(s.Name),
						state: state,
						file:  f,
					})
				}
			}
			if len(result) > 0 {
				return result
			}
		}
	}

	// Fallback if workbook.xml is absent (e.g. synthetic single-sheet test archive)
	var fallback []wbSheetEntry
	for _, f := range zr.File {
		lower := strings.ToLower(f.Name)
		if strings.HasPrefix(lower, "xl/worksheets/sheet") && strings.HasSuffix(lower, ".xml") {
			fallback = append(fallback, wbSheetEntry{
				name:  f.Name,
				state: "visible",
				file:  f,
			})
		}
	}
	return fallback
}

func readSharedStringsXML(f *zip.File) []string {
	data := readZipBytes(f)
	if len(data) == 0 {
		return nil
	}
	return readSharedStringsFast(data)
}

func readZipBytes(f *zip.File) []byte {
	rc, err := f.Open()
	if err != nil {
		return nil
	}
	defer rc.Close()
	b, _ := io.ReadAll(rc)
	return b
}

// detectWideMatrixHeader detects if a header row follows the wide branch-pivot structure:
// Col A: المجموعة, Col B: المورد, Col C: الباركود, Col D: الصنف, Cols E..N: Branches, Col Total: الاجمالى, Cols Qty: كمية <Branch>
func detectWideMatrixHeader(headerRow []string, retailer string) (wideMatrixLayout, bool) {
	layout := wideMatrixLayout{
		categoryIdx: -1,
		supplierIdx: -1,
		barcodeIdx:  -1,
		skuIdx:      -1,
		totalRevIdx: -1,
		totalQtyIdx: -1,
		monthIdx:    -1,
		yearIdx:     -1,
		dateIdx:     -1,
	}
	if len(headerRow) < 6 {
		return layout, false
	}

	for idx, raw := range headerRow {
		h := strings.TrimSpace(strings.TrimPrefix(raw, "\uFEFF"))
		if h == "" {
			continue
		}
		hLower := strings.ToLower(h)
		switch {
		case layout.categoryIdx < 0 && (h == "المجموعة" || h == "المجموعه" || h == "الفئة" || strings.EqualFold(h, "Group") || strings.EqualFold(h, "Category")):
			layout.categoryIdx = idx
		case layout.supplierIdx < 0 && (h == "المورد" || h == "الشركة الموردة" || h == "المصنع" || strings.EqualFold(h, "Supplier") || strings.EqualFold(h, "Vendor")):
			layout.supplierIdx = idx
		case layout.barcodeIdx < 0 && (h == "الباركود" || h == "باركود" || strings.EqualFold(h, "Barcode") || strings.EqualFold(h, "GTIN")):
			layout.barcodeIdx = idx
		case layout.skuIdx < 0 && (h == "الصنف" || h == "اسم الصنف" || strings.EqualFold(h, "Item") || strings.EqualFold(h, "SKU")):
			layout.skuIdx = idx
		case layout.totalQtyIdx < 0 && idx > 3 && isTotalQuantityHeader(h):
			layout.totalQtyIdx = idx
		case layout.totalRevIdx < 0 && idx > 3 && !isTotalQuantityHeader(h) && (strings.Contains(h, "الاجمال") || strings.Contains(h, "الإجمال") || strings.Contains(h, "اجمالى") || strings.Contains(h, "إجمالي") || strings.EqualFold(h, "Total")):
			layout.totalRevIdx = idx
		case layout.monthIdx < 0 && (hLower == "month" || hLower == "months" || hLower == "sales month" || h == "الشهر" || h == "شهر" || h == "شهر البيع"):
			layout.monthIdx = idx
		case layout.yearIdx < 0 && (hLower == "year" || hLower == "years" || hLower == "sales year" || h == "السنة" || h == "السنه" || h == "سنة" || h == "سنه" || h == "العام" || h == "عام"):
			layout.yearIdx = idx
		case layout.dateIdx < 0 && (hLower == "date" || hLower == "transaction date" || hLower == "sales date" || h == "التاريخ" || h == "تاريخ" || h == "تاريخ البيع" || h == "تاريخ الحركة"):
			layout.dateIdx = idx
		}
	}

	// Require Barcode, SKU, and either Total column or multiple quantity columns ("كمية ...")
	if layout.barcodeIdx < 0 || layout.skuIdx < 0 || layout.totalRevIdx <= layout.skuIdx+1 {
		return layout, false
	}

	// Collect quantity columns after totalRevIdx (skip MONTH/YEAR/DATE and اجمالى كميات)
	qtyColByNormBranch := make(map[string]int)
	var orderedQtyCols []int
	for idx := layout.totalRevIdx + 1; idx < len(headerRow); idx++ {
		if idx == layout.monthIdx || idx == layout.yearIdx || idx == layout.dateIdx || idx == layout.totalQtyIdx {
			continue
		}
		h := strings.TrimSpace(headerRow[idx])
		if h == "" || isTotalQuantityHeader(h) {
			if isTotalQuantityHeader(h) && layout.totalQtyIdx < 0 {
				layout.totalQtyIdx = idx
			}
			continue
		}
		if strings.HasPrefix(h, "كمية") || strings.HasPrefix(h, "كميه") || strings.HasPrefix(strings.ToLower(h), "qty") {
			orderedQtyCols = append(orderedQtyCols, idx)
			branchPart := strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(h, "كمية"), "كميه"))
			branchPart = strings.TrimSpace(strings.TrimPrefix(strings.ToLower(branchPart), "qty"))
			qtyColByNormBranch[normalizeBranchKey(branchPart)] = idx
		}
	}

	// Collect branch revenue columns between skuIdx+1 and totalRevIdx-1
	startBranchIdx := layout.skuIdx + 1
	branchSeq := 0
	for idx := startBranchIdx; idx < layout.totalRevIdx; idx++ {
		if idx == layout.monthIdx || idx == layout.yearIdx || idx == layout.dateIdx {
			continue
		}
		rawBranch := strings.TrimSpace(headerRow[idx])
		if rawBranch == "" {
			continue
		}
		normKey := normalizeBranchKey(rawBranch)
		qtyIdx := -1
		if matchedQtyIdx, ok := qtyColByNormBranch[normKey]; ok {
			qtyIdx = matchedQtyIdx
		} else if branchSeq < len(orderedQtyCols) {
			qtyIdx = orderedQtyCols[branchSeq]
		}
		branchSeq++

		storeMeta := BuildBranchStoreMetadata(retailer, rawBranch)
		layout.branches = append(layout.branches, branchColumnPair{
			rawBranchName: rawBranch,
			storeID:       storeMeta.ID,
			displayName:   storeMeta.BranchName,
			revColIdx:     idx,
			qtyColIdx:     qtyIdx,
		})
	}

	if len(layout.branches) == 0 {
		return layout, false
	}
	return layout, true
}

// Shared across every Sell-In / Sell-Out row: rebuilding NewReplacer per call was measurable on
// large GP SOP exports (in26 ≈ 40k rows × 2 BuildBranchStoreMetadata calls).
var branchKeyReplacer = strings.NewReplacer(
	" ", "",
	"-", "",
	"_", "",
	"أ", "ا",
	"إ", "ا",
	"آ", "ا",
	"ى", "ي",
	"ة", "ه",
)

func normalizeBranchKey(s string) string {
	cleaned := strings.TrimSpace(s)
	for _, prefix := range []string{
		"فرع فتح الله -", "فرع فتح الله",
		"فرع كارفور -", "فرع كارفور",
		"فرع جملة ماركت -", "فرع جملة ماركت",
		"فرع سبينيس -", "فرع سبينيس",
		"فتح الله -", "كارفور -",
	} {
		cleaned = strings.TrimSpace(strings.TrimPrefix(cleaned, prefix))
	}
	return strings.ToLower(branchKeyReplacer.Replace(cleaned))
}

type knownBranchSlug struct {
	slug, gov, city string
}

// knownBranchSlugMap is built once: previously BuildBranchStoreMetadata rebuilt this map (and
// re-normalized every key) on each of ~80k calls for in26.xlsx — the dominant cost before
// data-quality / product-match / BQ upsert on Adeco prod (~5 min of a 5m37s job).
var knownBranchSlugMap = map[string]knownBranchSlug{
	normalizeBranchKey("سموحة"):                  {"smouha", "الإسكندرية", "سموحة"},
	normalizeBranchKey("سموحة ميني"):             {"smouha_mini", "الإسكندرية", "سموحة"},
	normalizeBranchKey("جاردينيا"):               {"gardenia", "الإسكندرية", "جاردينيا"},
	normalizeBranchKey("هانوفيل"):                {"hanoville", "الإسكندرية", "العجمي - هانوفيل"},
	normalizeBranchKey("نهال فيل"):               {"hanoville", "الإسكندرية", "العجمي - هانوفيل"},
	normalizeBranchKey("أكتوبر"):                 {"october", "الجيزة", "السادس من أكتوبر"},
	normalizeBranchKey("طنطا"):                   {"tanta", "الغربية", "طنطا"},
	normalizeBranchKey("طنطا - اوت ليت مول"):     {"tanta_outlet", "الغربية", "طنطا"},
	normalizeBranchKey("عجمي ستار"):              {"agamy_star", "الإسكندرية", "العجمي"},
	normalizeBranchKey("الإبراهيمية"):            {"ibrahimia", "الإسكندرية", "الإبراهيمية"},
	normalizeBranchKey("الإبراهيمية ميني"):       {"ibrahimia_mini", "الإسكندرية", "الإبراهيمية"},
	normalizeBranchKey("سيدي جابر ميني"):         {"sidi_gaber_mini", "الإسكندرية", "سيدي جابر"},
	normalizeBranchKey("سيدي جابر المحطة"):       {"sidi_gaber_station", "الإسكندرية", "سيدي جابر"},
	normalizeBranchKey("كفر الدوار"):             {"kafr_eldawar", "البحيرة", "كفر الدوار"},
	normalizeBranchKey("كفر الدوار - مول"):       {"kafr_eldawar_mall", "البحيرة", "كفر الدوار"},
	normalizeBranchKey("مطروح"):                  {"matrouh", "مرسى مطروح", "مطروح"},
	normalizeBranchKey("دمنهور الأندلس"):         {"damanhour_andalus", "البحيرة", "دمنهور"},
	normalizeBranchKey("دمنهور - الاستاد"):       {"damanhour_stadium", "البحيرة", "دمنهور"},
	normalizeBranchKey("الأنفوشي"):               {"anfoushy", "الإسكندرية", "الأنفوشي"},
	normalizeBranchKey("المحلة الكبرى"):          {"mahalla", "الغربية", "المحلة الكبرى"},
	normalizeBranchKey("فلمنج"):                  {"fleming", "الإسكندرية", "فلمنج"},
	normalizeBranchKey("الدخيلة ميني"):           {"dekheila_mini", "الإسكندرية", "الدخيلة"},
	normalizeBranchKey("الدخيلة مينى 2"):         {"dekheila_mini_2", "الإسكندرية", "الدخيلة"},
	normalizeBranchKey("سيدي بشر ميني"):          {"sidi_bishr_mini", "الإسكندرية", "سيدي بشر"},
	normalizeBranchKey("روزانا"):                 {"rozana", "الإسكندرية", "سموحة - روزانا"},
	normalizeBranchKey("النصر"):                  {"elnasr", "الإسكندرية", "شارع النصر"},
	normalizeBranchKey("طوسون"):                  {"toson", "الإسكندرية", "أبو قير - طوسون"},
	normalizeBranchKey("ابو يوسف"):               {"abu_youssef", "الإسكندرية", "العجمي - أبو يوسف"},
	normalizeBranchKey("ستانلى"):                 {"stanley", "الإسكندرية", "ستانلي"},
	normalizeBranchKey("ستانلي"):                 {"stanley", "الإسكندرية", "ستانلي"},
	normalizeBranchKey("أمواج - الساحل الشمالي"): {"amwaj_north_coast", "الساحل الشمالي", "أمواج"},
	normalizeBranchKey("ملك حفنى"):               {"malak_hefny", "الإسكندرية", "ملك حفني"},
	normalizeBranchKey("سيتي سكوير"):             {"city_square", "الإسكندرية", "سيتي سكوير"},
	normalizeBranchKey("مدينة الرحاب"):           {"rehab_city", "القاهرة", "مدينة الرحاب"},
	normalizeBranchKey("نيس2"):                   {"nice_2", "الإسكندرية", "نيس"},
	normalizeBranchKey("دمياط الجديدة"):          {"new_damietta", "دمياط", "دمياط الجديدة"},
	normalizeBranchKey("المعادي"):                {"maadi", "القاهرة", "المعادي"},
	normalizeBranchKey("الدقي"):                  {"dokki", "الجيزة", "الدقي"},
	normalizeBranchKey("مدينة نصر"):              {"nasr_city", "القاهرة", "مدينة نصر"},
}

// BuildBranchStoreMetadata maps any raw branch name from Excel (or creates a new deterministic branch)
// with full Egyptian geographic classification (Governorate, City, StoreID, DisplayName).
// Arabic/English abbreviations are expanded via branchnorm before the frozen slug lookup.
func BuildBranchStoreMetadata(retailer, rawBranch string) domain.Store {
	clean := strings.TrimSpace(rawBranch)
	if clean == "" {
		clean = "سموحة"
	}
	chain := strings.ToLower(strings.TrimSpace(retailer))
	if chain == "" || chain == "unknown" {
		chain = "fathalla"
	}

	// Synthetic reconciliation bucket for value not present in any named branch column.
	if isUnallocatedBranchName(clean) {
		prefix := "fat"
		switch chain {
		case "carrefour":
			prefix = "crf"
		case "gomla":
			prefix = "gom"
		case "beet-elgomla", "beet_elgomla":
			prefix = "bet"
		case "spinneys":
			prefix = "spi"
		case "metro":
			prefix = "met"
		case "seoudi":
			prefix = "seo"
		case "kazyon":
			prefix = "kaz"
		default:
			if chain != "fathalla" {
				if p := storeIDPrefixForChain(chain); p != "" {
					prefix = p
				}
			}
		}
		return domain.Store{
			ID:          fmt.Sprintf("%s_unallocated", prefix),
			Chain:       chain,
			BranchName:  UnallocatedBranchName,
			Governorate: "غير محدد",
			City:        UnallocatedBranchName,
			IsActive:    true,
		}
	}

	// Phase A5: expand abbreviations / English → canonical Arabic short name.
	var bn branchnorm.Result
	if canon, known, r := canonicalizeBranchForStore(clean); known {
		clean = canon
		bn = r
	} else {
		bn = r
	}

	norm := normalizeBranchKey(clean)

	prefix := "fat"
	chainLabel := "فرع فتح الله"
	switch chain {
	case "carrefour":
		prefix = "crf"
		chainLabel = "فرع كارفور"
	case "gomla":
		prefix = "gom"
		chainLabel = "فرع جملة ماركت"
	case "beet-elgomla", "beet_elgomla":
		prefix = "bet"
		chainLabel = "فرع بيت الجملة"
	case "spinneys":
		prefix = "spi"
		chainLabel = "فرع سبينيس"
	case "metro":
		prefix = "met"
		chainLabel = "فرع مترو"
	case "seoudi":
		prefix = "seo"
		chainLabel = "فرع سعودي"
	case "kazyon":
		prefix = "kaz"
		chainLabel = "فرع كازيون"
	default:
		// Prefixes above are frozen: existing StoreIDs (fat_/gom_/bet_/...) must never change.
		// Rows of Zahran / El Wakala etc. uploaded under the fathalla file keep fat_.
		if chain != "fathalla" {
			if p := storeIDPrefixForChain(chain); p != "" {
				prefix = p
				chainLabel = "فرع " + chain
			}
		}
	}

	displayName := clean
	if !strings.Contains(clean, "فتح الله") && !strings.Contains(clean, "كارفور") && !strings.Contains(clean, "سبينيس") && !strings.Contains(clean, "جملة") && !strings.HasPrefix(clean, "فرع") {
		displayName = fmt.Sprintf("%s - %s", chainLabel, clean)
	}

	if info, ok := knownBranchSlugMap[norm]; ok {
		return domain.Store{
			ID:          fmt.Sprintf("%s_%s", prefix, info.slug),
			Chain:       chain,
			BranchName:  displayName,
			Governorate: info.gov,
			City:        info.city,
			IsActive:    true,
		}
	}

	// branchnorm knew a slug that isn't in the legacy map yet — still use frozen slug form.
	if bn.Slug != "" {
		gov := bn.Governorate
		city := bn.City
		if gov == "" {
			gov = inferGovernorateFromBranch(clean)
		}
		if city == "" {
			city = clean
		}
		return domain.Store{
			ID:          fmt.Sprintf("%s_%s", prefix, bn.Slug),
			Chain:       chain,
			BranchName:  displayName,
			Governorate: gov,
			City:        city,
			IsActive:    true,
		}
	}

	// Dynamic auto-creation for ANY previously unseen branch name in the Excel file!
	h := fnv.New32a()
	_, _ = h.Write([]byte(norm))
	storeID := fmt.Sprintf("%s_auto_%x", prefix, h.Sum32())
	gov := inferGovernorateFromBranch(clean)

	return domain.Store{
		ID:          storeID,
		Chain:       chain,
		BranchName:  displayName,
		Governorate: gov,
		City:        clean,
		IsActive:    true,
	}
}

func inferGovernorateFromBranch(branch string) string {
	switch {
	case strings.Contains(branch, "أكتوبر") || strings.Contains(branch, "زايد") || strings.Contains(branch, "الجيزة"):
		return "الجيزة"
	case strings.Contains(branch, "الرحاب") || strings.Contains(branch, "القاهرة") || strings.Contains(branch, "المعادي") || strings.Contains(branch, " التجمع"):
		return "القاهرة"
	case strings.Contains(branch, "طنطا") || strings.Contains(branch, "المحلة"):
		return "الغربية"
	case strings.Contains(branch, "دمنهور") || strings.Contains(branch, "كفر الدوار"):
		return "البحيرة"
	case strings.Contains(branch, "مطروح") || strings.Contains(branch, "الساحل") || strings.Contains(branch, "أمواج"):
		return "مرسى مطروح والساحل"
	case strings.Contains(branch, "دمياط"):
		return "دمياط"
	default:
		return "الإسكندرية"
	}
}

func computeQuickSheetTotals(summary *parsedSheetSummary) {
	layout := summary.layout
	for rIdx := 1; rIdx < len(summary.rows); rIdx++ {
		row := summary.rows[rIdx]
		if isRowEmpty(row) {
			continue
		}
		sup := getCell(row, layout.supplierIdx)
		totRev := parseRevenueFloat(getCell(row, layout.totalRevIdx))
		if totRev == 0 {
			for _, b := range layout.branches {
				totRev += parseRevenueFloat(getCell(row, b.revColIdx))
			}
		}
		summary.marketRev += totRev
		if isAdcoOrTenantSupplier(sup) {
			summary.adcoRev += totRev
			var rowUnits int
			for _, b := range layout.branches {
				rowUnits += parseQuantityInt(getCell(row, b.qtyColIdx))
			}
			summary.adcoUnits += rowUnits
		}
	}
}

func isAdcoOrTenantSupplier(sup string) bool {
	s := strings.ToLower(strings.TrimSpace(sup))
	if s == "" {
		return true // If no supplier column exists, treat rows as tenant's own SKUs
	}
	// Canonical display is «ادكو»; keep legacy ياء/hamza spellings as input aliases only.
	return strings.Contains(s, "ادكو") ||
		strings.Contains(s, "أدكو") ||
		strings.Contains(s, "اديكو") ||
		strings.Contains(s, "أديكو") ||
		strings.Contains(s, "إديكو") ||
		strings.Contains(s, "أيديكو") ||
		strings.Contains(s, "ايديكو") ||
		strings.Contains(s, "آديكو") ||
		strings.Contains(s, "adco") ||
		strings.Contains(s, "adeco") ||
		strings.Contains(s, "الإسكندرية للمنظفات") ||
		strings.Contains(s, "الاسكندرية للمنظفات")
}

func parseArabicSheetMonthDate(sheetName string) string {
	if d := tryParseArabicSheetMonthDate(sheetName, 0); d != "" {
		return d
	}
	return time.Now().Format("2006-01-02")
}

// inferYearFromText scans any string (filename, sheet name, cell value) for a 4-digit year (2020..2035) or trailing 2-digit year.
func inferYearFromText(s string, fallback int) int {
	clean := normalizeArabicDigitsToASCII(strings.TrimSpace(s))
	if clean == "" {
		return fallback
	}
	for yr := 2020; yr <= 2035; yr++ {
		if strings.Contains(clean, fmt.Sprintf("%d", yr)) {
			return yr
		}
	}
	// Check exact 2-digit year or suffix like "يناير 25", "sale out 25", "24", "25", "26"
	if len(clean) == 2 {
		var y2 int
		if _, err := fmt.Sscanf(clean, "%d", &y2); err == nil && y2 >= 20 && y2 <= 35 {
			return 2000 + y2
		}
	}
	for y2 := 20; y2 <= 35; y2++ {
		suf := fmt.Sprintf("%d", y2)
		if strings.HasSuffix(clean, " "+suf) || strings.HasSuffix(clean, "-"+suf) || strings.HasSuffix(clean, "_"+suf) || strings.HasSuffix(clean, "/"+suf) {
			return 2000 + y2
		}
		if strings.HasSuffix(clean, suf) && len(clean) > 2 {
			prev := clean[len(clean)-3]
			if prev < '0' || prev > '9' {
				return 2000 + y2
			}
		}
	}
	return fallback
}

func normalizeArabicDigitsToASCII(s string) string {
	var sb strings.Builder
	sb.Grow(len(s))
	for _, r := range s {
		if r >= '٠' && r <= '٩' {
			sb.WriteByte(byte('0' + (r - '٠')))
		} else {
			sb.WriteRune(r)
		}
	}
	return sb.String()
}

// parseSmartMonthToken recognizes English/Arabic full month names, 2/3-letter prefixes (ja, fe, ma, ap, ju, jl, au, se, oc, no, de),
// Franco-Arabic transliterations (yanayer, febrayer...), and numeric months (1..12 or "شهر 7").
func parseSmartMonthToken(raw string) int {
	clean := normalizeArabicDigitsToASCII(strings.ToLower(strings.TrimSpace(raw)))
	if clean == "" {
		return 0
	}

	monthKeywords := []struct {
		keywords []string
		month    int
	}{
		{[]string{"يناير", "ينابر", "كانون الثاني", "كانون ثاني", "january", "jan", "yanayer"}, 1},
		{[]string{"فبراير", "فبرير", "شباط", "february", "feb", "febrayer"}, 2},
		{[]string{"مارس", "آذار", "اذار", "march", "mar", "mares"}, 3},
		{[]string{"ابريل", "أبريل", "إبريل", "نيسان", "april", "apr", "abril"}, 4},
		{[]string{"مايو", "ماي", "أيار", "ايار", "may", "mayo"}, 5},
		{[]string{"يونيه", "يونيو", "حزيران", "june", "jun", "yonyo"}, 6},
		{[]string{"يوليو", "يوليه", "تموز", "july", "jul", "yolyo"}, 7},
		{[]string{"اغسطس", "أغسطس", "إغسطس", "آب", "اب", "august", "aug", "aghostos"}, 8},
		{[]string{"سبتمبر", "أيلول", "ايلول", "september", "sept", "sep", "seb"}, 9},
		{[]string{"اكتوبر", "أكتوبر", "إكتوبر", "تشرين الأول", "تشرين اول", "october", "oct"}, 10},
		{[]string{"نوفمبر", "تشرين الثاني", "تشرين ثاني", "november", "nov"}, 11},
		{[]string{"ديسمبر", "كانون الأول", "كانون اول", "december", "dec"}, 12},
	}

	for _, m := range monthKeywords {
		for _, kw := range m.keywords {
			if strings.Contains(clean, kw) {
				return m.month
			}
		}
	}

	// Exact 2-letter English or Arabic month abbreviations when a cell contains just a short code
	twoLetterMap := map[string]int{
		"ja": 1, "ينا": 1,
		"fe": 2, "فبر": 2,
		"mr": 3, "مار": 3,
		"ap": 4, "ابر": 4, "أبر": 4,
		"my": 5, "ماي": 5,
		"jn": 6, "يون": 6,
		"jl": 7, "يول": 7,
		"au": 8, "اغس": 8, "أغس": 8,
		"se": 9, "سبت": 9,
		"oc": 10, "اكت": 10, "أكت": 10,
		"no": 11, "نوف": 11,
		"de": 12, "ديس": 12,
	}
	if m, ok := twoLetterMap[clean]; ok {
		return m
	}

	// Support "شهر 7", "month 7", "m7", "m07"
	for _, marker := range []string{"شهر", "month"} {
		if idx := strings.Index(clean, marker); idx >= 0 {
			rest := strings.TrimSpace(clean[idx+len(marker):])
			numStr := ""
			for _, r := range rest {
				if r >= '0' && r <= '9' {
					numStr += string(r)
				} else if numStr != "" {
					break
				} else if r == ' ' || r == '-' || r == '_' || r == ':' {
					continue
				} else {
					break
				}
			}
			if numStr != "" {
				var mVal int
				_, _ = fmt.Sscanf(numStr, "%d", &mVal)
				if mVal >= 1 && mVal <= 12 {
					return mVal
				}
			}
		}
	}

	// Support standalone numeric month (1..12 or 01..12) when raw string is purely 1-2 digits
	if len(clean) <= 2 {
		var mVal int
		if _, err := fmt.Sscanf(clean, "%d", &mVal); err == nil && mVal >= 1 && mVal <= 12 {
			return mVal
		}
	}

	return 0
}

func tryParseArabicSheetMonthDate(sheetName string, defaultYear int) string {
	s := strings.TrimSpace(sheetName)
	if s == "" {
		return ""
	}
	monthLastDays := [13]int{0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

	detectedMonth := parseSmartMonthToken(s)
	// Avoid matching pure numbers in filenames (like "40-Adco") as a month unless it's 1..12 alone or with month words
	if detectedMonth == 0 {
		return ""
	}
	lastDay := monthLastDays[detectedMonth]

	detectedYear := 2026
	if defaultYear >= 2020 && defaultYear <= 2035 {
		detectedYear = defaultYear
	}
	detectedYear = inferYearFromText(s, detectedYear)

	return fmt.Sprintf("%04d-%02d-%02d", detectedYear, detectedMonth, lastDay)
}

// inferTemporalColumnsFromData inspects up to 200 sample rows across all columns to automatically discover
// Year, Month, or Date columns by their cell values even if column headers were arbitrary, missing, or in unexpected positions.
func inferTemporalColumnsFromData(rows [][]string, layout *wideMatrixLayout) {
	if len(rows) < 2 || layout == nil {
		return
	}
	headerRow := rows[0]
	numCols := len(headerRow)
	for i := 1; i < len(rows) && i <= 50; i++ {
		if len(rows[i]) > numCols {
			numCols = len(rows[i])
		}
	}

	// Mark columns that are already bound to core fields or branch revenue/quantity
	boundCols := make(map[int]bool)
	boundCols[layout.categoryIdx] = true
	boundCols[layout.supplierIdx] = true
	boundCols[layout.barcodeIdx] = true
	boundCols[layout.skuIdx] = true
	boundCols[layout.totalRevIdx] = true
	for _, b := range layout.branches {
		if b.qtyColIdx >= 0 {
			boundCols[b.qtyColIdx] = true
		}
	}

	sampleLimit := len(rows)
	if sampleLimit > 250 {
		sampleLimit = 250
	}

	for colIdx := 0; colIdx < numCols; colIdx++ {
		if boundCols[colIdx] || colIdx == layout.monthIdx || colIdx == layout.yearIdx || colIdx == layout.dateIdx {
			continue
		}
		hText := ""
		if colIdx < len(headerRow) {
			hText = strings.ToLower(strings.TrimSpace(headerRow[colIdx]))
		}
		// Do not hijack total quantity column
		if strings.Contains(hText, "اجمال") || strings.Contains(hText, "إجمال") || strings.Contains(hText, "total") {
			continue
		}

		nonEmpty := 0
		yearHits := 0
		monthTextHits := 0
		dateHits := 0

		for rIdx := 1; rIdx < sampleLimit; rIdx++ {
			val := getCell(rows[rIdx], colIdx)
			if val == "" {
				continue
			}
			nonEmpty++
			clean := normalizeArabicDigitsToASCII(strings.TrimSpace(val))

			// 1. Check if cell is a 4-digit year (e.g. 2024, 2025, 2026)
			if len(clean) == 4 {
				var yr int
				if _, err := fmt.Sscanf(clean, "%d", &yr); err == nil && yr >= 2020 && yr <= 2035 {
					yearHits++
					continue
				}
			}

			// 2. Check if cell is a textual month name or abbreviation (e.g. jan, feb, mar, apr, يناير, فبراير, شهر 7)
			hasLetters := false
			for _, r := range clean {
				if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= 0x0600 && r <= 0x06FF) {
					hasLetters = true
					break
				}
			}
			if hasLetters && parseSmartMonthToken(clean) > 0 {
				monthTextHits++
				continue
			}

			// 3. Check if cell is a full ISO/slash date (e.g. 2025-01-31, 15/02/2025)
			if len(clean) >= 8 && (strings.Contains(clean, "-") || strings.Contains(clean, "/")) {
				if d := normalizeDateString(clean, ""); d != "" {
					dateHits++
				}
			}
		}

		if nonEmpty < 3 {
			continue
		}

		if layout.yearIdx < 0 && float64(yearHits)/float64(nonEmpty) >= 0.85 {
			layout.yearIdx = colIdx
			removeBranchByColIdx(layout, colIdx)
		} else if layout.monthIdx < 0 && float64(monthTextHits)/float64(nonEmpty) >= 0.80 {
			layout.monthIdx = colIdx
			removeBranchByColIdx(layout, colIdx)
		} else if layout.dateIdx < 0 && float64(dateHits)/float64(nonEmpty) >= 0.80 {
			layout.dateIdx = colIdx
			removeBranchByColIdx(layout, colIdx)
		}
	}
}

func removeBranchByColIdx(layout *wideMatrixLayout, colIdx int) {
	if layout == nil || colIdx < 0 {
		return
	}
	filtered := make([]branchColumnPair, 0, len(layout.branches))
	for _, b := range layout.branches {
		if b.revColIdx == colIdx {
			continue
		}
		filtered = append(filtered, b)
	}
	layout.branches = filtered
}

var arabicMonthNamesByNum = [13]string{
	"", "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
	"يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
}

// splitWideSheetByRowPeriods checks if a wide-matrix worksheet has row-level MONTH / YEAR / DATE columns.
// If present, it partitions the rows chronologically by YYYY-MM into virtual parsedSheetSummary items so
// every single month's records, totals, and MoM/YoY trends are extracted without overwriting each other.
func splitWideSheetByRowPeriods(
	filename string,
	sheetName string,
	sheetState string,
	rows [][]string,
	layout wideMatrixLayout,
) []parsedSheetSummary {
	if len(rows) < 2 || (layout.monthIdx < 0 && layout.yearIdx < 0 && layout.dateIdx < 0) {
		return nil
	}

	defaultYear := inferYearFromText(sheetName, inferYearFromText(filename, 2026))
	monthLastDays := [13]int{0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

	type periodBucket struct {
		ymKey     string
		sheetDate string
		label     string
		rows      [][]string
	}
	bucketMap := make(map[string]*periodBucket)
	var ymOrder []string

	headerRow := rows[0]
	resolvedRowsCount := 0

	for rIdx := 1; rIdx < len(rows); rIdx++ {
		row := rows[rIdx]
		if isRowEmpty(row) {
			continue
		}

		rowDate := ""
		if layout.dateIdx >= 0 {
			rowDate = normalizeDateString(getCell(row, layout.dateIdx), "")
		}
		if rowDate == "" && (layout.monthIdx >= 0 || layout.yearIdx >= 0) {
			rawM := getCell(row, layout.monthIdx)
			rawY := getCell(row, layout.yearIdx)
			yr := inferYearFromText(rawY, defaultYear)
			mo := parseSmartMonthToken(rawM)
			if mo == 0 && rawM != "" {
				// Also check if rawM itself has a full date or year+month
				if d := normalizeDateString(rawM, ""); d != "" {
					rowDate = d
				}
			}
			if rowDate == "" && mo >= 1 && mo <= 12 {
				rowDate = fmt.Sprintf("%04d-%02d-%02d", yr, mo, monthLastDays[mo])
			} else if rowDate == "" && layout.yearIdx >= 0 && yr >= 2020 && yr <= 2035 {
				// Year column only, try sheet name for month or default to Jan
				if d := tryParseArabicSheetMonthDate(sheetName, yr); d != "" {
					rowDate = d
				} else {
					rowDate = fmt.Sprintf("%04d-01-31", yr)
				}
			}
		}

		if rowDate == "" || len(rowDate) < 7 {
			continue
		}
		resolvedRowsCount++
		ymKey := rowDate[:7]
		b, exists := bucketMap[ymKey]
		if !exists {
			var yr, mo int
			_, _ = fmt.Sscanf(ymKey, "%04d-%02d", &yr, &mo)
			label := ymKey
			if mo >= 1 && mo <= 12 && yr >= 2000 {
				label = fmt.Sprintf("%s %02d", arabicMonthNamesByNum[mo], yr%100)
			}
			b = &periodBucket{
				ymKey:     ymKey,
				sheetDate: rowDate,
				label:     label,
				rows:      [][]string{headerRow},
			}
			bucketMap[ymKey] = b
			ymOrder = append(ymOrder, ymKey)
		}
		if rowDate > b.sheetDate {
			b.sheetDate = rowDate
		}
		b.rows = append(b.rows, row)
	}

	if resolvedRowsCount == 0 || len(bucketMap) == 0 {
		return nil
	}

	sort.Strings(ymOrder)
	summaries := make([]parsedSheetSummary, 0, len(ymOrder))
	for _, ymKey := range ymOrder {
		b := bucketMap[ymKey]
		sum := parsedSheetSummary{
			sheetName:  b.label,
			sheetDate:  b.sheetDate,
			state:      sheetState,
			rows:       b.rows,
			layout:     layout,
			isWide:     true,
			storeCount: len(layout.branches),
		}
		computeQuickSheetTotals(&sum)
		summaries = append(summaries, sum)
	}
	return summaries
}

func buildPayloadFromWideMatrix(
	filename string,
	primary parsedSheetSummary,
	activeSheets []parsedSheetSummary,
	allWideSheets []parsedSheetSummary,
	sheetEntries []wbSheetEntry,
) (*domain.NormalizedRetailIngestionPayload, bool) {
	layout := primary.layout
	retailer := "fathalla"
	lowerFile := strings.ToLower(filename)
	switch {
	case strings.Contains(lowerFile, "carrefour") || strings.Contains(filename, "كارفور"):
		retailer = "carrefour"
	case strings.Contains(lowerFile, "gomla") || (strings.Contains(filename, "جملة") && !strings.Contains(filename, "فتح الله")):
		retailer = "gomla"
	case strings.Contains(lowerFile, "spinneys") || strings.Contains(filename, "سبينيس"):
		retailer = "spinneys"
	default:
		for _, br := range layout.branches {
			brLower := strings.ToLower(br.rawBranchName)
			if strings.Contains(brLower, "gomla") || (strings.Contains(br.rawBranchName, "جملة") && !strings.Contains(br.rawBranchName, "فتح الله")) {
				retailer = "gomla"
				break
			}
			if strings.Contains(brLower, "carrefour") || strings.Contains(br.rawBranchName, "كارفور") {
				retailer = "carrefour"
				break
			}
			if strings.Contains(brLower, "spinneys") || strings.Contains(br.rawBranchName, "سبينيس") {
				retailer = "spinneys"
				break
			}
		}
	}

	// 1. Build DiscoveredSheets metadata across all workbook sheets
	detectedSheets := make([]domain.DiscoveredSheetInfo, 0, len(sheetEntries)+len(allWideSheets))
	sheetIdxMap := make(map[string]int)
	for _, entry := range sheetEntries {
		info := domain.DiscoveredSheetInfo{
			Name:  entry.name,
			State: entry.state,
		}
		sheetIdxMap[strings.ToLower(strings.TrimSpace(entry.name))] = len(detectedSheets)
		detectedSheets = append(detectedSheets, info)
	}

	for _, sh := range allWideSheets {
		key := strings.ToLower(strings.TrimSpace(sh.sheetName))
		if idx, ok := sheetIdxMap[key]; ok {
			detectedSheets[idx].RowCount = len(sh.rows) - 1
			detectedSheets[idx].TotalRevenue = math.Round(sh.adcoRev*100) / 100
			detectedSheets[idx].TotalUnits = sh.adcoUnits
			detectedSheets[idx].PeriodDate = sh.sheetDate
		} else {
			info := domain.DiscoveredSheetInfo{
				Name:         sh.sheetName,
				State:        sh.state,
				RowCount:     len(sh.rows) - 1,
				TotalRevenue: math.Round(sh.adcoRev*100) / 100,
				TotalUnits:   sh.adcoUnits,
				PeriodDate:   sh.sheetDate,
			}
			sheetIdxMap[key] = len(detectedSheets)
			detectedSheets = append(detectedSheets, info)
		}
	}

	// 2. Discover branches across ALL sheets
	branchMap := make(map[string]bool)
	discoveredBranches := make([]string, 0, len(layout.branches))
	for _, b := range layout.branches {
		discoveredBranches = append(discoveredBranches, b.displayName)
		branchMap[b.displayName] = true
	}
	for _, sh := range activeSheets {
		for _, b := range sh.layout.branches {
			if !branchMap[b.displayName] {
				discoveredBranches = append(discoveredBranches, b.displayName)
				branchMap[b.displayName] = true
			}
		}
	}

	categorySet := make(map[string]bool)
	categoryMarketTotals := make(map[string]float64)

	type supAgg struct {
		name     string
		rev      float64
		units    int
		skus     map[string]bool
		isTenant bool
	}
	supplierMap := make(map[string]*supAgg)

	var records []domain.NormalizedRecord
	var anomalies []domain.IngestionAnomaly
	var computedPricing []domain.PricingComplianceItem
	var computedOOS []domain.OOSAlert
	reconByMonth := make(map[string]*monthReconAgg)
	sawUnallocated := false

	type adcoSKUZeroBranch struct {
		barcode      string
		skuName      string
		category     string
		totalRev     float64
		activeStores int
		zeroBranches []branchColumnPair
	}
	var oosCandidates []adcoSKUZeroBranch

	totalMarketRev := 0.0

	for rIdx := 1; rIdx < len(primary.rows); rIdx++ {
		row := primary.rows[rIdx]
		if isRowEmpty(row) {
			continue
		}

		sheetCat := domain.NormalizeProductCategory(getCell(row, layout.categoryIdx))
		rawCat := sheetCat
		if rawCat == "" {
			rawCat = BlankWideMatrixCategory
		}
		rawSup := getCell(row, layout.supplierIdx)
		if rawSup == "" {
			rawSup = "ادكو (1)"
		}
		rawBarcode := getCell(row, layout.barcodeIdx)
		cleanedBarcode := normalizeBarcodeValue(rawBarcode)
		if cleanedBarcode == "" {
			cleanedBarcode = strings.TrimSpace(rawBarcode)
		}
		rawSKU := getCell(row, layout.skuIdx)
		if rawSKU == "" {
			rawSKU = cleanedBarcode
		}

		if len(domain.CleanBarcode(cleanedBarcode)) < 6 {
			anomalies = append(anomalies, domain.IngestionAnomaly{
				RowNumber:   rIdx,
				IssueType:   "invalid_barcode",
				Description: fmt.Sprintf("الباركود غير مكتمل (%s) في الصف %d للصنف %s", cleanedBarcode, rIdx, rawSKU),
			})
			continue
		}

		isOwn := isAdcoOrTenantSupplier(rawSup)
		recordCat := wideMatrixRecordCategory(sheetCat, isOwn)
		if isOwn {
			categorySet[rawCat] = true
		}

		activeObs, zeroBranches, recon := collectWideRowBranchObservations(row, layout, retailer, &anomalies, rIdx, rawSKU)
		monthKey := primary.sheetDate
		if len(monthKey) >= 7 {
			monthKey = monthKey[:7]
		}
		accumulateMonthRecon(reconByMonth, monthKey, recon)
		if math.Abs(recon.valueGap) > valueGapEpsilon {
			sawUnallocated = true
		}

		rowTotalRev, rowTotalQty := rowTotalsFromObservations(activeObs)
		if rowTotalRev == 0 && rowTotalQty == 0 {
			continue
		}

		// Infer Standard Product Price (RRP) as the modal price across named branches (skip unallocated).
		priceFreq := make(map[float64]int)
		maxUnitPrice := 0.0
		for _, obs := range activeObs {
			if isUnallocatedBranchName(obs.branch.rawBranchName) || obs.unitPrice <= 0 {
				continue
			}
			roundedHalf := math.Round(obs.unitPrice*2) / 2
			priceFreq[roundedHalf]++
			if obs.unitPrice > maxUnitPrice {
				maxUnitPrice = obs.unitPrice
			}
		}
		inferredRRP := maxUnitPrice
		bestFreq := 0
		for pVal, freq := range priceFreq {
			if freq > bestFreq || (freq == bestFreq && pVal > inferredRRP) {
				bestFreq = freq
				inferredRRP = pVal
			}
		}
		if inferredRRP <= 0 && rowTotalQty > 0 {
			inferredRRP = math.Round((rowTotalRev/float64(rowTotalQty))*100) / 100
		}

		totalMarketRev += rowTotalRev
		categoryMarketTotals[rawCat] += rowTotalRev

		sAgg, exists := supplierMap[rawSup]
		if !exists {
			sAgg = &supAgg{
				name:     rawSup,
				skus:     make(map[string]bool),
				isTenant: isOwn,
			}
			supplierMap[rawSup] = sAgg
		}
		sAgg.rev += rowTotalRev
		sAgg.units += rowTotalQty
		sAgg.skus[cleanedBarcode] = true

		if isOwn {
			namedObsCount := 0
			for _, obs := range activeObs {
				if !isUnallocatedBranchName(obs.branch.rawBranchName) {
					namedObsCount++
				}
			}
			avgBranchUnits := 0.0
			if namedObsCount > 0 {
				avgBranchUnits = float64(recon.branchQtySum) / float64(namedObsCount)
			}

			for _, obs := range activeObs {
				uPrice := obs.unitPrice
				if uPrice <= 0 && obs.qty > 0 {
					uPrice = inferredRRP
				}
				records = append(records, domain.NormalizedRecord{
					RawStoreName:     obs.branch.displayName,
					ResolvedStoreID:  obs.branch.storeID,
					Barcode:          cleanedBarcode,
					SKUName:          rawSKU,
					Category:         recordCat,
					Supplier:         rawSup,
					IsOwnBrand:       true,
					QuantitySold:     obs.qty,
					NetRevenue:       obs.rev,
					UnitPrice:        uPrice,
					RecommendedPrice: inferredRRP,
					TransactionDate:  primary.sheetDate,
					DateFromFile:     primary.sheetDate != "",
				})

				if isUnallocatedBranchName(obs.branch.rawBranchName) {
					continue
				}
				if inferredRRP > 0 && uPrice > 0 {
					deltaPct := domain.CalculatePriceDeltaPct(uPrice, inferredRRP)
					vType := domain.ClassifyPriceViolation(deltaPct)
					if vType != "compliant" || (obs.rev >= 5000 && len(computedPricing) < 120) {
						isPromo := deltaPct <= -5.0 || strings.Contains(rawSKU, "عرض")
						uplift := 0.0
						if isPromo && avgBranchUnits > 0 && float64(obs.qty) > avgBranchUnits {
							uplift = math.Round(((float64(obs.qty)-avgBranchUnits)/avgBranchUnits)*1000) / 10
						} else if isPromo {
							uplift = math.Round(math.Abs(deltaPct)*1.8*10) / 10
						}
						computedPricing = append(computedPricing, domain.PricingComplianceItem{
							TenantID:         "tenant-adeco",
							SKUName:          rawSKU,
							Barcode:          cleanedBarcode,
							Category:         recordCat,
							RetailerChain:    retailer,
							StoreName:        obs.branch.displayName,
							ActualPrice:      uPrice,
							RecommendedPrice: inferredRRP,
							PriceDeltaPct:    deltaPct,
							ViolationType:    vType,
							IsPromoActive:    isPromo,
							PromoUpliftPct:   uplift,
						})
					}
				}
			}

			if len(zeroBranches) > 0 && namedObsCount >= 8 && rowTotalRev >= 15000 {
				oosCandidates = append(oosCandidates, adcoSKUZeroBranch{
					barcode:      cleanedBarcode,
					skuName:      rawSKU,
					category:     recordCat,
					totalRev:     rowTotalRev,
					activeStores: namedObsCount,
					zeroBranches: zeroBranches,
				})
			}
		} else {
			// Competitors: keep one market-intel row for named-branch totals, plus a separate
			// unallocated row when الاجمالى differs (permanent generic rule).
			var namedRev float64
			var namedQty int
			topBranch := layout.branches[0]
			bestBRev := -1.0
			var unallocObs *wideBranchObservation
			for i := range activeObs {
				obs := &activeObs[i]
				if isUnallocatedBranchName(obs.branch.rawBranchName) {
					unallocObs = obs
					continue
				}
				namedRev += obs.rev
				namedQty += obs.qty
				if obs.rev > bestBRev {
					bestBRev = obs.rev
					topBranch = obs.branch
				}
			}
			if namedRev != 0 || namedQty != 0 {
				// Preserve zero / negative aggregated qty on the stored record.
				uPrice := inferredRRP
				if uPrice <= 0 && namedRev != 0 {
					priceQty := namedQty
					if priceQty == 0 && namedRev > 0 {
						priceQty = 1 // unit-price only; not stored
					}
					if priceQty != 0 {
						uPrice = math.Round((namedRev/float64(priceQty))*100) / 100
					}
				}
				records = append(records, domain.NormalizedRecord{
					RawStoreName:     topBranch.displayName,
					ResolvedStoreID:  topBranch.storeID,
					Barcode:          cleanedBarcode,
					SKUName:          rawSKU,
					Category:         recordCat,
					Supplier:         rawSup,
					IsOwnBrand:       false,
					QuantitySold:     namedQty,
					NetRevenue:       math.Round(namedRev*100) / 100,
					UnitPrice:        uPrice,
					RecommendedPrice: uPrice,
					TransactionDate:  primary.sheetDate,
					DateFromFile:     primary.sheetDate != "",
				})
			}
			if unallocObs != nil {
				records = append(records, domain.NormalizedRecord{
					RawStoreName:     unallocObs.branch.displayName,
					ResolvedStoreID:  unallocObs.branch.storeID,
					Barcode:          cleanedBarcode,
					SKUName:          rawSKU,
					Category:         recordCat,
					Supplier:         rawSup,
					IsOwnBrand:       false,
					QuantitySold:     unallocObs.qty,
					NetRevenue:       unallocObs.rev,
					UnitPrice:        0,
					RecommendedPrice: inferredRRP,
					TransactionDate:  primary.sheetDate,
					DateFromFile:     primary.sheetDate != "",
				})
			}
		}
	}

	if len(records) == 0 {
		return nil, false
	}

	primaryKey := strings.ToLower(strings.TrimSpace(primary.sheetName))
	if pIdx, ok := sheetIdxMap[primaryKey]; ok {
		detectedSheets[pIdx].RecordsCount = len(records)
	}

	// Ingest multi-period historical records across all other active wide sheets
	for _, sh := range activeSheets {
		if strings.EqualFold(strings.TrimSpace(sh.sheetName), strings.TrimSpace(primary.sheetName)) {
			continue
		}
		shLayout := sh.layout
		sheetRecCount := 0
		for rIdx := 1; rIdx < len(sh.rows); rIdx++ {
			row := sh.rows[rIdx]
			if isRowEmpty(row) {
				continue
			}
			rawSup := getCell(row, shLayout.supplierIdx)
			if rawSup == "" {
				rawSup = "ادكو (1)"
			}
			cleanedBarcode := normalizeBarcodeValue(getCell(row, shLayout.barcodeIdx))
			if len(domain.CleanBarcode(cleanedBarcode)) < 6 {
				continue
			}
			rawSKU := getCell(row, shLayout.skuIdx)
			if rawSKU == "" {
				rawSKU = cleanedBarcode
			}
			sheetCat := domain.NormalizeProductCategory(getCell(row, shLayout.categoryIdx))
			rawCat := sheetCat
			if rawCat == "" {
				rawCat = BlankWideMatrixCategory
			}
			isOwn := isAdcoOrTenantSupplier(rawSup)
			recordCat := wideMatrixRecordCategory(sheetCat, isOwn)
			if isOwn {
				categorySet[rawCat] = true
			}

			activeObs, _, recon := collectWideRowBranchObservations(row, shLayout, retailer, nil, rIdx, rawSKU)
			monthKey := sh.sheetDate
			if len(monthKey) >= 7 {
				monthKey = monthKey[:7]
			}
			accumulateMonthRecon(reconByMonth, monthKey, recon)
			if math.Abs(recon.valueGap) > valueGapEpsilon {
				sawUnallocated = true
			}
			rowTotalRev, rowTotalQty := rowTotalsFromObservations(activeObs)
			if rowTotalRev == 0 && rowTotalQty == 0 {
				continue
			}

			if isOwn {
				for _, obs := range activeObs {
					uPrice := obs.unitPrice
					if uPrice <= 0 && obs.qty > 0 && obs.rev > 0 {
						uPrice = math.Round((obs.rev/float64(obs.qty))*100) / 100
					}
					records = append(records, domain.NormalizedRecord{
						RawStoreName:     obs.branch.displayName,
						ResolvedStoreID:  obs.branch.storeID,
						Barcode:          cleanedBarcode,
						SKUName:          rawSKU,
						Category:         recordCat,
						Supplier:         rawSup,
						IsOwnBrand:       true,
						QuantitySold:     obs.qty,
						NetRevenue:       obs.rev,
						UnitPrice:        uPrice,
						RecommendedPrice: uPrice,
						TransactionDate:  sh.sheetDate,
						DateFromFile:     sh.sheetDate != "",
					})
					sheetRecCount++
				}
			} else if len(shLayout.branches) > 0 {
				var namedRev float64
				var namedQty int
				topBranch := shLayout.branches[0]
				bestBRev := -1.0
				var unallocObs *wideBranchObservation
				for i := range activeObs {
					obs := &activeObs[i]
					if isUnallocatedBranchName(obs.branch.rawBranchName) {
						unallocObs = obs
						continue
					}
					namedRev += obs.rev
					namedQty += obs.qty
					if obs.rev > bestBRev {
						bestBRev = obs.rev
						topBranch = obs.branch
					}
				}
				if namedRev != 0 || namedQty != 0 {
					uPrice := 0.0
					if namedRev != 0 {
						priceQty := namedQty
						if priceQty == 0 && namedRev > 0 {
							priceQty = 1 // unit-price only; not stored
						}
						if priceQty != 0 {
							uPrice = math.Round((namedRev/float64(priceQty))*100) / 100
						}
					}
					records = append(records, domain.NormalizedRecord{
						RawStoreName:     topBranch.displayName,
						ResolvedStoreID:  topBranch.storeID,
						Barcode:          cleanedBarcode,
						SKUName:          rawSKU,
						Category:         recordCat,
						Supplier:         rawSup,
						IsOwnBrand:       false,
						QuantitySold:     namedQty,
						NetRevenue:       math.Round(namedRev*100) / 100,
						UnitPrice:        uPrice,
						RecommendedPrice: uPrice,
						TransactionDate:  sh.sheetDate,
						DateFromFile:     sh.sheetDate != "",
					})
					sheetRecCount++
				}
				if unallocObs != nil {
					records = append(records, domain.NormalizedRecord{
						RawStoreName:     unallocObs.branch.displayName,
						ResolvedStoreID:  unallocObs.branch.storeID,
						Barcode:          cleanedBarcode,
						SKUName:          rawSKU,
						Category:         recordCat,
						Supplier:         rawSup,
						IsOwnBrand:       false,
						QuantitySold:     unallocObs.qty,
						NetRevenue:       unallocObs.rev,
						UnitPrice:        0,
						RecommendedPrice: 0,
						TransactionDate:  sh.sheetDate,
						DateFromFile:     sh.sheetDate != "",
					})
					sheetRecCount++
				}
			}
		}
		shKey := strings.ToLower(strings.TrimSpace(sh.sheetName))
		if shIdx, ok := sheetIdxMap[shKey]; ok {
			detectedSheets[shIdx].RecordsCount = sheetRecCount
		}
	}

	// Build OOS alerts from top Adco SKUs missing in specific Fathalla branches
	sort.Slice(oosCandidates, func(i, j int) bool {
		return oosCandidates[i].totalRev > oosCandidates[j].totalRev
	})
	now := time.Now()
	alertSeq := 1
	for _, cand := range oosCandidates {
		if len(computedOOS) >= 25 {
			break
		}
		avgBranchMonthlyRev := cand.totalRev / float64(cand.activeStores)
		dailyLost := math.Round((avgBranchMonthlyRev/30.0)*10) / 10
		if dailyLost < 50 {
			dailyLost = 120.0
		}
		maxZeroPerSKU := 2
		for zIdx, zb := range cand.zeroBranches {
			if zIdx >= maxZeroPerSKU || len(computedOOS) >= 25 {
				break
			}
			severity := "medium"
			daysOOS := 3
			if dailyLost >= 500 {
				severity = "critical"
				daysOOS = 5
			} else if dailyLost >= 200 {
				severity = "high"
				daysOOS = 4
			}
			computedOOS = append(computedOOS, domain.OOSAlert{
				AlertID:                fmt.Sprintf("oos_excel_%03d", alertSeq),
				TenantID:               "tenant-adeco",
				RetailerChain:          retailer,
				StoreID:                zb.storeID,
				StoreName:              zb.displayName,
				Barcode:                cand.barcode,
				SKUName:                cand.skuName,
				Category:               cand.category,
				EstimatedLostDailyCost: dailyLost,
				ConsecutiveDaysOOS:     daysOOS,
				Severity:               severity,
				DetectedAt:             now,
			})
			alertSeq++
		}
	}

	// Sort and compute SupplierShares
	// Note: If the workbook was a single physical sheet split into multiple virtual monthly sheets (e.g., "2025 out.xlsx" with jan, feb, mar, apr),
	// accumulate supplier totals across all virtual monthly sheets so the upload summary matches the full file total!
	isSingleSheetSplit := len(activeSheets) > 1 && len(activeSheets) == len(sheetEntries)
	if isSingleSheetSplit {
		allSameUnderlying := true
		for _, sh := range activeSheets {
			if len(sh.rows) == 0 || len(primary.rows) == 0 || len(sh.rows[0]) != len(primary.rows[0]) {
				allSameUnderlying = false
				break
			}
		}
		if allSameUnderlying && (layout.monthIdx >= 0 || layout.yearIdx >= 0 || layout.dateIdx >= 0) {
			for _, sh := range activeSheets {
				if strings.EqualFold(strings.TrimSpace(sh.sheetName), strings.TrimSpace(primary.sheetName)) {
					continue
				}
				shLayout := sh.layout
				for rIdx := 1; rIdx < len(sh.rows); rIdx++ {
					row := sh.rows[rIdx]
					if isRowEmpty(row) {
						continue
					}
					rawSup := getCell(row, shLayout.supplierIdx)
					if rawSup == "" {
						rawSup = "ادكو (1)"
					}
					cleanedBarcode := normalizeBarcodeValue(getCell(row, shLayout.barcodeIdx))
					if len(domain.CleanBarcode(cleanedBarcode)) < 6 {
						continue
					}
					rawCat := domain.NormalizeProductCategory(getCell(row, shLayout.categoryIdx))
					if rawCat == "" {
						rawCat = BlankWideMatrixCategory
					}
					isOwn := isAdcoOrTenantSupplier(rawSup)
					// Market-share only (records already emitted above); do not re-accumulate recon warnings.
					activeObs, _, _ := collectWideRowBranchObservations(row, shLayout, retailer, nil, rIdx, cleanedBarcode)
					rowTotalRev, rowTotalQty := rowTotalsFromObservations(activeObs)
					if rowTotalRev == 0 && rowTotalQty == 0 {
						continue
					}
					totalMarketRev += rowTotalRev
					categoryMarketTotals[rawCat] += rowTotalRev
					sAgg, exists := supplierMap[rawSup]
					if !exists {
						sAgg = &supAgg{
							name:     rawSup,
							skus:     make(map[string]bool),
							isTenant: isOwn,
						}
						supplierMap[rawSup] = sAgg
					}
					sAgg.rev += rowTotalRev
					sAgg.units += rowTotalQty
					sAgg.skus[cleanedBarcode] = true
				}
			}
		}
	}

	supplierShares := make([]domain.SupplierShareSummary, 0, len(supplierMap))
	for _, s := range supplierMap {
		share := 0.0
		if totalMarketRev > 0 {
			share = math.Round((s.rev/totalMarketRev)*10000) / 100
		}
		supplierShares = append(supplierShares, domain.SupplierShareSummary{
			SupplierName: s.name,
			TotalRevenue: math.Round(s.rev*100) / 100,
			TotalUnits:   s.units,
			MarketShare:  share,
			SKUCount:     len(s.skus),
			IsTenant:     s.isTenant,
		})
	}
	sort.Slice(supplierShares, func(i, j int) bool {
		return supplierShares[i].TotalRevenue > supplierShares[j].TotalRevenue
	})

	// Build discovered categories list
	discoveredCategories := make([]string, 0, len(categorySet))
	for c := range categorySet {
		discoveredCategories = append(discoveredCategories, c)
	}
	sort.Strings(discoveredCategories)

	// Build multi-sheet monthly trends and compute real MoM% and YoY%
	var monthlyTrends []domain.DailyTrendPoint
	var sheetsProcessed []string
	for _, sh := range allWideSheets {
		sheetsProcessed = append(sheetsProcessed, sh.sheetName)
		if sh.adcoRev > 0 {
			monthlyTrends = append(monthlyTrends, domain.DailyTrendPoint{
				Date:       sh.sheetDate,
				Revenue:    math.Round(sh.adcoRev*100) / 100,
				Units:      sh.adcoUnits,
				StoreCount: sh.storeCount,
			})
		}
	}

	revMoM := 0.0
	unitsMoM := 0.0
	revYoY := 0.0
	unitsYoY := 0.0

	if len(allWideSheets) >= 2 {
		prev := allWideSheets[len(allWideSheets)-2]
		if prev.adcoRev > 0 {
			revMoM = math.Round(((primary.adcoRev-prev.adcoRev)/prev.adcoRev)*1000) / 10
		}
		if prev.adcoUnits > 0 {
			unitsMoM = math.Round(((float64(primary.adcoUnits)-float64(prev.adcoUnits))/float64(prev.adcoUnits))*1000) / 10
		}
	}
	if len(allWideSheets) >= 12 {
		yoySheet := allWideSheets[0]
		// Prefer matching same month from prior year (e.g., index len-13)
		if len(allWideSheets) >= 13 {
			yoySheet = allWideSheets[len(allWideSheets)-13]
		}
		if yoySheet.adcoRev > 0 {
			revYoY = math.Round(((primary.adcoRev-yoySheet.adcoRev)/yoySheet.adcoRev)*1000) / 10
		}
		if yoySheet.adcoUnits > 0 {
			unitsYoY = math.Round(((float64(primary.adcoUnits)-float64(yoySheet.adcoUnits))/float64(yoySheet.adcoUnits))*1000) / 10
		}
	}

	minDate := primary.sheetDate
	maxDate := primary.sheetDate
	if len(activeSheets) > 0 {
		minDate = activeSheets[0].sheetDate
		maxDate = activeSheets[len(activeSheets)-1].sheetDate
	}

	if sawUnallocated && !branchMap[UnallocatedBranchName] {
		discoveredBranches = append(discoveredBranches, UnallocatedBranchName)
		branchMap[UnallocatedBranchName] = true
	}
	anomalies = append(anomalies, buildWideMatrixReconAnomalies(reconByMonth)...)

	payload := &domain.NormalizedRetailIngestionPayload{
		RetailerDetected:     retailer,
		ReportingPeriodStart: minDate,
		ReportingPeriodEnd:   maxDate,
		ConfidenceScore:      0.996,
		ColumnMapping: domain.ColumnMapping{
			BarcodeColumn:      "الباركود (Col C)",
			SKUNameColumn:      "الصنف (Col D)",
			StoreNameColumn:    fmt.Sprintf("مصفوفة فروع فتح الله (%d فرع تلقائي)", len(layout.branches)),
			QuantitySoldColumn: fmt.Sprintf("أعمدة كميات الفروع (%d عمود كمية)", len(layout.branches)),
			NetRevenueColumn:   fmt.Sprintf("أعمدة مبيعات الفروع + الإجمالي (%d عمود قيمة)", len(layout.branches)),
			CategoryColumn:     "المجموعة الرئيسية (Col A)",
			SupplierColumn:     "المورد والشركات المنافسة (Col B)",
		},
		AnomaliesDetected:    anomalies,
		NormalizedRecords:    records,
		DiscoveredBranches:   discoveredBranches,
		DiscoveredCategories: discoveredCategories,
		SheetsProcessed:      sheetsProcessed,
		DetectedSheets:       detectedSheets,
		SheetsDetectedCount:  len(sheetEntries),
		SupplierShares:       supplierShares,
		CategoryMarketTotals: categoryMarketTotals,
		MonthlyTrends:        monthlyTrends,
		ComputedOOSAlerts:    computedOOS,
		ComputedPricingItems: computedPricing,
		RevenueMoMPct:        revMoM,
		RevenueYoYPct:        revYoY,
		UnitsMoMPct:          unitsMoM,
		UnitsYoYPct:          unitsYoY,
		IsWideMatrixWorkbook: true,
	}
	attachBranchNormSummary(payload)
	return payload, true
}

// frozenStoreIDPrefixes pins the historical chain[:3] prefix of every chain that already exists
// (Firestore tenant_retail_chains + retail_chains + SELLIN_CUSTOMER_CHAIN_MAP, read 3 Nov 2026) and
// reaches the default case of BuildBranchStoreMetadata. carrefour/gomla/beet-elgomla/spinneys/metro/
// seoudi/kazyon/fathalla have explicit cases above. Only chains created later use the new rule.
var frozenStoreIDPrefixes = map[string]string{
	"qa_test":       "qa_",
	"chain-1080314": "cha",
	"zahran":        "zah",
}

// storeIDPrefixForChain keeps the historical chain[:3] prefix when it is plain alphanumeric, and
// otherwise uses the first three alphanumerics (frozen codes above win, e.g. qa_test -> qa_). Returns "" when the
// chain has fewer than three alphanumerics (caller keeps its default).
func storeIDPrefixForChain(chain string) string {
	if p, ok := frozenStoreIDPrefixes[chain]; ok {
		return p
	}
	isAlnum := func(b byte) bool { return b >= 'a' && b <= 'z' || b >= '0' && b <= '9' }
	if len(chain) >= 3 && isAlnum(chain[0]) && isAlnum(chain[1]) && isAlnum(chain[2]) {
		return chain[:3]
	}
	out := make([]byte, 0, 3)
	for i := 0; i < len(chain) && len(out) < 3; i++ {
		if isAlnum(chain[i]) {
			out = append(out, chain[i])
		}
	}
	if len(out) < 3 {
		return ""
	}
	return string(out)
}
