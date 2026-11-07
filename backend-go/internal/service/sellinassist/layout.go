package sellinassist

import (
	"fmt"
	"strings"
)

// Sell-In column roles Gemini (or heuristics) may assign.
const (
	roleCustomer   = "customer"
	roleItemCode   = "item_code"
	roleItemName   = "item_name"
	roleQty        = "qty"
	roleValue      = "value"
	roleNetQ       = "net_q"
	roleNetV       = "net_v"
	roleDate       = "date"
	roleMonth      = "month"
	roleYear       = "year"
	roleBarcode    = "barcode"
	roleBranch     = "branch"
	roleChain      = "chain"
	roleIgnore     = "ignore"
)

var roleAliases = map[string][]string{
	roleCustomer: {"customer name", "customer", "اسم العميل", "العميل"},
	roleItemCode: {"item number", "item code", "كود الصنف", "barcode", "الباركود"},
	roleItemName: {"item description", "item name", "اسم الصنف", "item 1"},
	roleQty:      {"qty", "quantity", "الكميه", "الكمية"},
	roleValue:    {"extended price", "ext price", "قيمه الفاتوره", "قيمة الفاتورة", "net v", "net value", "صافي القيمه"},
	roleNetQ:     {"net q", "net qty", "صافي الكميه", "صافي الكمية"},
	roleNetV:     {"net v", "to", "t.o", "صافي القيمه"},
	roleDate:     {"document date", "doc date", "invoice date", "تاريخ المستند", "تاريخ الفاتوره", "date"},
	roleMonth:    {"month", "الشهر", "شهر"},
	roleYear:     {"year", "السنه", "السنة"},
	roleBarcode:  {"barcode", "الباركود", "gtin"},
	roleBranch:   {"branch", "الفرع", "store"},
	roleChain:    {"chain", "retailer", "السلسله", "السلسلة"},
}

type layoutGuess struct {
	Layout         string
	HeaderRowIndex int
	Columns        []ColumnRole
	Missing        []string
	Confidence     float64
	ReasonAR       string
}

func guessLayoutFromSample(filename string, rows [][]string) *layoutGuess {
	if len(rows) == 0 {
		return nil
	}
	bestHdr, bestScore := 0, -1
	var bestCols []ColumnRole
	var bestMissing []string
	var bestLayout string
	limit := len(rows)
	if limit > 12 {
		limit = 12
	}
	for i := 0; i < limit; i++ {
		cols, missing, layout, score := scoreHeaderRow(rows[i])
		if score > bestScore {
			bestScore, bestHdr, bestCols, bestMissing, bestLayout = score, i, cols, missing, layout
		}
	}
	if bestScore < 2 {
		return &layoutGuess{
			Layout:         "unknown",
			HeaderRowIndex: 0,
			Confidence:     0.2,
			Missing:        []string{roleCustomer, roleQty, roleValue},
			ReasonAR:       fmt.Sprintf("ملف %s: مش قادرين نحدد صف العناوين بوضوح — محتاج مراجعة يدوية أو مساعدة Gemini", filename),
		}
	}
	conf := 0.55 + 0.08*float64(bestScore)
	if conf > 0.95 {
		conf = 0.95
	}
	reason := fmt.Sprintf("شكل مقترح «%s» — صف العناوين رقم %d. الاقتراح للتأكيد فقط ومش بيتطبق لوحده.", bestLayout, bestHdr+1)
	if len(bestMissing) > 0 {
		reason += " أعمدة ناقصة محتملة: " + strings.Join(bestMissing, "، ")
	}
	return &layoutGuess{
		Layout:         bestLayout,
		HeaderRowIndex: bestHdr,
		Columns:        bestCols,
		Missing:        bestMissing,
		Confidence:     conf,
		ReasonAR:       reason,
	}
}

