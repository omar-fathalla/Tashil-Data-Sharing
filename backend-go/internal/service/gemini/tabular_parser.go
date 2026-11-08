package gemini

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/gemini/guardrails"
)

type xlsxSST struct {
	SI []xlsxSI `xml:"si"`
}

type xlsxSI struct {
	T string  `xml:"t"`
	R []xlsxR `xml:"r"`
}

type xlsxR struct {
	T string `xml:"t"`
}

type xlsxWorksheet struct {
	SheetData xlsxSheetData `xml:"sheetData"`
}

type xlsxSheetData struct {
	Rows []xlsxRow `xml:"row"`
}

type xlsxRow struct {
	R     int        `xml:"r,attr"`
	Cells []xlsxCell `xml:"c"`
}

type xlsxCell struct {
	R  string `xml:"r,attr"`
	T  string `xml:"t,attr"`
	V  string `xml:"v"`
	IS struct {
		T string  `xml:"t"`
		R []xlsxR `xml:"r"`
	} `xml:"is"`
}

// isZipArchive checks if raw bytes begin with the PK\x03\x04 ZIP signature used by .xlsx files.
func isZipArchive(data []byte) bool {
	return len(data) >= 4 && data[0] == 'P' && data[1] == 'K' && data[2] == 0x03 && data[3] == 0x04
}

// readSharedStringsFast extracts sharedStrings from xl/sharedStrings.xml using a zero-DOM byte scanner.
func readSharedStringsFast(data []byte) []string {
	if len(data) == 0 {
		return nil
	}
	var sharedStrings []string
	pos := 0
	siOpen := []byte("<si")
	siClose := []byte("</si>")
	tOpen := []byte("<t")
	tClose := []byte("</t>")

	for pos < len(data) {
		idx := bytes.Index(data[pos:], siOpen)
		if idx < 0 {
			break
		}
		startSI := pos + idx
		// Ensure it's <si> or <si ...>
		afterSI := startSI + 3
		if afterSI < len(data) && data[afterSI] != '>' && data[afterSI] != ' ' && data[afterSI] != '/' && data[afterSI] != '\t' && data[afterSI] != '\r' && data[afterSI] != '\n' {
			pos = afterSI
			continue
		}
		endIdx := bytes.Index(data[afterSI:], siClose)
		if endIdx < 0 {
			break
		}
		siBody := data[afterSI : afterSI+endIdx]
		pos = afterSI + endIdx + len(siClose)

		var sb strings.Builder
		tPos := 0
		for tPos < len(siBody) {
			tIdx := bytes.Index(siBody[tPos:], tOpen)
			if tIdx < 0 {
				break
			}
			tStart := tPos + tIdx + 2
			if tStart < len(siBody) && siBody[tStart] != '>' && siBody[tStart] != ' ' && siBody[tStart] != '/' {
				tPos = tStart
				continue
			}
			gtIdx := bytes.IndexByte(siBody[tStart:], '>')
			if gtIdx < 0 {
				break
			}
			if gtIdx > 0 && siBody[tStart+gtIdx-1] == '/' {
				// self-closing <t/>
				tPos = tStart + gtIdx + 1
				continue
			}
			valStart := tStart + gtIdx + 1
			tEnd := bytes.Index(siBody[valStart:], tClose)
			if tEnd < 0 {
				break
			}
			rawVal := string(siBody[valStart : valStart+tEnd])
			if strings.IndexByte(rawVal, '&') >= 0 {
				rawVal = html.UnescapeString(rawVal)
			}
			sb.WriteString(rawVal)
			tPos = valStart + tEnd + len(tClose)
		}
		sharedStrings = append(sharedStrings, sb.String())
	}
	return sharedStrings
}

// parseXLSXRows extracts all rows from the best matching worksheet of an .xlsx archive using high-speed streaming.
func parseXLSXRows(rawContent []byte) ([][]string, error) {
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil, fmt.Errorf("failed to open xlsx zip reader: %w", err)
	}

	var sharedStrings []string
	var sheetFiles []*zip.File

	for _, f := range zr.File {
		nameLower := strings.ToLower(f.Name)
		if nameLower == "xl/sharedstrings.xml" {
			rc, err := f.Open()
			if err == nil {
				data, readErr := io.ReadAll(rc)
				_ = rc.Close()
				if readErr == nil {
					sharedStrings = readSharedStringsFast(data)
				}
			}
		} else if strings.HasPrefix(nameLower, "xl/worksheets/sheet") && strings.HasSuffix(nameLower, ".xml") {
			sheetFiles = append(sheetFiles, f)
		}
	}

	if len(sheetFiles) == 0 {
		return nil, fmt.Errorf("no worksheet xml found in xlsx archive")
	}

	var fallbackSheet *zip.File
	for _, sf := range sheetFiles {
		// Stream only the first 16 rows to check if this worksheet has a valid retail header!
		sampleRows, err := readWorksheetSampleRows(sf, sharedStrings, 16)
		if err != nil || len(sampleRows) == 0 {
			continue
		}
		if fallbackSheet == nil {
			fallbackSheet = sf
		}
		if _, headerIdx, ok := findHeaderRow(sampleRows); ok && headerIdx < len(sampleRows)-1 {
			return readWorksheetXML(sf, sharedStrings)
		}
	}

	if fallbackSheet != nil {
		return readWorksheetXML(fallbackSheet, sharedStrings)
	}
	return nil, fmt.Errorf("no readable worksheet found in xlsx archive")
}

// parseXLSXMultiSheetRows reads all valid tabular worksheets from an .xlsx archive, combining their data rows
// under the primary header row and recording each row's inferred worksheet month date (e.g. "لشركة شهر 7" -> "2026-07-31").
func parseXLSXMultiSheetRows(filename string, rawContent []byte) ([][]string, map[int]string, error) {
	zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to open xlsx zip reader: %w", err)
	}

	var sharedStrings []string
	fileByName := make(map[string]*zip.File)
	for _, f := range zr.File {
		nameLower := strings.ToLower(f.Name)
		fileByName[nameLower] = f
		if nameLower == "xl/sharedstrings.xml" {
			rc, err := f.Open()
			if err == nil {
				data, readErr := io.ReadAll(rc)
				_ = rc.Close()
				if readErr == nil {
					sharedStrings = readSharedStringsFast(data)
				}
			}
		}
	}

	fileYear := 2026
	switch {
	case strings.Contains(filename, "2024"):
		fileYear = 2024
	case strings.Contains(filename, "2025"):
		fileYear = 2025
	case strings.Contains(filename, "2026"):
		fileYear = 2026
	}

	sheetEntries := listOrderedWorkbookSheets(zr, fileByName)
	if len(sheetEntries) == 0 {
		rows, err := parseXLSXRows(rawContent)
		return rows, nil, err
	}

	var combinedRows [][]string
	rowSheetDates := make(map[int]string)
	primaryHeaderFetched := false
	dataRowOffset := 0

	for _, entry := range sheetEntries {
		sampleRows, err := readWorksheetSampleRows(entry.file, sharedStrings, 16)
		if err != nil || len(sampleRows) == 0 {
			continue
		}
		_, headerIdx, ok := findHeaderRow(sampleRows)
		if !ok || headerIdx >= len(sampleRows)-1 {
			continue
		}
		sheetRows, err := readWorksheetXML(entry.file, sharedStrings)
		if err != nil || len(sheetRows) <= headerIdx+1 {
			continue
		}
		sheetDate := tryParseArabicSheetMonthDate(entry.name, fileYear)
		if sheetDate == "" && len(sheetEntries) == 1 {
			sheetDate = tryParseArabicSheetMonthDate(filename, fileYear)
		}

		if !primaryHeaderFetched {
			combinedRows = append(combinedRows, sheetRows[:headerIdx+1]...)
			primaryHeaderFetched = true
		}

		sheetDataRows := sheetRows[headerIdx+1:]
		for _, dr := range sheetDataRows {
			combinedRows = append(combinedRows, dr)
			if sheetDate != "" {
				rowSheetDates[dataRowOffset] = sheetDate
			}
			dataRowOffset++
		}
	}

	if len(combinedRows) > 0 {
		return combinedRows, rowSheetDates, nil
	}

	rows, err := parseXLSXRows(rawContent)
	return rows, nil, err
}

// readWorksheetSampleRows streams only up to maxRows from an .xlsx worksheet without reading or unmarshaling the entire file.
func readWorksheetSampleRows(sheetFile *zip.File, sharedStrings []string, maxRows int) ([][]string, error) {
	if maxRows <= 0 {
		maxRows = 15
	}
	return readWorksheetXMLStreaming(sheetFile, sharedStrings, maxRows)
}

func readWorksheetXML(sheetFile *zip.File, sharedStrings []string) ([][]string, error) {
	return readWorksheetXMLStreaming(sheetFile, sharedStrings, 0)
}

