package sellinassist

import (
	"fmt"
	"strings"
)

// Sell-In column roles Gemini (or heuristics) may assign.
const (
	roleCustomer = "customer"
	roleItemCode = "item_code"
	roleItemName = "item_name"
	roleQty      = "qty"
	roleValue    = "value"
	roleNetQ     = "net_q"
	roleNetV     = "net_v"
	roleDate     = "date"
	roleMonth    = "month"
	roleYear     = "year"
	roleBarcode  = "barcode"
	roleBranch   = "branch"
	roleChain    = "chain"
	roleIgnore   = "ignore"
)

// roleMatchOrder is deterministic precedence for header→role matching.
// More specific aliases (Net V, barcode) must win over broader ones (value, item_code).
// Never iterate a Go map for matching — map order is non-deterministic.
var roleMatchOrder = []struct {
	role    string
	aliases []string
}{
	{roleNetV, []string{"net v", "net value", "to", "t.o", "صافي القيمه", "صافي القيمة"}},
	{roleNetQ, []string{"net q", "net qty", "صافي الكميه", "صافي الكمية"}},
	{roleBarcode, []string{"barcode", "الباركود", "gtin"}},
	{roleCustomer, []string{"customer name", "customer", "اسم العميل", "العميل"}},
	{roleItemCode, []string{"item number", "item code", "كود الصنف"}},
	{roleItemName, []string{"item description", "item name", "اسم الصنف", "item 1"}},
	{roleQty, []string{"qty", "quantity", "الكميه", "الكمية"}},
	{roleValue, []string{"extended price", "ext price", "to", "t.o", "turnover", "قيمه الفاتوره", "قيمة الفاتورة"}},
	{roleDate, []string{"document date", "doc date", "invoice date", "تاريخ المستند", "تاريخ الفاتوره", "date"}},
	{roleMonth, []string{"month", "الشهر", "شهر"}},
	{roleYear, []string{"year", "السنه", "السنة"}},
	{roleBranch, []string{"branch", "الفرع", "store"}},
	{roleChain, []string{"chain", "retailer", "السلسله", "السلسلة"}},
}

var allowedLayouts = map[string]bool{
	"gp_sop": true, "raw_plan": true, "guided": true, "long": true, "unknown": true,
}

var allowedRoles = map[string]bool{
	roleCustomer: true, roleItemCode: true, roleItemName: true, roleQty: true,
	roleValue: true, roleNetQ: true, roleNetV: true, roleDate: true, roleMonth: true,
	roleYear: true, roleBarcode: true, roleBranch: true, roleChain: true, roleIgnore: true,
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

// matchRole returns the first role in roleMatchOrder whose alias matches.
func matchRole(norm string) string {
	for _, entry := range roleMatchOrder {
		for _, a := range entry.aliases {
			an := normalizeHeaderLabel(a)
			if an == "" {
				continue
			}
			if norm == an || strings.Contains(norm, an) {
				return entry.role
			}
		}
	}
	return roleIgnore
}

// validateLayoutAI rejects malformed / out-of-range Gemini layout payloads before accept.
func validateLayoutAI(ai *layoutAIResponse, sampleRows int) error {
	if ai == nil {
		return fmt.Errorf("empty layout response")
	}
	if ai.Confidence < minLayoutAIConf || ai.Confidence > 1 {
		return fmt.Errorf("confidence out of range: %v", ai.Confidence)
	}
	if !allowedLayouts[ai.Layout] {
		return fmt.Errorf("unknown layout %q", ai.Layout)
	}
	if ai.HeaderRowIndex < 0 || (sampleRows > 0 && ai.HeaderRowIndex >= sampleRows) {
		return fmt.Errorf("header_row_index %d out of range", ai.HeaderRowIndex)
	}
	if len(ai.Columns) == 0 {
		return fmt.Errorf("columns empty")
	}
	seen := map[int]bool{}
	for _, c := range ai.Columns {
		if c.Index < 0 {
			return fmt.Errorf("negative column index")
		}
		if seen[c.Index] {
			return fmt.Errorf("duplicate column index %d", c.Index)
		}
		seen[c.Index] = true
		if !allowedRoles[c.Role] {
			return fmt.Errorf("unknown role %q", c.Role)
		}
	}
	if strings.TrimSpace(ai.ReasonAR) == "" {
		return fmt.Errorf("reason_ar required")
	}
	return nil
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
