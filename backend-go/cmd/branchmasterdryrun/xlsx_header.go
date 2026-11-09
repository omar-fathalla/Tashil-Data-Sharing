package main

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"io"
	"strings"
)

// readXLSXHeaderBranches extracts Arabic/branch header cells from the first row of
// sheet1 (or the first worksheet), skipping meta / qty / month columns.
func readXLSXHeaderBranches(path string) ([]string, error) {
	zr, err := zip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer zr.Close()

	shared, err := readSharedStrings(zr)
	if err != nil {
		return nil, err
	}
	sheetName, err := firstWorksheetPath(zr)
	if err != nil {
		return nil, err
	}
	var sheetFile *zip.File
	for _, f := range zr.File {
		if f.Name == sheetName {
			sheetFile = f
			break
		}
	}
	if sheetFile == nil {
		return nil, fmt.Errorf("worksheet %s not found", sheetName)
	}
	rc, err := sheetFile.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	type cVal struct {
		T string `xml:"t,attr"`
		V string `xml:"v"`
		Is struct {
			T string `xml:"t"`
		} `xml:"is"`
	}
	type cCell struct {
		R string `xml:"r,attr"`
		C cVal   `xml:",any"`
	}
	// Stream tokens until we finish row 1.
	dec := xml.NewDecoder(rc)
	var (
		inSheetData, inRow1 bool
		colVals             []string
		maxCol              int
	)
	cellAt := map[int]string{}
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "sheetData":
				inSheetData = true
			case "row":
				if !inSheetData {
					continue
				}
				rIdx := attr(t, "r")
				inRow1 = rIdx == "1" || rIdx == ""
				if rIdx != "" && rIdx != "1" && len(cellAt) > 0 {
					// Finished row 1.
					goto done
				}
			case "c":
				if !inRow1 {
					continue
				}
				ref := attr(t, "r")
				tAttr := attr(t, "t")
				col := colIndex(ref)
				var v struct {
					V  string `xml:"v"`
					Is struct {
						T string `xml:"t"`
					} `xml:"is"`
				}
				if err := dec.DecodeElement(&v, &t); err != nil {
					return nil, err
				}
				val := strings.TrimSpace(v.V)
				if tAttr == "s" {
					// shared string index
					var idx int
					fmt.Sscanf(val, "%d", &idx)
					if idx >= 0 && idx < len(shared) {
						val = shared[idx]
					}
				} else if tAttr == "inlineStr" {
					val = strings.TrimSpace(v.Is.T)
				}
				val = strings.TrimSpace(val)
				if val != "" {
					cellAt[col] = val
					if col > maxCol {
						maxCol = col
					}
				}
			}
		case xml.EndElement:
			if t.Name.Local == "row" && inRow1 && len(cellAt) > 0 {
				goto done
			}
		}
	}
done:
	for i := 0; i <= maxCol; i++ {
		if v, ok := cellAt[i]; ok {
			colVals = append(colVals, v)
		} else {
			colVals = append(colVals, "")
		}
	}
	return filterBranchHeaders(colVals), nil
}

func filterBranchHeaders(cells []string) []string {
	var out []string
	seen := map[string]bool{}
	for i, s := range cells {
		s = strings.TrimSpace(s)
		if s == "" || i < 4 {
			continue
		}
		up := strings.ToUpper(s)
		if up == "MONTH" || up == "YEAR" || s == "الاجمالى" || s == "اجمالى كميات" || s == "الشهر" {
			continue
		}
		if strings.HasPrefix(s, "كمية") || strings.HasPrefix(s, "كميه") {
			continue
		}
		hasAr := false
		for _, r := range s {
			if r >= 0x0600 && r <= 0x06FF {
				hasAr = true
				break
			}
		}
		if !hasAr {
			continue
		}
		if seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}

func readSharedStrings(zr *zip.ReadCloser) ([]string, error) {
	var f *zip.File
	for _, zf := range zr.File {
		if zf.Name == "xl/sharedStrings.xml" {
			f = zf
			break
		}
	}
	if f == nil {
		return nil, nil
	}
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	type si struct {
		T string   `xml:"t"`
		R []struct {
			T string `xml:"t"`
		} `xml:"r"`
	}
	type sst struct {
		SI []si `xml:"si"`
	}
	var doc sst
	if err := xml.NewDecoder(rc).Decode(&doc); err != nil {
		return nil, err
	}
	out := make([]string, len(doc.SI))
	for i, s := range doc.SI {
		if s.T != "" {
			out[i] = s.T
			continue
		}
		var b strings.Builder
		for _, r := range s.R {
			b.WriteString(r.T)
		}
		out[i] = b.String()
	}
	return out, nil
}

func firstWorksheetPath(zr *zip.ReadCloser) (string, error) {
	// Prefer sheet named like sale out2026 via workbook.xml; fallback sheet1.
	type rel struct {
		ID     string `xml:"Id,attr"`
		Target string `xml:"Target,attr"`
		Type   string `xml:"Type,attr"`
	}
	// Map rId → target from workbook.xml.rels
	ridTarget := map[string]string{}
	for _, zf := range zr.File {
		if zf.Name != "xl/_rels/workbook.xml.rels" {
			continue
		}
		rc, err := zf.Open()
		if err != nil {
			return "", err
		}
		var root struct {
			Relationships []rel `xml:"Relationship"`
		}
		_ = xml.NewDecoder(rc).Decode(&root)
		rc.Close()
		for _, r := range root.Relationships {
			t := r.Target
			if !strings.HasPrefix(t, "/") && !strings.HasPrefix(t, "xl/") {
				t = "xl/" + strings.TrimPrefix(t, "/")
			}
			if strings.HasPrefix(t, "/") {
				t = strings.TrimPrefix(t, "/")
			}
			ridTarget[r.ID] = t
		}
	}
	type sheet struct {
		Name string `xml:"name,attr"`
		ID   string `xml:"id,attr"`
	}
	for _, zf := range zr.File {
		if zf.Name != "xl/workbook.xml" {
			continue
		}
		rc, err := zf.Open()
		if err != nil {
			return "", err
		}
		var wb struct {
			Sheets struct {
				Sheet []sheet `xml:"sheet"`
			} `xml:"sheets"`
		}
		_ = xml.NewDecoder(rc).Decode(&wb)
		rc.Close()
		// Prefer 2026 sheet name.
		var fallback string
		for _, s := range wb.Sheets.Sheet {
			target := ridTarget[s.ID]
			if target == "" {
				continue
			}
			if fallback == "" {
				fallback = target
			}
			low := strings.ToLower(s.Name)
			if strings.Contains(low, "2026") || strings.Contains(low, "out2026") {
				return target, nil
			}
		}
		if fallback != "" {
			return fallback, nil
		}
	}
	return "xl/worksheets/sheet1.xml", nil
}

func attr(t xml.StartElement, name string) string {
	for _, a := range t.Attr {
		if a.Name.Local == name {
			return a.Value
		}
	}
	return ""
}

func colIndex(ref string) int {
	// "E1" → 4
	n := 0
	for _, r := range ref {
		if r >= 'A' && r <= 'Z' {
			n = n*26 + int(r-'A'+1)
		} else {
			break
		}
	}
	if n == 0 {
		return 0
	}
	return n - 1
}