// readWorksheetXMLStreaming streams `<row>...</row>` blocks from the compressed worksheet XML in 256 KB chunks.
// If maxRows > 0, it stops and closes the stream immediately once maxRows rows are extracted.
func readWorksheetXMLStreaming(sheetFile *zip.File, sharedStrings []string, maxRows int) ([][]string, error) {
	rc, err := sheetFile.Open()
	if err != nil {
		return nil, fmt.Errorf("failed to open worksheet xml: %w", err)
	}
	defer rc.Close()

	var rows [][]string
	if maxRows > 0 {
		rows = make([][]string, 0, maxRows)
	} else {
		rows = make([][]string, 0, 1024)
	}

	chunk := make([]byte, 256*1024)
	var buf []byte
	rowOpenTag := []byte("<row")
	rowCloseTag := []byte("</row>")

	for {
		n, readErr := rc.Read(chunk)
		if n > 0 {
			buf = append(buf, chunk[:n]...)
			offset := 0
			for {
				rIdx := bytes.Index(buf[offset:], rowOpenTag)
				if rIdx < 0 {
					// Keep trailing 8 bytes in case "<row" straddles chunk boundary
					if len(buf)-offset > 8 {
						offset = len(buf) - 8
					}
					break
				}
				rowStart := offset + rIdx
				afterRowTag := rowStart + 4
				if afterRowTag < len(buf) {
					ch := buf[afterRowTag]
					if ch != '>' && ch != ' ' && ch != '/' && ch != '\t' && ch != '\r' && ch != '\n' {
						offset = afterRowTag
						continue
					}
				} else if readErr == nil {
					break
				}

				endIdx := bytes.Index(buf[afterRowTag:], rowCloseTag)
				if endIdx < 0 {
					// Wait for more bytes unless it's a self-closing <row .../>
					gtIdx := bytes.IndexByte(buf[afterRowTag:], '>')
					if gtIdx >= 0 && buf[afterRowTag+gtIdx-1] == '/' {
						offset = afterRowTag + gtIdx + 1
						continue
					}
					offset = rowStart
					break
				}

				rowEnd := afterRowTag + endIdx
				rowCells := parseStreamingRowCells(buf[afterRowTag:rowEnd], sharedStrings)
				if len(rowCells) > 0 {
					rows = append(rows, rowCells)
					if maxRows > 0 && len(rows) >= maxRows {
						return rows, nil
					}
				}
				offset = rowEnd + len(rowCloseTag)
			}

			if offset > 0 {
				remaining := len(buf) - offset
				if remaining > 0 {
					copy(buf[:remaining], buf[offset:])
					buf = buf[:remaining]
				} else {
					buf = buf[:0]
				}
			}
		}
		if readErr != nil {
			if readErr == io.EOF {
				break
			}
			return nil, fmt.Errorf("failed to stream worksheet xml: %w", readErr)
		}
	}

	return rows, nil
}

func parseStreamingRowCells(rowBody []byte, sharedStrings []string) []string {
	// Skip leading attributes of <row ...> up to '>'
	gt := bytes.IndexByte(rowBody, '>')
	if gt < 0 || (gt > 0 && rowBody[gt-1] == '/') {
		return nil
	}
	cellsData := rowBody[gt+1:]

	var rowCells []string
	nextCol := 0
	pos := 0
	cOpen := []byte("<c")
	cClose := []byte("</c>")
	vOpen := []byte("<v>")
	vOpenAttr := []byte("<v ")
	vClose := []byte("</v>")
	tOpen := []byte("<t")
	tClose := []byte("</t>")

	for pos < len(cellsData) {
		cIdx := bytes.Index(cellsData[pos:], cOpen)
		if cIdx < 0 {
			break
		}
		cStart := pos + cIdx
		afterC := cStart + 2
		if afterC >= len(cellsData) {
			break
		}
		if cellsData[afterC] != '>' && cellsData[afterC] != ' ' && cellsData[afterC] != '/' && cellsData[afterC] != '\t' {
			pos = afterC
			continue
		}

		tagEnd := bytes.IndexByte(cellsData[afterC:], '>')
		if tagEnd < 0 {
			break
		}
		attrSlice := cellsData[afterC : afterC+tagEnd]
		isSelfClosing := tagEnd > 0 && cellsData[afterC+tagEnd-1] == '/'

		cellRef := extractXMLAttr(attrSlice, "r")
		cellType := extractXMLAttr(attrSlice, "t")
		colIdx := parseXLSXColIndex(cellRef, nextCol)

		if isSelfClosing {
			nextCol = colIdx + 1
			pos = afterC + tagEnd + 1
			continue
		}

		bodyStart := afterC + tagEnd + 1
		cEndIdx := bytes.Index(cellsData[bodyStart:], cClose)
		if cEndIdx < 0 {
			break
		}
		cBody := cellsData[bodyStart : bodyStart+cEndIdx]
		pos = bodyStart + cEndIdx + len(cClose)

		var val string
		if cellType == "inlineStr" {
			var sb strings.Builder
			tPos := 0
			for tPos < len(cBody) {
				ti := bytes.Index(cBody[tPos:], tOpen)
				if ti < 0 {
					break
				}
				ts := tPos + ti + 2
				tg := bytes.IndexByte(cBody[ts:], '>')
				if tg < 0 {
					break
				}
				if tg > 0 && cBody[ts+tg-1] == '/' {
					tPos = ts + tg + 1
					continue
				}
				vs := ts + tg + 1
				te := bytes.Index(cBody[vs:], tClose)
				if te < 0 {
					break
				}
				part := string(cBody[vs : vs+te])
				if strings.IndexByte(part, '&') >= 0 {
					part = html.UnescapeString(part)
				}
				sb.WriteString(part)
				tPos = vs + te + len(tClose)
			}
			val = sb.String()
		} else {
			vIdx := bytes.Index(cBody, vOpen)
			vValStart := -1
			if vIdx >= 0 {
				vValStart = vIdx + 3
			} else if vaIdx := bytes.Index(cBody, vOpenAttr); vaIdx >= 0 {
				if vg := bytes.IndexByte(cBody[vaIdx:], '>'); vg >= 0 {
					vValStart = vaIdx + vg + 1
				}
			}
			if vValStart >= 0 && vValStart <= len(cBody) {
				vEnd := bytes.Index(cBody[vValStart:], vClose)
				if vEnd >= 0 {
					val = strings.TrimSpace(string(cBody[vValStart : vValStart+vEnd]))
					if cellType == "s" {
						if sIdx, err := strconv.Atoi(val); err == nil && sIdx >= 0 && sIdx < len(sharedStrings) {
							val = sharedStrings[sIdx]
						}
					} else if strings.IndexByte(val, '&') >= 0 {
						val = html.UnescapeString(val)
					}
				}
			}
		}

		for len(rowCells) <= colIdx {
			rowCells = append(rowCells, "")
		}
		rowCells[colIdx] = strings.TrimSpace(val)
		nextCol = colIdx + 1
	}

	return rowCells
}

func extractXMLAttr(attrBytes []byte, attrName string) string {
	n := len(attrBytes)
	nameLen := len(attrName)
	for i := 0; i+nameLen+2 < n; i++ {
		if (i == 0 || attrBytes[i-1] == ' ' || attrBytes[i-1] == '\t' || attrBytes[i-1] == '\n' || attrBytes[i-1] == '\r') &&
			string(attrBytes[i:i+nameLen]) == attrName && attrBytes[i+nameLen] == '=' {
			qPos := i + nameLen + 1
			quote := attrBytes[qPos]
			if quote == '"' || quote == '\'' {
				valStart := qPos + 1
				endQ := bytes.IndexByte(attrBytes[valStart:], quote)
				if endQ >= 0 {
					return string(attrBytes[valStart : valStart+endQ])
				}
			}
		}
	}
	return ""
}

