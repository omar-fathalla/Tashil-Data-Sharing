package ingestion

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
	"github.com/tashil/data-sharing/backend/internal/service/bigquery"
	"github.com/tashil/data-sharing/backend/internal/service/customers"
	"github.com/tashil/data-sharing/backend/internal/service/gemini"
)

// UploadGuards carries the uploader's explicit answers. It is set only by the upload handlers, so
// archive replays (no guards) keep their old behaviour and never stop on a question.
type UploadGuards struct {
	ReplaceConfirmed bool   // "partial_month": the user confirmed replacing a bigger month with a smaller file
	PeriodChoice     string // "form" | "sheet" for "period_conflict"
}

type uploadGuardsKey struct{}

// WithUploadGuards marks ctx as an interactive upload.
func WithUploadGuards(ctx context.Context, g UploadGuards) context.Context {
	g.PeriodChoice = strings.ToLower(strings.TrimSpace(g.PeriodChoice))
	return context.WithValue(ctx, uploadGuardsKey{}, g)
}

func uploadGuards(ctx context.Context) (UploadGuards, bool) {
	if ctx == nil {
		return UploadGuards{}, false
	}
	g, ok := ctx.Value(uploadGuardsKey{}).(UploadGuards)
	return g, ok
}

// MonthSlice is one month of an upload.
type MonthSlice struct {
	Period string  `json:"period"` // YYYY-MM
	Rows   int     `json:"rows"`
	Value  float64 `json:"value"`
	Units  float64 `json:"units"`
	// Existing* are what is stored now for the same chain and month (partial-month check).
	ExistingRows  int     `json:"existing_rows,omitempty"`
	ExistingValue float64 `json:"existing_value,omitempty"`
}

// ConfirmOption is one button of a confirmation dialog.
type ConfirmOption struct {
	Value       string `json:"value"`
	LabelAR     string `json:"label_ar"`
	Recommended bool   `json:"recommended,omitempty"`
}

// ConfirmationRequiredError stops an upload before anything is written; the handler returns 409.
type ConfirmationRequiredError struct {
	Kind       string          `json:"kind"` // period_conflict | partial_month | chain_required
	MessageAR  string          `json:"message_ar"`
	Param      string          `json:"param"` // query/form parameter that carries the answer
	Options    []ConfirmOption `json:"options"`
	Breakdown  []MonthSlice    `json:"breakdown,omitempty"`
	FormPeriod string          `json:"form_period,omitempty"`
}

func (e *ConfirmationRequiredError) Error() string { return e.MessageAR }

// AsConfirmationRequired unwraps a confirmation request.
func AsConfirmationRequired(err error) (*ConfirmationRequiredError, bool) {
	var c *ConfirmationRequiredError
	if errors.As(err, &c) {
		return c, true
	}
	return nil, false
}

// UploadIssue is a non-blocking warning shown in the upload result.
type UploadIssue struct {
	Code      string   `json:"code"`
	Severity  string   `json:"severity"` // warning | info
	MessageAR string   `json:"message_ar"`
	Count     int      `json:"count,omitempty"`
	Value     float64  `json:"value,omitempty"`
	Samples   []string `json:"samples,omitempty"`
}

// UnknownBarcode is an item that is kept but has no Product Master match.
type UnknownBarcode struct {
	ItemCode string  `json:"item_code,omitempty"`
	Barcode  string  `json:"barcode,omitempty"`
	ItemName string  `json:"item_name"`
	Rows     int     `json:"rows"`
	Value    float64 `json:"value"`
}

// Partial-month thresholds: an upload for a (chain, month) that already holds data needs an explicit
// confirmation when it brings less than half of the stored rows or value. Months with fewer than
// minExistingRows stored rows are too small to judge.
const (
	partialMonthRatio = 0.5
	minExistingRows   = 20
)

func r2(f float64) float64 { return math.Round(f*100) / 100 }

func periodKey(y, m int) string { return fmt.Sprintf("%04d-%02d", y, m) }

func sellInBreakdown(records []domain.SellInRecord) []MonthSlice {
	m := map[string]*MonthSlice{}
	for _, r := range records {
		k := periodKey(r.Year, r.MonthNum)
		s := m[k]
		if s == nil {
			s = &MonthSlice{Period: k}
			m[k] = s
		}
		s.Rows++
		s.Value += r.NetValueEGP
		s.Units += r.NetQtyCases
	}
	out := make([]MonthSlice, 0, len(m))
	for _, s := range m {
		s.Value, s.Units = r2(s.Value), r2(s.Units)
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Period < out[j].Period })
	return out
}