func scoreHeaderRow(row []string) (cols []ColumnRole, missing []string, layout string, score int) {
	joined := normalizeHeaderLabel(strings.Join(row, " | "))
	found := map[string]int{}
	for i, cell := range row {
		label := strings.TrimSpace(cell)
		norm := normalizeHeaderLabel(label)
		if norm == "" {
			continue
		}
		role := matchRole(norm)
		if role == "" || role == roleIgnore {
			continue
		}
		if _, ok := found[role]; ok {
			continue
		}
		found[role] = i
		cols = append(cols, ColumnRole{Index: i, Role: role, Label: label})
		score++
	}
	required := []string{roleCustomer, roleQty, roleValue}
	layout = "long"
	if containsAny(joined, "sop number", "document date", "extended price") {
		layout = "gp_sop"
		required = []string{roleCustomer, roleItemCode, roleQty, roleValue, roleDate}
	} else if containsAny(joined, "sell in cases", "net_qty_cases", "expected_cases", "صافي الكمية الفعلية") {
		layout = "guided"
		required = []string{roleCustomer, roleQty, roleValue}
	} else if containsAny(joined, "net q", "net v", "item 1", "officer") {
		layout = "raw_plan"
		required = []string{roleCustomer, roleNetQ, roleNetV, roleMonth}
	}
	for _, r := range required {
		if okRole(found, r) {
			continue
		}
		// qty/value aliases: net_q can satisfy qty for raw_plan
		if r == roleQty && okRole(found, roleNetQ) {
			continue
		}
		if r == roleValue && okRole(found, roleNetV) {
			continue
		}
		if r == roleItemCode && okRole(found, roleBarcode) {
			continue
		}
		missing = append(missing, r)
	}
	score -= len(missing)
	return cols, missing, layout, score
}

func okRole(found map[string]int, role string) bool {
	_, ok := found[role]
	return ok
}

func matchRole(norm string) string {
	for role, aliases := range roleAliases {
		for _, a := range aliases {
			if normalizeHeaderLabel(a) == norm || strings.Contains(norm, normalizeHeaderLabel(a)) {
				return role
			}
		}
	}
	return roleIgnore
}

const sellInLayoutSchemaJSON = `{"type":"OBJECT","properties":{
"header_row_index":{"type":"INTEGER"},
"layout":{"type":"STRING","enum":["gp_sop","raw_plan","guided","long","unknown"]},
"confidence":{"type":"NUMBER"},
"reason_ar":{"type":"STRING"},
"missing_roles":{"type":"ARRAY","items":{"type":"STRING"}},
"columns":{"type":"ARRAY","items":{"type":"OBJECT","properties":{
"index":{"type":"INTEGER"},
"role":{"type":"STRING","enum":["customer","item_code","item_name","qty","value","net_q","net_v","date","month","year","barcode","branch","chain","ignore"]},
"label":{"type":"STRING"}},"required":["index","role"]}}},
"required":["header_row_index","layout","columns","confidence","reason_ar"]}`

func buildSellInLayoutPrompt(filename string, sample [][]string) string {
	var b strings.Builder
	b.WriteString(`You map columns of an Egyptian retail Sell-In / supplier invoice spreadsheet.
Return JSON only. Rows and columns are 0-based.
- header_row_index: row with column headers.
- layout: gp_sop (Dynamics SOP invoice), raw_plan (Net Q / Net V plan), guided (template), long, or unknown.
- columns: role per useful column. Roles: customer, item_code, item_name, qty, value, net_q, net_v, date, month, year, barcode, branch, chain, ignore.
- missing_roles: required roles not found.
- confidence: 0..1.
- reason_ar: short Arabic explanation for a human reviewer (suggestion only; never auto-applied).
File: ` + filename + "\nRows:\n")
	for i, r := range sample {
		cells := make([]string, len(r))
		for j, c := range r {
			c = strings.TrimSpace(c)
			if len([]rune(c)) > 40 {
				c = string([]rune(c)[:40])
			}
			cells[j] = fmt.Sprintf("%d:%s", j, c)
		}
		fmt.Fprintf(&b, "row %d | %s\n", i, strings.Join(cells, " | "))
	}
	return b.String()
}