// ConvertXLSXToCSVBytes converts an .xlsx archive in memory into UTF-8 CSV bytes using the streaming reader.
func ConvertXLSXToCSVBytes(rawContent []byte) ([]byte, error) {
	rows, err := parseXLSXRows(rawContent)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	cw := csv.NewWriter(&buf)
	for _, r := range rows {
		if err := cw.Write(r); err != nil {
			return nil, err
		}
	}
	cw.Flush()
	if err := cw.Error(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// extractSmartCSVSample extracts up to maxRows (including headers) as clean CSV text from either .xlsx or .csv bytes
// so Gemini receives human-readable UTF-8 tabular sample rows instead of raw binary ZIP bytes.
// Cells are PII-minimized (truncated + redacted) before leaving this function.
func extractSmartCSVSample(filename string, rawContent []byte, maxRows int) string {
	if maxRows <= 0 {
		maxRows = 25
	}
	encode := func(rows [][]string) string {
		safe := guardrails.SanitizeSampleRowsLimit(rows, maxRows)
		var buf bytes.Buffer
		cw := csv.NewWriter(&buf)
		_ = cw.WriteAll(safe)
		cw.Flush()
		return buf.String()
	}
	if isZipArchive(rawContent) {
		zr, err := zip.NewReader(bytes.NewReader(rawContent), int64(len(rawContent)))
		if err == nil {
			var sharedStrings []string
			var sheetFiles []*zip.File
			for _, f := range zr.File {
				nl := strings.ToLower(f.Name)
				if nl == "xl/sharedstrings.xml" {
					if rc, oErr := f.Open(); oErr == nil {
						data, _ := io.ReadAll(rc)
						_ = rc.Close()
						sharedStrings = readSharedStringsFast(data)
					}
				} else if strings.HasPrefix(nl, "xl/worksheets/sheet") && strings.HasSuffix(nl, ".xml") {
					sheetFiles = append(sheetFiles, f)
				}
			}
			for _, sf := range sheetFiles {
				sampleRows, sErr := readWorksheetSampleRows(sf, sharedStrings, maxRows)
				if sErr == nil && len(sampleRows) > 0 {
					return encode(sampleRows)
				}
			}
		}
	}
	if rows, err := parseCSVRows(rawContent); err == nil && len(rows) > 0 {
		return encode(rows)
	}
	// Opaque bytes: still redact/truncate before sending toward the model prompt.
	return guardrails.RedactString(string(takeSample(rawContent, 32000)))
}

func parseXLSXColIndex(cellRef string, fallback int) int {
	if cellRef == "" {
		return fallback
	}
	col := 0
	foundLetter := false
	for i := 0; i < len(cellRef); i++ {
		ch := cellRef[i]
		if ch >= 'A' && ch <= 'Z' {
			col = col*26 + int(ch-'A'+1)
			foundLetter = true
		} else if ch >= 'a' && ch <= 'z' {
			col = col*26 + int(ch-'a'+1)
			foundLetter = true
		} else {
			break
		}
	}
	if !foundLetter || col <= 0 {
		return fallback
	}
	return col - 1
}

// BuildSampleXLSX constructs a valid .xlsx ZIP archive in memory from tabular rows using Go's standard library.
func BuildSampleXLSX(rows [][]string) ([]byte, error) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	sharedStrings := make([]string, 0)
	sharedIndex := make(map[string]int)

	addSharedString := func(s string) int {
		if idx, ok := sharedIndex[s]; ok {
			return idx
		}
		idx := len(sharedStrings)
		sharedStrings = append(sharedStrings, s)
		sharedIndex[s] = idx
		return idx
	}

	var sheetBuf bytes.Buffer
	sheetBuf.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	sheetBuf.WriteString(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)

	for rIdx, row := range rows {
		sheetBuf.WriteString(fmt.Sprintf(`<row r="%d">`, rIdx+1))
		for cIdx, cell := range row {
			colRef := xlsxColLetters(cIdx) + strconv.Itoa(rIdx+1)
			// Check if strictly numeric (and not a long barcode starting with 0 or >= 8 digits)
			trimmed := strings.TrimSpace(cell)
			if rIdx > 0 && len(trimmed) > 0 && len(trimmed) < 8 {
				if _, err := strconv.ParseFloat(trimmed, 64); err == nil {
					sheetBuf.WriteString(fmt.Sprintf(`<c r="%s"><v>%s</v></c>`, colRef, xmlEscape(trimmed)))
					continue
				}
			}
			sIdx := addSharedString(cell)
			sheetBuf.WriteString(fmt.Sprintf(`<c r="%s" t="s"><v>%d</v></c>`, colRef, sIdx))
		}
		sheetBuf.WriteString(`</row>`)
	}
	sheetBuf.WriteString(`</sheetData></worksheet>`)

	var sstBuf bytes.Buffer
	sstBuf.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	sstBuf.WriteString(fmt.Sprintf(`<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="%d" uniqueCount="%d">`, len(sharedStrings), len(sharedStrings)))
	for _, s := range sharedStrings {
		sstBuf.WriteString(fmt.Sprintf(`<si><t>%s</t></si>`, xmlEscape(s)))
	}
	sstBuf.WriteString(`</sst>`)

	files := map[string][]byte{
		"[Content_Types].xml": []byte(`<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
</Types>`),
		"xl/sharedStrings.xml":      sstBuf.Bytes(),
		"xl/worksheets/sheet1.xml": sheetBuf.Bytes(),
	}

	for name, content := range files {
		w, err := zw.Create(name)
		if err != nil {
			return nil, err
		}
		if _, err := w.Write(content); err != nil {
			return nil, err
		}
	}

	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func xlsxColLetters(colIdx int) string {
	var res []byte
	n := colIdx + 1
	for n > 0 {
		rem := (n - 1) % 26
		res = append([]byte{byte('A' + rem)}, res...)
		n = (n - 1) / 26
	}
	return string(res)
}

func xmlEscape(s string) string {
	var buf bytes.Buffer
	_ = xml.EscapeText(&buf, []byte(s))
	return buf.String()
}

// parseCSVRows parses all rows from a UTF-8 CSV byte slice without any size truncation.
func parseCSVRows(rawContent []byte) ([][]string, error) {
	cleaned := bytes.TrimPrefix(rawContent, []byte("\xEF\xBB\xBF"))
	text := strings.TrimSpace(string(cleaned))
	if text == "" {
		return nil, fmt.Errorf("empty csv content")
	}

	// Auto-detect delimiter from header line
	firstLine := text
	if nl := strings.IndexByte(text, '\n'); nl >= 0 {
		firstLine = text[:nl]
	}
	commaCount := strings.Count(firstLine, ",")
	semiCount := strings.Count(firstLine, ";")
	tabCount := strings.Count(firstLine, "\t")

	delimiter := ','
	if semiCount > commaCount && semiCount >= tabCount {
		delimiter = ';'
	} else if tabCount > commaCount && tabCount > semiCount {
		delimiter = '\t'
	}

	reader := csv.NewReader(strings.NewReader(text))
	reader.Comma = delimiter
	reader.FieldsPerRecord = -1
	reader.LazyQuotes = true
	reader.TrimLeadingSpace = true

	return reader.ReadAll()
}

type discoveredColumns struct {
	barcodeIdx   int
	skuNameIdx   int
	storeNameIdx int
	qtyIdx       int
	revIdx       int
	categoryIdx  int
	dateIdx      int
	yearIdx      int
	monthIdx     int
	supplierIdx  int
	mapping      domain.ColumnMapping
}

// findHeaderRow scans up to the first 15 non-empty rows to locate the retail header row.
func findHeaderRow(rows [][]string) (discoveredColumns, int, bool) {
	checked := 0
	for idx, r := range rows {
		if isRowEmpty(r) {
			continue
		}
		if cols, ok := discoverColumnIndices(r); ok {
			return cols, idx, true
		}
		checked++
		if checked >= 15 {
			break
		}
	}
	return discoveredColumns{}, -1, false
}

func discoverColumnIndices(headers []string) (discoveredColumns, bool) {
	cols := discoveredColumns{
		barcodeIdx:   -1,
		skuNameIdx:   -1,
		storeNameIdx: -1,
		qtyIdx:       -1,
		revIdx:       -1,
		categoryIdx:  -1,
		dateIdx:      -1,
		yearIdx:      -1,
		monthIdx:     -1,
		supplierIdx:  -1,
		mapping: domain.ColumnMapping{
			BarcodeColumn:      "Barcode",
			SKUNameColumn:      "Item_Description",
			StoreNameColumn:    "Store_Name",
			QuantitySoldColumn: "Qty_Sold",
			NetRevenueColumn:   "Net_Amount",
		},
	}

	barcodeCands := []string{
		"barcode", "gtin", "ean", "item code", "itemcode", "product code", "sku code", "code",
		"الباركود الدولي", "الباركود", "باركود", "كود الصنف", "رقم الصنف", "كود العبوة", "رقم العبوة", "الرمز الشريطي", "الكود", "كود",
	}
	dateCands := []string{
		"transaction date", "sales date", "date", "day",
		"تاريخ البيع", "التاريخ", "تاريخ الحركة", "تاريخ الفاتورة", "تاريخ",
	}
	yearCands := []string{
		"year", "sales year", "السنة", "سنة", "العام", "عام",
	}
	monthCands := []string{
		"month", "sales month", "الشهر", "شهر",
	}
	supplierCands := []string{
		"supplier", "vendor", "manufacturer", "المورد", "مورد", "إسم المورد", "اسم المورد", "الشركة المنتجة",
	}
	primaryCategoryCands := []string{
		"category", "product category", "item category",
		"الفئة", "فئة الصنف", "تصنيف المنتج", "التصنيف", "فئة", "تصنيف",
	}
	secondaryCategoryCands := []string{
		"department", "cat", "القسم",
	}
	categoryCands := append(append([]string{}, primaryCategoryCands...), secondaryCategoryCands...)
	qtyCands := []string{
		"sales units", "qty sold", "quantity sold", "quantity", "qty", "units", "sold units",
		"صافي كمية المبيعات", "صافى كمية المبيعات", "صافي كمية", "صافى كمية", "كمية المبيعات", "الكمية المباعة", "الكمية", "عدد الوحدات", "الوحدات المباعة", "مبيعات بالقطعة", "كمية", "الوحدات",
	}
	revCands := []string{
		"net val egp", "net amount", "net revenue", "revenue", "sales amount", "sales value", "sales val", "total sales", "extended price", "ext price", "extended amount", "line total", "amount", "net sales", "value",
		"صافي قيمة المبيعات", "صافى قيمة المبيعات", "صافي قيمة", "صافى قيمة", "قيمة المبيعات", "صافي المبيعات", "إجمالي المبيعات", "اجمالي المبيعات", "صافي القيمة", "القيمة", "الإيراد", "المبيعات", "قيمة",
	}
	storeNameCands := []string{
		"store code branch", "store name", "branch name", "store", "branch", "outlet",
		"إسم الفرع", "اسم الفرع", "فرع فتح الله", "الفرع", "فرع", "المنفذ", "السلسلة والفرع", "إسم المعرض", "اسم المعرض", "المعرض",
	}
	skuNameCands := []string{
		"item description", "sku name", "product name", "item name", "sku", "product", "description",
		"إسم الصنف", "اسم الصنف", "بيان الصنف", "وصف الصنف", "الصنف", "المنتج", "اسم المنتج", "إسم المنتج", "إسم العبوة", "اسم العبوة", "بيان العبوة", "وصف العبوة", "العبوة",
	}

	usedCol := make(map[int]bool)

	// Pre-pass for primary category exact match so "category" wins over "department" when both exist
	for idx, rawH := range headers {
		h := strings.TrimSpace(strings.TrimPrefix(rawH, "\uFEFF"))
		if h == "" {
			continue
		}
		norm := strings.ToLower(strings.NewReplacer("_", " ", "-", " ").Replace(h))
		if cols.categoryIdx < 0 && matchesExactHeader(norm, h, primaryCategoryCands) {
			cols.categoryIdx = idx
			cols.mapping.CategoryColumn = h
			usedCol[idx] = true
			break
		}
	}

	// Pass 1: Exact header matching so specific columns (e.g., Store_Name, Product_Name, Category)
	// are bound before substring matching.
	for idx, rawH := range headers {
		if usedCol[idx] {
			continue
		}
		h := strings.TrimSpace(strings.TrimPrefix(rawH, "\uFEFF"))
		if h == "" {
			continue
		}
		norm := strings.ToLower(strings.NewReplacer("_", " ", "-", " ").Replace(h))

		if cols.barcodeIdx < 0 && matchesExactHeader(norm, h, barcodeCands) {
			cols.barcodeIdx = idx
			cols.mapping.BarcodeColumn = h
			usedCol[idx] = true
		} else if cols.dateIdx < 0 && matchesExactHeader(norm, h, dateCands) {
			cols.dateIdx = idx
			usedCol[idx] = true
		} else if cols.yearIdx < 0 && matchesExactHeader(norm, h, yearCands) {
			cols.yearIdx = idx
			usedCol[idx] = true
		} else if cols.monthIdx < 0 && matchesExactHeader(norm, h, monthCands) {
			cols.monthIdx = idx
			usedCol[idx] = true
		} else if cols.supplierIdx < 0 && matchesExactHeader(norm, h, supplierCands) {
			cols.supplierIdx = idx
			usedCol[idx] = true
		} else if cols.categoryIdx < 0 && matchesExactHeader(norm, h, categoryCands) {
			cols.categoryIdx = idx
			cols.mapping.CategoryColumn = h
			usedCol[idx] = true
		} else if cols.qtyIdx < 0 && matchesExactHeader(norm, h, qtyCands) {
			cols.qtyIdx = idx
			cols.mapping.QuantitySoldColumn = h
			usedCol[idx] = true
		} else if cols.revIdx < 0 && matchesExactHeader(norm, h, revCands) {
			cols.revIdx = idx
			cols.mapping.NetRevenueColumn = h
			usedCol[idx] = true
		} else if cols.storeNameIdx < 0 && matchesExactHeader(norm, h, storeNameCands) {
			cols.storeNameIdx = idx
			cols.mapping.StoreNameColumn = h
			usedCol[idx] = true
		} else if cols.skuNameIdx < 0 && matchesExactHeader(norm, h, skuNameCands) {
			cols.skuNameIdx = idx
			cols.mapping.SKUNameColumn = h
			usedCol[idx] = true
		}
	}

	// Pass 2: Substring matching for remaining unbound columns, checking specific types
	// (barcode, date, year, month, supplier, category, qty, rev) before broad store/sku substrings.
	for idx, rawH := range headers {
		if usedCol[idx] {
			continue
		}
		h := strings.TrimSpace(strings.TrimPrefix(rawH, "\uFEFF"))
		if h == "" {
			continue
		}
		norm := strings.ToLower(strings.NewReplacer("_", " ", "-", " ").Replace(h))

		if cols.barcodeIdx < 0 && matchesAnyHeader(norm, h, barcodeCands) {
			cols.barcodeIdx = idx
			cols.mapping.BarcodeColumn = h
			usedCol[idx] = true
			continue
		}

		if cols.dateIdx < 0 && matchesAnyHeader(norm, h, dateCands) {
			cols.dateIdx = idx
			usedCol[idx] = true
			continue
		}

		if cols.yearIdx < 0 && matchesAnyHeader(norm, h, yearCands) {
			cols.yearIdx = idx
			usedCol[idx] = true
			continue
		}

		if cols.monthIdx < 0 && matchesAnyHeader(norm, h, monthCands) {
			cols.monthIdx = idx
			usedCol[idx] = true
			continue
		}

		if cols.supplierIdx < 0 && matchesAnyHeader(norm, h, supplierCands) {
			cols.supplierIdx = idx
			usedCol[idx] = true
			continue
		}

		if cols.categoryIdx < 0 && matchesAnyHeader(norm, h, categoryCands) {
			cols.categoryIdx = idx
			cols.mapping.CategoryColumn = h
			usedCol[idx] = true
			continue
		}

		if cols.qtyIdx < 0 && matchesAnyHeader(norm, h, qtyCands) {
			cols.qtyIdx = idx
			cols.mapping.QuantitySoldColumn = h
			usedCol[idx] = true
			continue
		}

		if cols.revIdx < 0 && matchesAnyHeader(norm, h, revCands) {
			cols.revIdx = idx
			cols.mapping.NetRevenueColumn = h
			usedCol[idx] = true
			continue
		}

		if cols.storeNameIdx < 0 &&
			!strings.Contains(norm, "store id") &&
			!strings.Contains(h, "كود الفرع") &&
			matchesAnyHeader(norm, h, storeNameCands) {
			cols.storeNameIdx = idx
			cols.mapping.StoreNameColumn = h
			usedCol[idx] = true
			continue
		}

		if cols.skuNameIdx < 0 &&
			!strings.Contains(norm, "price") &&
			!strings.Contains(norm, "cost") &&
			!strings.Contains(norm, "category") &&
			!strings.Contains(h, "سعر") &&
			!strings.Contains(h, "فئة") &&
			!strings.Contains(h, "تصنيف") &&
			matchesAnyHeader(norm, h, skuNameCands) {
			cols.skuNameIdx = idx
			cols.mapping.SKUNameColumn = h
			usedCol[idx] = true
			continue
		}
	}

	// Fallback if only Store_ID / كود الفرع was provided for store column
	if cols.storeNameIdx < 0 {
		for idx, rawH := range headers {
			if usedCol[idx] {
				continue
			}
			h := strings.TrimSpace(strings.TrimPrefix(rawH, "\uFEFF"))
			norm := strings.ToLower(strings.NewReplacer("_", " ", "-", " ").Replace(h))
			if matchesAnyHeader(norm, h, storeNameCands) {
				cols.storeNameIdx = idx
				cols.mapping.StoreNameColumn = h
				usedCol[idx] = true
				break
			}
		}
	}

	// Valid retail header requires at least barcode and one metric/store column
	recognizedCount := 0
	for _, v := range []int{cols.barcodeIdx, cols.storeNameIdx, cols.skuNameIdx, cols.qtyIdx, cols.revIdx} {
		if v >= 0 {
			recognizedCount++
		}
	}
	isValidHeader := cols.barcodeIdx >= 0 && recognizedCount >= 2
	return cols, isValidHeader
}

func cleanArabicHeader(s string) string {
	s = strings.ReplaceAll(s, "\r", "")
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.TrimSpace(strings.TrimPrefix(s, "\uFEFF"))
	s = strings.ToLower(s)
	s = strings.NewReplacer("_", " ", "-", " ").Replace(s)
	s = strings.Map(func(r rune) rune {
		switch r {
		case 'ـ':
			return -1
		case 'أ', 'إ', 'آ':
			return 'ا'
		case 'ى':
			return 'ي'
		case 'ة':
			return 'ه'
		default:
			return r
		}
	}, s)
	for strings.Contains(s, "  ") {
		s = strings.ReplaceAll(s, "  ", " ")
	}
	return strings.TrimSpace(s)
}

func matchesExactHeader(normLower, rawHeader string, candidates []string) bool {
	cNorm := cleanArabicHeader(normLower)
	for _, cand := range candidates {
		candNorm := cleanArabicHeader(cand)
		if normLower == cand || rawHeader == cand || cNorm == candNorm {
			return true
		}
	}
	return false
}

func matchesAnyHeader(normLower, rawHeader string, candidates []string) bool {
	cNorm := cleanArabicHeader(normLower)
	for _, cand := range candidates {
		candNorm := cleanArabicHeader(cand)
		if normLower == cand || rawHeader == cand || cNorm == candNorm ||
			strings.Contains(normLower, cand) || strings.Contains(rawHeader, cand) ||
			(candNorm != "" && strings.Contains(cNorm, candNorm)) {
			return true
		}
	}
	return false
}

// parseFullTabularPayload parses all rows of a CSV or XLSX file without 4KB truncation.
// Returns (payload, true) if rawContent is a valid retail tabular file with recognizable headers and data rows.
func parseFullTabularPayload(filename string, rawContent []byte) (*domain.NormalizedRetailIngestionPayload, bool) {
	var rows [][]string
	var rowSheetDates map[int]string
	var err error

	if isZipArchive(rawContent) {
		if widePayload, ok := parseWideMatrixXLSX(filename, rawContent); ok {
			return widePayload, true
		}
		rows, rowSheetDates, err = parseXLSXMultiSheetRows(filename, rawContent)
	} else {
		rows, err = parseCSVRows(rawContent)
		if err == nil && len(rows) >= 2 {
			if widePayload, ok := parseWideMatrixCSV(filename, rows); ok {
				return widePayload, true
			}
		}
	}
	if err != nil || len(rows) < 2 {
		return nil, false
	}

	cols, headerIdx, ok := findHeaderRow(rows)
	if !ok || headerIdx+1 >= len(rows) {
		return nil, false
	}

	dataRows := rows[headerIdx+1:]
	// Section-header layout: a branch name row followed by its detail rows (blank store cells).
	applySectionHeaderStoreFill(dataRows, cols.storeNameIdx, cols.barcodeIdx, cols.qtyIdx, cols.revIdx)
	inferTabularTemporalColumnsFromData(dataRows, &cols)
	isLargeDataset := len(dataRows) > 2500
	today := time.Now().Format("2006-01-02")
	if fileYear := inferYearFromText(filename, 0); fileYear >= 2020 && fileYear <= 2035 {
		if d := tryParseArabicSheetMonthDate(filename, fileYear); d != "" {
			today = d
		} else {
			today = fmt.Sprintf("%04d-01-31", fileYear)
		}
	}
	minDate := ""
	maxDate := ""

	var records []domain.NormalizedRecord
	var anomalies []domain.IngestionAnomaly
	var storeSamples []string
	var supplierSamples []string
	branchSet := make(map[string]bool)
	categorySet := make(map[string]bool)

	// Sample up to 3,000 rows for fast chain voting without scanning 250k+ rows twice
	sampleStep := 1
	if len(dataRows) > 3000 {
		sampleStep = len(dataRows) / 3000
	}
	for i := 0; i < len(dataRows); i += sampleStep {
		r := dataRows[i]
		if isRowEmpty(r) {
			continue
		}
		if cols.storeNameIdx >= 0 && cols.storeNameIdx < len(r) {
			storeSamples = append(storeSamples, r[cols.storeNameIdx])
		}
		if cols.supplierIdx >= 0 && cols.supplierIdx < len(r) {
			supplierSamples = append(supplierSamples, r[cols.supplierIdx])
		}
	}

	retailer := detectRetailerWithSuppliers(filename, storeSamples, supplierSamples)

	dataRowNum := 0
	rawValidRowsCount := 0
	totalValidRev := 0.0
	totalValidUnits := 0
	totalOwnRev := 0.0
	totalOwnUnits := 0
	totalMarketRev := 0.0
	skuPriceFreq := make(map[string]map[float64]int)
	skuMaxPrice := make(map[string]float64)

	// High-speed memoization caches for 250k+ row datasets
	type resolvedStoreEntry struct {
		id      string
		matched bool
	}
	storeCache := make(map[string]resolvedStoreEntry, 64)
	catCache := make(map[string]string, 64)
	supOwnCache := make(map[string]bool, 128)
	barcodeCache := make(map[string]string, 2048)
	dateCache := make(map[string]string, 64)

	type supAgg struct {
		name     string
		rev      float64
		units    int
		skus     map[string]bool
		isTenant bool
	}
	supplierMap := make(map[string]*supAgg)
	categoryMarketTotals := make(map[string]float64)

	type monthSummary struct {
		ownRev    float64
		ownUnits  int
		mktRev    float64
		rowCount  int
		maxTxDate string
	}
	monthlyMap := make(map[string]*monthSummary)

	// Consolidation index for large multi-supplier files so 250k+ rows aggregate cleanly in memory
	consolidatedIdx := make(map[string]int)

	// An unknown retailer is never treated as Gomla: the processor re-keys stores to the chain the
	// uploader chose (this used to produce gom_ ids on qa_test uploads).
	effectiveRetailerForStore := retailer

	for rowIdx, r := range dataRows {
		if isRowEmpty(r) {
			continue
		}
		dataRowNum++

		rawStoreCell := getCell(r, cols.storeNameIdx)
		chainLabel, branchLabel := ParseChainBranchCell(rawStoreCell)
		rawStore := branchLabel
		if rawStore == "" {
			rawStore = strings.TrimSpace(rawStoreCell)
		}
		rowRetailer := effectiveRetailerForStore
		if chainLabel != "" {
			if resolved := resolveChainCodeFromCustomerLabel(chainLabel, ""); resolved != "" {
				rowRetailer = resolved
			}
		}
		rawBarcode := getCell(r, cols.barcodeIdx)
		rawSKU := getCell(r, cols.skuNameIdx)
		rawCatCell := getCell(r, cols.categoryIdx)
		rawSupplier := getCell(r, cols.supplierIdx)
		rawQty := getCell(r, cols.qtyIdx)
		rawRev := getCell(r, cols.revIdx)
		rawDate := getCell(r, cols.dateIdx)
		rawYear := getCell(r, cols.yearIdx)
		rawMonth := getCell(r, cols.monthIdx)
		sheetFallbackDate := ""
		if rowSheetDates != nil {
			sheetFallbackDate = rowSheetDates[rowIdx]
		}

		cleanedBarcode, ok := barcodeCache[rawBarcode]
		if !ok {
			cleanedBarcode = normalizeBarcodeValue(rawBarcode)
			if cleanedBarcode == "" {
				cleanedBarcode = strings.TrimSpace(rawBarcode)
			}
			barcodeCache[rawBarcode] = cleanedBarcode
		}

		rawCategory, ok := catCache[rawCatCell]
		if !ok {
			rawCategory = domain.NormalizeProductCategory(rawCatCell)
			catCache[rawCatCell] = rawCategory
		}

		rev := parseRevenueFloat(rawRev)
		qty := parseQuantityInt(rawQty)
		qtyInvented := cols.qtyIdx < 0 && qty == 0 && rev > 0
		if cols.qtyIdx < 0 && qty == 0 && rev > 0 {
			if isLargeDataset {
				qty = int(math.Max(1, math.Round(rev/45.0)))
			} else {
				qty = 1
			}
		}

		storeCacheKey := rowRetailer + "|" + rawStore
		stEntry, ok := storeCache[storeCacheKey]
		if !ok {
			id, matched := resolveCanonicalStoreID(rowRetailer, rawStore)
			stEntry = resolvedStoreEntry{id: id, matched: matched}
			storeCache[storeCacheKey] = stEntry
		}
		resolvedStoreID := stEntry.id
		storeMatched := stEntry.matched

		if rawStore == "" {
			rawStore = defaultStoreNameForRetailer(rowRetailer)
		}
		// Group by Arabic-normalized branch so عائلة/عائله variants collapse; keep first spelling.
		branchSet[rawStore] = true

		isOwn, ok := supOwnCache[rawSupplier]
		if !ok {
			isOwn = isAdcoOrTenantSupplier(rawSupplier)
			supOwnCache[rawSupplier] = isOwn
		}
		if rawCategory != "" && isOwn {
			categorySet[rawCategory] = true
		}

		if rawSKU == "" {
			rawSKU = defaultSKUNameForBarcode(cleanedBarcode)
		}

		dateKey := rawDate + "|" + rawYear + "|" + rawMonth + "|" + sheetFallbackDate
		txDate, ok := dateCache[dateKey]
		dateFromFile := rawDate != "" || rawYear != "" || rawMonth != "" || sheetFallbackDate != ""
		if !ok {
			ymDate := ""
			if rawYear != "" || rawMonth != "" {
				ymDate = resolveYearMonthDate(rawYear, rawMonth, "")
			}
			if rawDate != "" {
				txDate = normalizeDateString(rawDate, "")
			}
			if txDate == "" || (ymDate != "" && cols.yearIdx >= 0 && cols.monthIdx >= 0) {
				if ymDate != "" {
					txDate = ymDate
				}
			}
			if txDate == "" {
				if sheetFallbackDate != "" {
					txDate = sheetFallbackDate
				} else {
					txDate = today
				}
			}
			if !dateFromFile {
				txDate = today
			}
			dateCache[dateKey] = txDate
		}

		if minDate == "" || txDate < minDate {
			minDate = txDate
		}
		if maxDate == "" || txDate > maxDate {
			maxDate = txDate
		}

		// Record row-level anomalies with exact 1-based data row index
		isRowAnomaly := false
		if rev < 0 || qty <= 0 {
			isRowAnomaly = true
			if len(anomalies) < 250 {
				anomalies = append(anomalies, domain.IngestionAnomaly{
					RowNumber:   dataRowNum,
					IssueType:   "negative_sales",
					Description: fmt.Sprintf("Negative or zero sales value detected in row %d (Qty: %d, Rev: %.2f)", dataRowNum, qty, rev),
				})
			}
		} else if len(cleanedBarcode) < 6 {
			isRowAnomaly = true
			if len(anomalies) < 250 {
				anomalies = append(anomalies, domain.IngestionAnomaly{
					RowNumber:   dataRowNum,
					IssueType:   "invalid_barcode",
					Description: fmt.Sprintf("Short or non-standard barcode '%s' in row %d", cleanedBarcode, dataRowNum),
				})
			}
		} else if !storeMatched && rawStore != "" {
			_ = storeMatched
		}

		if !isRowAnomaly {
			rawValidRowsCount++
			totalValidRev += rev
			totalValidUnits += qty
			totalMarketRev += rev
			if isOwn {
				totalOwnRev += rev
				totalOwnUnits += qty
			}
			if rawCategory != "" {
				categoryMarketTotals[rawCategory] += rev
			}

			if rawSupplier != "" {
				supKey := rawSupplier
				if isOwn {
					supKey = "ادكو (شركة الإسكندرية للمنظفات)"
				}
				sa, exists := supplierMap[supKey]
				if !exists {
					sa = &supAgg{
						name:     supKey,
						skus:     make(map[string]bool),
						isTenant: isOwn,
					}
					supplierMap[supKey] = sa
				}
				sa.rev += rev
				sa.units += qty
				sa.skus[cleanedBarcode] = true
			}

			if len(txDate) >= 7 {
				ym := txDate[:7]
				ms, exists := monthlyMap[ym]
				if !exists {
					ms = &monthSummary{maxTxDate: txDate}
					monthlyMap[ym] = ms
				}
				ms.rowCount++
				ms.mktRev += rev
				if isOwn {
					ms.ownRev += rev
					ms.ownUnits += qty
				}
				if txDate > ms.maxTxDate {
					ms.maxTxDate = txDate
				}
			}
		}

		uPrice := 0.0
		if qty > 0 && rev > 0 {
			uPrice = math.Round((rev/float64(qty))*100) / 100
			if isOwn || !isLargeDataset {
				roundedHalf := math.Round(uPrice*2) / 2
				if skuPriceFreq[cleanedBarcode] == nil {
					skuPriceFreq[cleanedBarcode] = make(map[float64]int)
				}
				skuPriceFreq[cleanedBarcode][roundedHalf]++
				if uPrice > skuMaxPrice[cleanedBarcode] {
					skuMaxPrice[cleanedBarcode] = uPrice
				}
			}
		}

		if isLargeDataset && !isRowAnomaly {
			// Consolidate large datasets: keep full branch+SKU+date granularity for tenant (isOwn) rows,
			// and consolidate competitor (!isOwn) rows by supplier+SKU+date across branches.
			var cKey string
			if isOwn {
				cKey = "own|" + resolvedStoreID + "|" + cleanedBarcode + "|" + txDate
			} else {
				cKey = "comp|" + rawSupplier + "|" + cleanedBarcode + "|" + txDate
			}
			if existingIdx, exists := consolidatedIdx[cKey]; exists {
				records[existingIdx].QuantitySold += qty
				records[existingIdx].NetRevenue = math.Round((records[existingIdx].NetRevenue+rev)*100) / 100
				if records[existingIdx].QuantitySold > 0 {
					records[existingIdx].UnitPrice = math.Round((records[existingIdx].NetRevenue/float64(records[existingIdx].QuantitySold))*100) / 100
				}
				continue
			}
			consolidatedIdx[cKey] = len(records)
		}

		records = append(records, domain.NormalizedRecord{
			RawStoreName:     rawStore,
			ResolvedStoreID:  resolvedStoreID,
			Barcode:          cleanedBarcode,
			SKUName:          rawSKU,
			Category:         rawCategory,
			Supplier:         rawSupplier,
			IsOwnBrand:       isOwn,
			QuantitySold:     qty,
			NetRevenue:       rev,
			UnitPrice:        uPrice,
			RecommendedPrice: uPrice,
			TransactionDate:  txDate,
			DateFromFile:     dateFromFile,
			QtyInvented:      qtyInvented,
		})
	}

	if len(records) == 0 {
		return nil, false
	}

	if minDate == "" {
		minDate = time.Now().AddDate(0, 0, -7).Format("2006-01-02")
	}
	if maxDate == "" {
		maxDate = today
	}

	// Infer modal RecommendedPrice per SKU across branches and generate pricing/OOS items when multi-branch
	skuModalRRP := make(map[string]float64)
	for bc, freqMap := range skuPriceFreq {
		bestFreq := 0
		bestPrice := skuMaxPrice[bc]
		for pVal, freq := range freqMap {
			if freq > bestFreq || (freq == bestFreq && pVal > bestPrice) {
				bestFreq = freq
				bestPrice = pVal
			}
		}
		if bestPrice > 0 {
			skuModalRRP[bc] = bestPrice
		}
	}

	var computedPricing []domain.PricingComplianceItem
	for i := range records {
		if rrp, ok := skuModalRRP[records[i].Barcode]; ok && rrp > 0 {
			records[i].RecommendedPrice = rrp
			if records[i].IsOwnBrand && len(branchSet) >= 3 && records[i].UnitPrice > 0 && records[i].QuantitySold > 0 && records[i].NetRevenue > 0 {
				deltaPct := domain.CalculatePriceDeltaPct(records[i].UnitPrice, rrp)
				vType := domain.ClassifyPriceViolation(deltaPct)
				if (vType != "compliant" || records[i].NetRevenue >= 3000) && len(computedPricing) < 80 {
					effChain := retailer
					if effChain == "" {
						effChain = "gomla"
					}
					computedPricing = append(computedPricing, domain.PricingComplianceItem{
						TenantID:         "tenant-adeco",
						SKUName:          records[i].SKUName,
						Barcode:          records[i].Barcode,
						Category:         records[i].Category,
						RetailerChain:    effChain,
						StoreName:        records[i].RawStoreName,
						ActualPrice:      records[i].UnitPrice,
						RecommendedPrice: rrp,
						PriceDeltaPct:    deltaPct,
						ViolationType:    vType,
						IsPromoActive:    deltaPct <= -5.0 || strings.Contains(records[i].SKUName, "عرض"),
						PromoUpliftPct:   math.Round(math.Abs(deltaPct)*1.5*10) / 10,
					})
				}
			}
		}
	}

	discoveredBranches := make([]string, 0, len(branchSet))
	for b := range branchSet {
		discoveredBranches = append(discoveredBranches, b)
	}
	sort.Strings(discoveredBranches)

	discoveredCategories := make([]string, 0, len(categorySet))
	for c := range categorySet {
		discoveredCategories = append(discoveredCategories, c)
	}
	sort.Strings(discoveredCategories)

	// Build SupplierShares when multiple suppliers exist in the tabular sheet
	var supplierShares []domain.SupplierShareSummary
	if len(supplierMap) > 1 && totalMarketRev > 0 {
		for _, sa := range supplierMap {
			sharePct := math.Round((sa.rev/totalMarketRev)*10000) / 100
			supplierShares = append(supplierShares, domain.SupplierShareSummary{
				SupplierName: sa.name,
				TotalRevenue: math.Round(sa.rev*100) / 100,
				TotalUnits:   sa.units,
				SKUCount:     len(sa.skus),
				MarketShare:  sharePct,
				IsTenant:     sa.isTenant,
			})
		}
		sort.Slice(supplierShares, func(i, j int) bool {
			return supplierShares[i].TotalRevenue > supplierShares[j].TotalRevenue
		})
	}

	// Build DetectedSheets and MonthlyTrends across discovered months
	var discoveredSheets []domain.DiscoveredSheetInfo
	var monthlyTrends []domain.DailyTrendPoint
	if len(monthlyMap) > 1 {
		ymKeys := make([]string, 0, len(monthlyMap))
		for ym := range monthlyMap {
			ymKeys = append(ymKeys, ym)
		}
		sort.Strings(ymKeys)
		for _, ym := range ymKeys {
			ms := monthlyMap[ym]
			revToReport := ms.ownRev
			unitsToReport := ms.ownUnits
			if revToReport == 0 {
				revToReport = ms.mktRev
			}
			discoveredSheets = append(discoveredSheets, domain.DiscoveredSheetInfo{
				Name:         ym,
				State:        "visible",
				RowCount:     ms.rowCount,
				RecordsCount: ms.rowCount,
				TotalRevenue: math.Round(revToReport*100) / 100,
				TotalUnits:   unitsToReport,
				PeriodDate:   ms.maxTxDate,
			})
			monthlyTrends = append(monthlyTrends, domain.DailyTrendPoint{
				Date:     ms.maxTxDate,
				MonthKey: ym,
				Revenue:  math.Round(revToReport*100) / 100,
				Units:    unitsToReport,
			})
		}
	} else {
		revToReport := totalValidRev
		unitsToReport := totalValidUnits
		if len(supplierMap) > 1 && totalOwnRev > 0 {
			revToReport = totalOwnRev
			unitsToReport = totalOwnUnits
		}
		discoveredSheets = []domain.DiscoveredSheetInfo{
			{
				Name:         "Sheet1",
				State:        "visible",
				RowCount:     rawValidRowsCount,
				RecordsCount: rawValidRowsCount,
				TotalRevenue: math.Round(revToReport*100) / 100,
				TotalUnits:   unitsToReport,
				PeriodDate:   maxDate,
			},
		}
	}

	return &domain.NormalizedRetailIngestionPayload{
		RetailerDetected:     retailer,
		ReportingPeriodStart: minDate,
		ReportingPeriodEnd:   maxDate,
		ConfidenceScore:      0.992,
		RawValidRowsCount:    rawValidRowsCount,
		ColumnMapping:        cols.mapping,
		AnomaliesDetected:    anomalies,
		NormalizedRecords:    records,
		DiscoveredBranches:   discoveredBranches,
		DiscoveredCategories: discoveredCategories,
		SupplierShares:       supplierShares,
		CategoryMarketTotals: categoryMarketTotals,
		MonthlyTrends:        monthlyTrends,
		DetectedSheets:       discoveredSheets,
		ComputedPricingItems: computedPricing,
	}, true
}

func inferTabularTemporalColumnsFromData(dataRows [][]string, cols *discoveredColumns) {
	if len(dataRows) == 0 || cols == nil {
		return
	}
	if cols.dateIdx >= 0 && cols.yearIdx >= 0 && cols.monthIdx >= 0 {
		return
	}

	bound := map[int]bool{
		cols.barcodeIdx:   true,
		cols.skuNameIdx:   true,
		cols.storeNameIdx: true,
		cols.qtyIdx:       true,
		cols.revIdx:       true,
		cols.categoryIdx:  true,
		cols.supplierIdx:  true,
		cols.dateIdx:      true,
		cols.yearIdx:      true,
		cols.monthIdx:     true,
	}

	numCols := 0
	sampleLimit := len(dataRows)
	if sampleLimit > 200 {
		sampleLimit = 200
	}
	for i := 0; i < sampleLimit; i++ {
		if len(dataRows[i]) > numCols {
			numCols = len(dataRows[i])
		}
	}

	for colIdx := 0; colIdx < numCols; colIdx++ {
		if bound[colIdx] {
			continue
		}
		nonEmpty := 0
		yearHits := 0
		monthHits := 0
		dateHits := 0

		for rIdx := 0; rIdx < sampleLimit; rIdx++ {
			val := getCell(dataRows[rIdx], colIdx)
			if val == "" {
				continue
			}
			nonEmpty++
			clean := normalizeArabicDigitsToASCII(strings.TrimSpace(val))

			if len(clean) == 4 {
				var yr int
				if _, err := fmt.Sscanf(clean, "%d", &yr); err == nil && yr >= 2020 && yr <= 2035 {
					yearHits++
					continue
				}
			}

			hasLetters := false
			for _, r := range clean {
				if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= 0x0600 && r <= 0x06FF) {
					hasLetters = true
					break
				}
			}
			if hasLetters && parseSmartMonthToken(clean) > 0 {
				monthHits++
				continue
			}

			if len(clean) >= 8 && (strings.Contains(clean, "-") || strings.Contains(clean, "/")) {
				if d := normalizeDateString(clean, ""); d != "" {
					dateHits++
				}
			}
		}

		if nonEmpty < 3 {
			continue
		}
		if cols.yearIdx < 0 && float64(yearHits)/float64(nonEmpty) >= 0.85 {
			cols.yearIdx = colIdx
			bound[colIdx] = true
		} else if cols.monthIdx < 0 && float64(monthHits)/float64(nonEmpty) >= 0.80 {
			cols.monthIdx = colIdx
			bound[colIdx] = true
		} else if cols.dateIdx < 0 && float64(dateHits)/float64(nonEmpty) >= 0.80 {
			cols.dateIdx = colIdx
			bound[colIdx] = true
		}
	}
}

func resolveYearMonthDate(rawYear, rawMonth, fallback string) string {
	yr := inferYearFromText(rawYear, 0)
	if yr == 0 {
		if y, err := strconv.Atoi(strings.TrimSpace(rawYear)); err == nil {
			if y >= 2000 && y <= 2100 {
				yr = y
			} else if y >= 20 && y <= 99 {
				yr = 2000 + y
			}
		}
	}
	mo := parseSmartMonthToken(rawMonth)
	if mo >= 1 && mo <= 12 {
		effectiveYr := yr
		if effectiveYr == 0 {
			effectiveYr = inferYearFromText(rawMonth, 2026)
		}
		lastDay := time.Date(effectiveYr, time.Month(mo)+1, 0, 0, 0, 0, 0, time.UTC).Day()
		return fmt.Sprintf("%04d-%02d-%02d", effectiveYr, mo, lastDay)
	}
	combined := strings.TrimSpace(rawMonth)
	if yr > 0 {
		combined = fmt.Sprintf("%s %d", combined, yr)
	}
	if parsed := tryParseArabicSheetMonthDate(combined, yr); parsed != "" {
		return parsed
	}
	if yr > 0 {
		if m, err := strconv.Atoi(strings.TrimSpace(rawMonth)); err == nil && m >= 1 && m <= 12 {
			lastDay := time.Date(yr, time.Month(m)+1, 0, 0, 0, 0, 0, time.UTC).Day()
			return fmt.Sprintf("%04d-%02d-%02d", yr, m, lastDay)
		}
		return fmt.Sprintf("%04d-01-31", yr)
	}
	return fallback
}

func isRowEmpty(row []string) bool {
	for _, cell := range row {
		if strings.TrimSpace(cell) != "" {
			return false
		}
	}
	return true
}

func getCell(row []string, idx int) string {
	if idx < 0 || idx >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[idx])
}