func arabicPeriod(p string) string {
	var y, m int
	if _, err := fmt.Sscanf(p, "%d-%d", &y, &m); err == nil && m >= 1 && m <= 12 {
		return fmt.Sprintf("%s %d", gemini.ArabicMonthName(m), y)
	}
	return p
}

func periodConflictError(formPeriod string, breakdown []MonthSlice) *ConfirmationRequiredError {
	var months []string
	for _, b := range breakdown {
		months = append(months, arabicPeriod(b.Period))
	}
	return &ConfirmationRequiredError{
		Kind: "period_conflict",
		MessageAR: fmt.Sprintf("الفترة اللي اخترتها في الفورم (%s) مختلفة عن شهور الصفوف في الملف (%s). مفيش حاجة اتحفظت. اختار تستخدم أنهي فترة.",
			arabicPeriod(formPeriod), strings.Join(months, "، ")),
		Param: "period_choice",
		Options: []ConfirmOption{
			{Value: "sheet", LabelAR: "استخدم شهور الملف (موصى بيه)", Recommended: true},
			{Value: "form", LabelAR: "استخدم فترة الفورم لكل الصفوف"},
		},
		Breakdown:  breakdown,
		FormPeriod: formPeriod,
	}
}

// resolveSellInPeriod applies the form period vs sheet months rule. Returns an error when the user
// must choose. Non-interactive calls keep the old behaviour (form period only for single-month files).
func resolveSellInPeriod(ctx context.Context, records []domain.SellInRecord) error {
	req := gemini.GetRequestedPeriodDate(ctx)
	var reqYear, reqMonth int
	if len(req) >= 7 {
		fmt.Sscanf(req[:7], "%d-%d", &reqYear, &reqMonth)
	}
	if reqYear < 2000 || reqMonth < 1 || reqMonth > 12 {
		return nil
	}
	form := periodKey(reqYear, reqMonth)
	bd := sellInBreakdown(records)
	g, interactive := uploadGuards(ctx)
	applyForm := false
	switch {
	case !interactive:
		applyForm = len(bd) <= 1
	case len(bd) == 0, len(bd) == 1 && bd[0].Period == form:
		return nil
	case g.PeriodChoice == "form":
		applyForm = true
	case g.PeriodChoice == "sheet":
		return nil
	default:
		return periodConflictError(form, bd)
	}
	if applyForm {
		for i := range records {
			records[i].Year, records[i].MonthNum = reqYear, reqMonth
			records[i].MonthEN = gemini.MonthNumToEN(reqMonth)
			records[i].MonthAR = gemini.ArabicMonthName(reqMonth)
		}
	}
	return nil
}

type sellInSnapshotter interface {
	SellInRecordsSnapshot(tenantID string) []domain.SellInRecord
}

func storedChain(r domain.SellInRecord) string {
	ch := strings.ToLower(strings.TrimSpace(bigquery.ResolveSellInChain(r.CustomerName, r.RetailerChain)))
	if ch == "" {
		ch = "fathalla"
	}
	return ch
}

