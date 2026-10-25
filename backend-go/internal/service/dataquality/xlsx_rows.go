package dataquality

import (
	"archive/zip"
	"bytes"
	"encoding/csv"
	"encoding/xml"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// sheetRow is one worksheet row with its real Excel row number. Cells are indexed by column
// (A=0); error cells (t="e", e.g. #N/A) keep their error text.
type sheetRow struct {
	Num   int
	Cells []string
	Err   map[int]bool // column index -> cell is an Excel error value
}

type xSI struct {
	T string `xml:"t"`
	R []struct {
		T string `xml:"t"`
	} `xml:"r"`
}

type xSST struct {
	SI []xSI `xml:"si"`
}

type xCell struct {
	R  string `xml:"r,attr"`
	T  string `xml:"t,attr"`
	V  string `xml:"v"`
	IS *xSI   `xml:"is"`
}

type xRow struct {
	R int     `xml:"r,attr"`
	C []xCell `xml:"c"`
}

func siText(s xSI) string {
	if len(s.R) == 0 {
		return s.T
	}
	var b strings.Builder
	b.WriteString(s.T)
	for _, r := range s.R {
		b.WriteString(r.T)
	}
	return b.String()
}

func colIndex(ref string) int {
	n := 0
	for _, ch := range ref {
		if ch >= 'A' && ch <= 'Z' {
			n = n*26 + int(ch-'A'+1)
		} else if ch >= 'a' && ch <= 'z' {
			n = n*26 + int(ch-'a'+1)
		} else {
			break
		}
	}
	return n - 1
}

// readFirstSheet returns the first worksheet's rows (same sheet the Product Master parser reads)
// with Excel row numbers, plus the sheet name. CSV input is numbered from row 1.
func readFirstSheet(raw []byte) (string, []sheetRow, error) {
	if len(raw) < 4 || !bytes.HasPrefix(raw, []byte("PK")) {
		rd := csv.NewReader(bytes.NewReader(raw))
		rd.FieldsPerRecord = -1
		recs, err := rd.ReadAll()
		if err != nil {
			return "", nil, fmt.Errorf("read csv: %w", err)
		}
		out := make([]sheetRow, 0, len(recs))
		for i, r := range recs {
			out = append(out, sheetRow{Num: i + 1, Cells: r})
		}
		return "CSV", out, nil
	}
	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return "", nil, err
	}
	var shared []string
	var sheet *zip.File
	sheetName := ""
	for _, f := range zr.File {
		switch strings.ToLower(f.Name) {
		case "xl/sharedstrings.xml":
			b, err := readZip(f)
			if err != nil {
				return "", nil, err
			}
			var sst xSST
			if err := xml.Unmarshal(b, &sst); err != nil {
				return "", nil, fmt.Errorf("shared strings: %w", err)
			}
			for _, s := range sst.SI {
				shared = append(shared, siText(s))
			}
		case "xl/worksheets/sheet1.xml":
			sheet = f
		case "xl/workbook.xml":
			b, _ := readZip(f)
			var wb struct {
				Sheets []struct {
					Name string `xml:"name,attr"`
				} `xml:"sheets>sheet"`
			}
			if xml.Unmarshal(b, &wb) == nil && len(wb.Sheets) > 0 {
				sheetName = strings.TrimSpace(wb.Sheets[0].Name)
			}
		}
	}
	if sheet == nil {
		return "", nil, fmt.Errorf("no sheet1.xml found")
	}
	rc, err := sheet.Open()
	if err != nil {
		return "", nil, err
	}
	defer rc.Close()
	dec := xml.NewDecoder(rc)
	var rows []sheetRow
	next := 1
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", nil, fmt.Errorf("worksheet xml: %w", err)
		}
		se, ok := tok.(xml.StartElement)
		if !ok || se.Name.Local != "row" {
			continue
		}
		var xr xRow
		if err := dec.DecodeElement(&xr, &se); err != nil {
			return "", nil, err
		}
		if xr.R <= 0 {
			xr.R = next
		}
		next = xr.R + 1
		sr := sheetRow{Num: xr.R}
		pos := 0
		for _, c := range xr.C {
			idx := pos
			if c.R != "" {
				idx = colIndex(c.R)
			}
			pos = idx + 1
			val := c.V
			switch c.T {
			case "s":
				if i, err := strconv.Atoi(strings.TrimSpace(c.V)); err == nil && i >= 0 && i < len(shared) {
					val = shared[i]
				}
			case "inlineStr":
				if c.IS != nil {
					val = siText(*c.IS)
				}
			case "e":
				if sr.Err == nil {
					sr.Err = map[int]bool{}
				}
				sr.Err[idx] = true
			}
			for len(sr.Cells) <= idx {
				sr.Cells = append(sr.Cells, "")
			}
			sr.Cells[idx] = val
		}
		rows = append(rows, sr)
	}
	return sheetName, rows, nil
}

func readZip(f *zip.File) ([]byte, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	return io.ReadAll(rc)
}