func normalizeBarcodeValue(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	// Handle scientific notation like 6.221155001234E+12
	if strings.ContainsAny(trimmed, "eE") {
		if f, err := strconv.ParseFloat(trimmed, 64); err == nil && f > 1e7 {
			return fmt.Sprintf("%.0f", f)
		}
	}
	return domain.CleanBarcode(trimmed)
}

func parseQuantityInt(raw string) int {
	clean := strings.NewReplacer(",", "", " ", "", "قطعة", "", "علبة", "").Replace(strings.TrimSpace(raw))
	if clean == "" {
		return 0
	}
	if i, err := strconv.Atoi(clean); err == nil {
		return i
	}
	if f, err := strconv.ParseFloat(clean, 64); err == nil {
		return int(math.Round(f))
	}
	return 0
}

func parseRevenueFloat(raw string) float64 {
	clean := strings.NewReplacer(",", "", " ", "", "EGP", "", "ج.م", "", "جنيه", "").Replace(strings.TrimSpace(raw))
	if clean == "" {
		return 0.0
	}
	if f, err := strconv.ParseFloat(clean, 64); err == nil {
		return f
	}
	return 0.0
}

func normalizeDateString(raw, fallback string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return fallback
	}

	// Handle Excel 1900 numeric serial date values (e.g., 46088 -> 2026-03-07)
	if f, err := strconv.ParseFloat(trimmed, 64); err == nil && f >= 30000 && f <= 80000 {
		days := int(math.Floor(f))
		excelEpoch := time.Date(1899, 12, 30, 0, 0, 0, 0, time.UTC)
		return excelEpoch.AddDate(0, 0, days).Format("2006-01-02")
	}

	candidates := []string{trimmed}
	if sp := strings.IndexByte(trimmed, ' '); sp > 0 {
		candidates = append(candidates, strings.TrimSpace(trimmed[:sp]))
	}
	if tIdx := strings.IndexByte(trimmed, 'T'); tIdx > 0 {
		candidates = append(candidates, strings.TrimSpace(trimmed[:tIdx]))
	}

	layouts := []string{
		"2006-01-02",
		"2006-1-2",
		"2006/01/02",
		"2006/1/2",
		"02/01/2006",
		"2/1/2006",
		"01/02/2006",
		"1/2/2006",
		"02-01-2006",
		"2-1-2006",
		"01-02-2006",
		"1-2-2006",
		time.RFC3339,
	}
	for _, cand := range candidates {
		for _, layout := range layouts {
			if t, err := time.Parse(layout, cand); err == nil {
				return t.Format("2006-01-02")
			}
		}
	}
	if len(trimmed) >= 10 {
		if t, err := time.Parse("2006-01-02", trimmed[:10]); err == nil {
			return t.Format("2006-01-02")
		}
	}
	return fallback
}