// checkSellInPartialMonth compares the incoming months with what SetSellInRecords would replace.
func (p *Processor) checkSellInPartialMonth(ctx context.Context, tenantID, filename string, records []domain.SellInRecord) error {
	g, interactive := uploadGuards(ctx)
	if !interactive || g.ReplaceConfirmed {
		return nil
	}
	snap, ok := p.bqRepo.(sellInSnapshotter)
	if !ok {
		return nil
	}
	type agg struct {
		rows  int
		value float64
		units float64
	}
	incoming := map[string]*agg{}
	chains := map[string]bool{}
	for _, r := range records {
		ch := storedChain(r)
		chains[ch] = true
		k := ch + "|" + periodKey(r.Year, r.MonthNum)
		if incoming[k] == nil {
			incoming[k] = &agg{}
		}
		incoming[k].rows++
		incoming[k].value += r.NetValueEGP
		incoming[k].units += r.NetQtyCases
	}
	existing := map[string]*agg{}
	dropped := map[string]*agg{}
	for _, r := range snap.SellInRecordsSnapshot(tenantID) {
		ch := strings.ToLower(strings.TrimSpace(r.RetailerChain))
		if ch == "" {
			ch = "fathalla"
		}
		k := ch + "|" + periodKey(r.Year, r.MonthNum)
		target := existing
		if incoming[k] == nil {
			// Same file re-uploaded without this month: the month would disappear.
			if !(strings.EqualFold(strings.TrimSpace(r.SourceFilename), strings.TrimSpace(filename)) && chains[ch]) {
				continue
			}
			target = dropped
		}
		if target[k] == nil {
			target[k] = &agg{}
		}
		target[k].rows++
		target[k].value += r.NetValueEGP
	}
	var bd []MonthSlice
	for k, ex := range existing {
		in := incoming[k]
		if ex.rows < minExistingRows {
			continue
		}
		if float64(in.rows) < partialMonthRatio*float64(ex.rows) || math.Abs(in.value) < partialMonthRatio*math.Abs(ex.value) {
			bd = append(bd, MonthSlice{Period: k, Rows: in.rows, Value: r2(in.value), Units: r2(in.units), ExistingRows: ex.rows, ExistingValue: r2(ex.value)})
		}
	}
	for k, ex := range dropped {
		bd = append(bd, MonthSlice{Period: k, ExistingRows: ex.rows, ExistingValue: r2(ex.value)})
	}
	if len(bd) == 0 {
		return nil
	}
	sort.Slice(bd, func(i, j int) bool { return bd[i].Period < bd[j].Period })
	var parts []string
	for _, b := range bd {
		ch, per, _ := strings.Cut(b.Period, "|")
		if b.Rows == 0 {
			parts = append(parts, fmt.Sprintf("%s (%s): الشهر هيتشال كله (%d صف، %.0f جنيه)", arabicPeriod(per), getChainDisplayName(ch), b.ExistingRows, b.ExistingValue))
		} else {
			parts = append(parts, fmt.Sprintf("%s (%s): %d صف و%.0f جنيه بدل %d صف و%.0f جنيه", arabicPeriod(per), getChainDisplayName(ch), b.Rows, b.Value, b.ExistingRows, b.ExistingValue))
		}
	}
	return &ConfirmationRequiredError{
		Kind:      "partial_month",
		MessageAR: "الملف ده أصغر بكتير من البيانات المحفوظة لنفس الشهر، وممكن يكون شهر ناقص. لو كملت، البيانات القديمة للشهر هتتبدل بالملف ده. مفيش حاجة اتحفظت لسه: " + strings.Join(parts, "؛ "),
		Param:     "replace_confirmed",
		Options: []ConfirmOption{
			{Value: "true", LabelAR: "أيوه، استبدل الشهر بالملف ده"},
			{Value: "", LabelAR: "لا، إلغاء"},
		},
		Breakdown: bd,
	}
}

// quarantineSellIn applies the customer registry (TOP RULE: exact approved names only).
func (p *Processor) quarantineSellIn(ctx context.Context, tenantID, filename, chain string, records []domain.SellInRecord, persist bool) ([]domain.SellInRecord, []customers.QuarantinedCustomer, *UploadIssue) {
	if p.customers == nil {
		return records, nil, nil
	}
	kept, held := p.customers.Partition(ctx, tenantID, filename, chain, records, persist)
	if len(held) == 0 {
		return kept, nil, nil
	}
	rows, value := 0, 0.0
	var names []string
	for _, h := range held {
		rows += h.Rows
		value += h.Value
		if len(names) < 10 {
			names = append(names, h.Name)
		}
	}
	return kept, held, &UploadIssue{
		Code:     "unknown_customers",
		Severity: "warning",
		MessageAR: fmt.Sprintf("فيه %d عميل مش متسجل (%d صف، %.0f جنيه). الصفوف دي اتحجزت ومش داخلة في أي إجمالي لحد ما تأكد العميل من شاشة «عملاء في انتظار التأكيد». مفيش عميل اتنسب لعميل تاني.",
			len(held), rows, value),
		Count:   rows,
		Value:   r2(value),
		Samples: names,
	}
}

// unknownBarcodes lists kept rows without a Product Master match (records must already be enriched).
func unknownBarcodes(records []domain.SellInRecord) ([]UnknownBarcode, *UploadIssue) {
	m := map[string]*UnknownBarcode{}
	rows := 0
	for _, r := range records {
		if r.PricingWaveStatus != "unmatched" {
			continue
		}
		rows++
		code := r.ItemCode
		if code == "" {
			code = r.ItemGroup
		}
		k := code + "|" + r.Barcode + "|" + r.ItemName
		u := m[k]
		if u == nil {
			u = &UnknownBarcode{ItemCode: code, Barcode: r.Barcode, ItemName: r.ItemName}
			m[k] = u
		}
		u.Rows++
		u.Value += r.NetValueEGP
	}
	if len(m) == 0 {
		return nil, nil
	}
	out := make([]UnknownBarcode, 0, len(m))
	value := 0.0
	for _, u := range m {
		u.Value = r2(u.Value)
		value += u.Value
		out = append(out, *u)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Value > out[j].Value })
	var samples []string
	for i := 0; i < len(out) && i < 10; i++ {
		samples = append(samples, strings.TrimSpace(out[i].ItemCode+" "+out[i].ItemName))
	}
	return out, &UploadIssue{
		Code:      "unknown_barcodes",
		Severity:  "warning",
		MessageAR: fmt.Sprintf("%d صنف (%d صف، %.0f جنيه) مش موجود في كارتة الأصناف. الصفوف اتحفظت وداخلة في الإجماليات، لكن من غير سعر رسمي. راجعهم في صفحة جودة البيانات.", len(out), rows, value),
		Count:     rows,
		Value:     r2(value),
		Samples:   samples,
	}
}