func detectRetailer(filename string, storeSamples []string) string {
	return detectRetailerWithSuppliers(filename, storeSamples, nil)
}

func detectRetailerWithSuppliers(filename string, storeSamples []string, supplierSamples []string) string {
	lowerFile := strings.ToLower(filename)

	if strings.Contains(filename, "الوكالة") || strings.Contains(filename, "الوكاله") || strings.Contains(lowerFile, "wakala") {
		return "chain-1080314"
	}

	votes := map[string]int{
		"carrefour":    0,
		"fathalla":     0,
		"gomla":        0,
		"beet-elgomla": 0,
		"spinneys":     0,
	}

	// Filename votes (weight: 10)
	if strings.Contains(lowerFile, "carrefour") || strings.Contains(filename, "كارفور") {
		votes["carrefour"] += 10
	}
	if strings.Contains(lowerFile, "fathalla") || strings.Contains(filename, "فتح الله") || strings.Contains(filename, "فتح_الله") {
		votes["fathalla"] += 10
	}
	if strings.Contains(lowerFile, "beet") || strings.Contains(filename, "بيت الجملة") || strings.Contains(filename, "بيت الجمله") {
		votes["beet-elgomla"] += 12
	} else if strings.Contains(lowerFile, "gomla") || (strings.Contains(filename, "جملة") && !strings.Contains(filename, "فتح الله")) {
		votes["gomla"] += 10
	}
	if strings.Contains(lowerFile, "spinneys") || strings.Contains(filename, "سبينيس") {
		votes["spinneys"] += 10
	}

	beetElGomlaDistinctBranches := []string{
		"دارك ستور سموحة", "أكتوبر-سيلفر مول", "مدينتى - بي 12", "بير مسعود",
		"الدرايسة", "الحديد و الصلب", "كرافت زون", "شارع الثلاثين", "عرامة",
	}

	gomlaDistinctBranches := []string{
		"سهل حمزة", "مشعل", "الكوثر", "شارع المطار", "جرين تاورز", "ميدان العروسة",
		"وابور المياة", "الفراعنة", "حدائق الاهرام", "المنصورية", "أبو رواش", "ابو رواش",
	}

	// Deduplicate store samples with frequency weights for instant voting
	storeFreq := make(map[string]int, 64)
	for _, s := range storeSamples {
		if s != "" {
			storeFreq[s]++
		}
	}

	for s, weight := range storeFreq {
		sLower := strings.ToLower(s)
		if strings.Contains(sLower, "carrefour") || strings.Contains(s, "كارفور") {
			votes["carrefour"] += weight
		}
		if strings.Contains(sLower, "fathalla") || strings.Contains(s, "فتح الله") || strings.Contains(s, "فتح_الله") {
			votes["fathalla"] += weight
		}
		if strings.Contains(s, "بيت الجملة") || strings.Contains(s, "بيت الجمله") {
			votes["beet-elgomla"] += weight
		} else if strings.Contains(sLower, "gomla") || (strings.Contains(s, "جملة") && !strings.Contains(s, "فتح الله")) {
			votes["gomla"] += weight
		}
		if strings.Contains(sLower, "spinneys") || strings.Contains(s, "سبينيس") {
			votes["spinneys"] += weight
		}
		for _, bg := range beetElGomlaDistinctBranches {
			if strings.Contains(s, bg) {
				votes["beet-elgomla"] += weight * 2
				break
			}
		}
		for _, gb := range gomlaDistinctBranches {
			if strings.Contains(s, gb) {
				votes["gomla"] += weight
				break
			}
		}
	}

	// Supplier code signatures (e.g. "ادكو / 318" in Gomla Market ERP exports)
	for _, sup := range supplierSamples {
		if strings.Contains(sup, "/ 318") || strings.Contains(sup, "/318") {
			votes["gomla"]++
		}
	}

	bestRetailer := ""
	maxVotes := 0
	for retailer, count := range votes {
		if count > maxVotes {
			maxVotes = count
			bestRetailer = retailer
		}
	}

	if maxVotes > 0 {
		return bestRetailer
	}
	return ""
}

func resolveCanonicalStoreID(retailer, rawStore string) (string, bool) {
	lower := strings.ToLower(strings.TrimSpace(rawStore))
	switch retailer {
	case "carrefour":
		switch {
		case strings.Contains(lower, "maadi") || strings.Contains(rawStore, "المعادي"):
			return "crf_cairo_maadi", true
		case strings.Contains(lower, "dandy") || strings.Contains(rawStore, "داندي"):
			return "crf_giza_dandy", true
		case strings.Contains(lower, "city stars") || strings.Contains(lower, "citystars") || strings.Contains(rawStore, "سيتي ستارز"):
			return "crf_cairo_citystars", true
		case strings.Contains(lower, "festival") || strings.Contains(rawStore, "فيستيفال"):
			return "crf_cairo_festival", true
		case strings.Contains(lower, "alex") || strings.Contains(rawStore, "الإسكندرية") || strings.Contains(rawStore, "الاسكندرية"):
			return "crf_alex_citycentre", true
		case strings.Contains(lower, "october") || strings.Contains(rawStore, "أكتوبر") || strings.Contains(rawStore, "مول مصر"):
			return "crf_giza_october", true
		default:
			if strings.TrimSpace(rawStore) != "" {
				return BuildBranchStoreMetadata(retailer, rawStore).ID, true
			}
			return "crf_cairo_maadi", false
		}
	case "fathalla":
		switch {
		case (strings.Contains(lower, "smouha") || strings.Contains(rawStore, "سموحة")) && !strings.Contains(rawStore, "ميني"):
			return "fat_alex_smouha", true
		case (strings.Contains(lower, "stanley") || strings.Contains(rawStore, "ستانلي")) && !strings.Contains(rawStore, "ستانلى"):
			return "fat_alex_stanley", true
		case strings.Contains(lower, "mansheya") || strings.Contains(rawStore, "المنشية"):
			return "fat_alex_mansheya", true
		case strings.Contains(lower, "agami") || strings.Contains(rawStore, "العجمي") || strings.Contains(rawStore, "بيطاش") || strings.Contains(rawStore, "بيانكي"):
			return "fat_alex_agami", true
		case strings.Contains(lower, "stefano") || strings.Contains(rawStore, "سان ستيفانو"):
			return "fat_alex_sanstefano", true
		default:
			if strings.TrimSpace(rawStore) != "" {
				return BuildBranchStoreMetadata(retailer, rawStore).ID, true
			}
			return "fat_alex_smouha", false
		}
	case "spinneys":
		switch {
		case strings.Contains(lower, "arab") || strings.Contains(rawStore, "مول العرب"):
			return "spi_giza_mollarab", true
		case strings.Contains(lower, "new cairo") || strings.Contains(rawStore, "التجمع"):
			return "spi_cairo_newcairo", true
		case strings.Contains(lower, "zayed") || strings.Contains(rawStore, "الشيخ زايد"):
			return "spi_giza_zayed", true
		case strings.Contains(lower, "rehab") || strings.Contains(rawStore, "الرحاب"):
			return "spi_cairo_rehab", true
		default:
			if strings.TrimSpace(rawStore) != "" {
				return BuildBranchStoreMetadata(retailer, rawStore).ID, true
			}
			return "spi_giza_mollarab", false
		}
	case "beet-elgomla", "beet_elgomla":
		if strings.TrimSpace(rawStore) != "" {
			return BuildBranchStoreMetadata("beet-elgomla", rawStore).ID, true
		}
		return "bet_alex_smouha", false
	case "gomla":
		switch {
		case strings.Contains(lower, "nasr") || strings.Contains(rawStore, "مدينة نصر"):
			return "gom_cairo_nasrcity", true
		case strings.Contains(lower, "dokki") || strings.Contains(rawStore, "الدقي"):
			return "gom_giza_dokki", true
		case strings.Contains(lower, "heliopolis") || strings.Contains(rawStore, "مصر الجديدة"):
			return "gom_cairo_heliopolis", true
		case strings.Contains(lower, "bishr") || strings.Contains(rawStore, "سيدي بشر"):
			return "gom_alex_sidibishr", true
		default:
			if strings.TrimSpace(rawStore) != "" {
				return BuildBranchStoreMetadata("gomla", rawStore).ID, true
			}
			return "gom_cairo_nasrcity", false
		}
	default:
		if strings.TrimSpace(rawStore) != "" {
			return BuildBranchStoreMetadata(retailer, rawStore).ID, true
		}
		if strings.TrimSpace(retailer) == "" {
			// No chain: never attribute the row to Gomla (it used to fall into the gomla case).
			return "store_unassigned_main", false
		}
		return fmt.Sprintf("store_%s_main", strings.ToLower(strings.TrimSpace(retailer))), false
	}
}