// formulaGuard rejects a workbook whose formula cells have no saved value.
func formulaGuard(ctx context.Context, filename string, raw []byte) error {
	if _, interactive := uploadGuards(ctx); !interactive {
		return nil
	}
	rep := gemini.FindUncachedFormulaCells(raw)
	if rep.Count == 0 {
		return nil
	}
	return fmt.Errorf("%s: %s", filename, gemini.UncachedFormulaMessageAR(rep))
}

// sellOutSheetMonths breaks down the rows whose date came from the workbook itself.
func sellOutSheetMonths(recs []domain.NormalizedRecord) []MonthSlice {
	m := map[string]*MonthSlice{}
	for _, r := range recs {
		if !r.DateFromFile {
			continue
		}
		y, mo, ok := gemini.ParseDateToken(r.TransactionDate)
		if !ok {
			continue
		}
		k := periodKey(y, mo)
		s := m[k]
		if s == nil {
			s = &MonthSlice{Period: k}
			m[k] = s
		}
		s.Rows++
		s.Value += r.NetRevenue
		s.Units += float64(r.QuantitySold)
	}
	out := make([]MonthSlice, 0, len(m))
	for _, s := range m {
		s.Value, s.Units = r2(s.Value), r2(s.Units)
		out = append(out, *s)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Period < out[j].Period })
	return out
}

// sellOutPeriodChoice decides between the form period and the sheet's own months:
//   - no form period, or no per-row dates in the sheet → "" (form period, when given, applies as before)
//   - sheet months equal to the form month → "" (no conflict)
//   - otherwise an interactive upload must answer period_choice=form|sheet; replays keep the old rule.
func sellOutPeriodChoice(ctx context.Context, requested string, sheet []MonthSlice) (string, error) {
	g, interactive := uploadGuards(ctx)
	if !interactive || len(sheet) == 0 || len(requested) < 7 {
		return "", nil
	}
	y, m, ok := gemini.ParseDateToken(requested)
	if !ok {
		return "", nil
	}
	form := periodKey(y, m)
	if len(sheet) == 1 && sheet[0].Period == form {
		return "", nil
	}
	switch g.PeriodChoice {
	case "form", "sheet":
		return g.PeriodChoice, nil
	}
	return "", periodConflictError(form, sheet)
}

// chainRequiredError: TOP RULE — the AI-detected chain is only a suggestion, never applied by itself.
func chainRequiredError(suggested string) *ConfirmationRequiredError {
	msg := "اختار السلسلة اللي الملف ده تبعها قبل الرفع. مفيش حاجة اتحفظت."
	var opts []ConfirmOption
	if suggested != "" {
		msg = fmt.Sprintf("الملف شكله تبع «%s» (اقتراح بس). اختار السلسلة بنفسك قبل الرفع. مفيش حاجة اتحفظت.", getChainDisplayName(suggested))
		opts = append(opts, ConfirmOption{Value: suggested, LabelAR: getChainDisplayName(suggested)})
	}
	return &ConfirmationRequiredError{Kind: "chain_required", MessageAR: msg, Param: "chain", Options: opts}
}

// PrecheckSellIn runs the blocking Sell-In checks without writing anything, so a caller can stop
// before destructive steps (e.g. replacing an archived file).
func (p *Processor) PrecheckSellIn(ctx context.Context, tenantID, filename string, raw []byte, chain string) error {
	if err := formulaGuard(ctx, filename, raw); err != nil {
		return err
	}
	recs, _, err := gemini.ParseSellInPlanWorkbookWithReport(tenantID, filename, raw, chain)
	var layoutErr *gemini.SellInLayoutError
	var periodErr *gemini.SellInPeriodError
	if errors.As(err, &layoutErr) || errors.As(err, &periodErr) {
		return err
	}
	if err != nil || len(recs) == 0 {
		return nil // unknown layout: the full path decides (AI mapping, then strict checks)
	}
	if err := resolveSellInPeriod(ctx, recs); err != nil {
		return err
	}
	return p.checkSellInPartialMonth(ctx, tenantID, filename, recs)
}