func defaultStoreNameForRetailer(retailer string) string {
	switch retailer {
	case "carrefour":
		return "Carrefour Maadi City Center"
	case "fathalla":
		return "فتح الله جملة ماركت - فرع سموحة"
	case "spinneys":
		return "سبينيس - مول العرب"
	case "beet-elgomla", "beet_elgomla":
		return "فرع بيت الجملة - سموحة"
	case "gomla":
		return "Gomla Market Nasr City"
	case "":
		return "فرع غير محدد"
	default:
		if name, ok := domain.GetCustomChainDisplayName(retailer); ok && name != "" {
			return name + " - الفرع الرئيسي"
		}
		return retailer + " - الفرع الرئيسي"
	}
}

func defaultSKUNameForBarcode(barcode string) string {
	known := map[string]string{
		"6221155001234": "Adeco Extra Virgin Olive Oil 500ml",
		"6221155001241": "Adeco Pure Sunflower Oil 1L",
		"6221155001258": "Adeco Pure Corn Oil 800ml",
		"6221155001265": "Adeco Canola Blend 750ml",
		"6221155002019": "Adeco Premium Tomato Paste 380g",
		"6221155002026": "Adeco Peeled Whole Tomatoes 400g",
		"6221155003016": "Adeco Traditional Fava Beans 400g",
	}
	if name, ok := known[barcode]; ok {
		return name
	}
	return fmt.Sprintf("Retail SKU %s", barcode)
}
