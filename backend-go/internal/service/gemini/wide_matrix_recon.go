package gemini

import (
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/tashil/data-sharing/backend/internal/domain"
)

// UnallocatedBranchName is the synthetic branch used when الاجمالى differs from the
// sum of per-branch value columns. Permanent wide-format Sell-Out rule (any supplier/month).
const UnallocatedBranchName = "غير موزع على فرع"

const (
	anomalyValueTotalGap     = "value_total_gap"
	anomalyQtyTotalMismatch  = "qty_total_mismatch"
	diffReasonUnallocated    = "unallocated_branch"
	diffReasonQtyMismatch    = "qty_column_mismatch"
	valueGapEpsilon          = 0.009
)

type wideBranchObservation struct {
	branch    branchColumnPair
	rev       float64
	qty       int
	unitPrice float64
}

type wideRowRecon struct {
	fileValue       float64
	branchValueSum  float64
	valueGap        float64 // fileValue - branchValueSum (signed); non-zero → unallocated row
	fileQty         int
	branchQtySum    int
	qtyMismatch     bool
	hasFileValueCol bool
	hasFileQtyCol   bool
}

type monthReconAgg struct {
	monthKey            string
	valueGapAbs         float64
	valueGapSigned      float64
	valueGapRows        int
	unallocatedValue    float64
	qtyMismatchRows     int
	qtyFileSum          int
	qtyBranchSum        int
}

func isTotalQuantityHeader(h string) bool {
	clean := strings.TrimSpace(h)
	if clean == "" {
		return false
	}
	lower := strings.ToLower(clean)
	hasTotal := strings.Contains(clean, "اجمال") || strings.Contains(clean, "إجمال") ||
		strings.Contains(clean, "الاجمال") || strings.Contains(clean, "الإجمال") ||
		strings.EqualFold(clean, "Total Qty") || strings.EqualFold(clean, "Total Quantity") ||
		strings.Contains(lower, "total qty") || strings.Contains(lower, "total quantity")
	hasQty := strings.Contains(clean, "كمي") || strings.Contains(lower, "qty") || strings.Contains(lower, "quantity")
	return hasTotal && hasQty
}

func isUnallocatedBranchName(name string) bool {
	return normalizeBranchKey(name) == normalizeBranchKey(UnallocatedBranchName)
}

func unallocatedBranchPair(retailer string) branchColumnPair {
	meta := BuildBranchStoreMetadata(retailer, UnallocatedBranchName)
	return branchColumnPair{
		rawBranchName: UnallocatedBranchName,
		storeID:       meta.ID,
		displayName:   meta.BranchName,
		revColIdx:     -1,
		qtyColIdx:     -1,
	}
}

// collectWideRowBranchObservations reads per-branch value/qty cells, then applies the
// permanent reconciliation rule: any الاجمالى − Σ(branch values) remainder becomes
// branch غير موزع على فرع (positive or negative). Per-branch qty columns stay truth;
// mismatch vs اجمالى كميات is only flagged.
func collectWideRowBranchObservations(
	row []string,
	layout wideMatrixLayout,
	retailer string,
	anomalies *[]domain.IngestionAnomaly,
	rowNumber int,
	skuName string,
) (active []wideBranchObservation, zeroBranches []branchColumnPair, recon wideRowRecon) {
	recon.hasFileValueCol = layout.totalRevIdx >= 0
	recon.hasFileQtyCol = layout.totalQtyIdx >= 0
	if recon.hasFileValueCol {
		recon.fileValue = parseRevenueFloat(getCell(row, layout.totalRevIdx))
	}
	if recon.hasFileQtyCol {
		recon.fileQty = parseQuantityInt(getCell(row, layout.totalQtyIdx))
	}

	for _, b := range layout.branches {
		bRev := parseRevenueFloat(getCell(row, b.revColIdx))
		bQty := parseQuantityInt(getCell(row, b.qtyColIdx))

		// Keep negative branch cells in the sum (returns); skipping them would invent a false
		// غير موزع على فرع remainder vs الاجمالى. Still surface a warning.
		if (bRev < 0 || bQty < 0) && anomalies != nil {
			*anomalies = append(*anomalies, domain.IngestionAnomaly{
				RowNumber:   rowNumber,
				IssueType:   "negative_sales",
				Description: fmt.Sprintf("قيمة أو كمية سالبة في فرع %s للصنف %s", b.rawBranchName, skuName),
			})
		}

		if bRev == 0 && bQty == 0 {
			zeroBranches = append(zeroBranches, b)
			continue
		}

		// Value-only positive cell with no qty → count as 1 unit for unit-price inference.
		// Do not invent qty for negative returns (qty stays as parsed, often 0 or negative).
		if bQty == 0 && bRev > 0 {
			bQty = 1
		}
		uPrice := 0.0
		if bQty != 0 && bRev != 0 {
			uPrice = math.Round((bRev/float64(bQty))*100) / 100
		}

		recon.branchValueSum += bRev
		recon.branchQtySum += bQty
		active = append(active, wideBranchObservation{
			branch:    b,
			rev:       bRev,
			qty:       bQty,
			unitPrice: uPrice,
		})
	}

	recon.branchValueSum = math.Round(recon.branchValueSum*100) / 100
	if recon.hasFileValueCol {
		recon.valueGap = math.Round((recon.fileValue-recon.branchValueSum)*100) / 100
		if math.Abs(recon.valueGap) > valueGapEpsilon {
			ub := unallocatedBranchPair(retailer)
			active = append(active, wideBranchObservation{
				branch:    ub,
				rev:       recon.valueGap,
				qty:       0,
				unitPrice: 0,
			})
		} else {
			recon.valueGap = 0
		}
	}

	if recon.hasFileQtyCol && recon.fileQty != recon.branchQtySum {
		recon.qtyMismatch = true
	}
	return active, zeroBranches, recon
}

func rowTotalsFromObservations(obs []wideBranchObservation) (rev float64, qty int) {
	for _, o := range obs {
		rev += o.rev
		qty += o.qty
	}
	return math.Round(rev*100) / 100, qty
}

func accumulateMonthRecon(byMonth map[string]*monthReconAgg, monthKey string, recon wideRowRecon) {
	if monthKey == "" {
		monthKey = "unknown"
	}
	agg, ok := byMonth[monthKey]
	if !ok {
		agg = &monthReconAgg{monthKey: monthKey}
		byMonth[monthKey] = agg
	}
	if math.Abs(recon.valueGap) > valueGapEpsilon {
		agg.valueGapRows++
		agg.valueGapSigned += recon.valueGap
		agg.valueGapAbs += math.Abs(recon.valueGap)
		agg.unallocatedValue += recon.valueGap
	}
	if recon.qtyMismatch {
		agg.qtyMismatchRows++
		agg.qtyFileSum += recon.fileQty
		agg.qtyBranchSum += recon.branchQtySum
	}
}

func buildWideMatrixReconAnomalies(byMonth map[string]*monthReconAgg) []domain.IngestionAnomaly {
	if len(byMonth) == 0 {
		return nil
	}
	keys := make([]string, 0, len(byMonth))
	for k, agg := range byMonth {
		if agg.valueGapRows > 0 || agg.qtyMismatchRows > 0 {
			keys = append(keys, k)
		}
	}
	if len(keys) == 0 {
		return nil
	}
	sort.Strings(keys)

	var out []domain.IngestionAnomaly
	var totalValueGapRows int
	var totalValueGap float64
	var totalQtyRows int

	for _, k := range keys {
		agg := byMonth[k]
		if agg.valueGapRows > 0 {
			totalValueGapRows += agg.valueGapRows
			totalValueGap += agg.unallocatedValue
			out = append(out, domain.IngestionAnomaly{
				IssueType: anomalyValueTotalGap,
				Description: fmt.Sprintf(
					"فجوة قيمة في %s: الاجمالى يختلف عن مجموع أعمدة الفروع بـ %.2f جنيه عبر %d صف — تم تسجيل الباقي تحت فرع %s",
					k, agg.unallocatedValue, agg.valueGapRows, UnallocatedBranchName,
				),
			})
		}
		if agg.qtyMismatchRows > 0 {
			totalQtyRows += agg.qtyMismatchRows
			qtyGap := agg.qtyBranchSum - agg.qtyFileSum
			out = append(out, domain.IngestionAnomaly{
				IssueType: anomalyQtyTotalMismatch,
				Description: fmt.Sprintf(
					"فجوة كمية في %s: اجمالى كميات (%d) يختلف عن مجموع أعمدة كمية الفروع (%d) بفارق %d عبر %d صف — أعمدة الفروع هي المرجع",
					k, agg.qtyFileSum, agg.qtyBranchSum, qtyGap, agg.qtyMismatchRows,
				),
			})
		}
	}

	if totalValueGapRows > 0 {
		out = append([]domain.IngestionAnomaly{{
			IssueType: anomalyValueTotalGap,
			Description: fmt.Sprintf(
				"تسوية قيمة: %.2f جنيه غير موزعة على فروع معروفة عبر %d صف في %d شهر/فترة — محفوظة تحت %s",
				totalValueGap, totalValueGapRows, countMonthsWith(byMonth, true, false), UnallocatedBranchName,
			),
		}}, out...)
	}
	if totalQtyRows > 0 {
		out = append(out, domain.IngestionAnomaly{
			IssueType: anomalyQtyTotalMismatch,
			Description: fmt.Sprintf(
				"تحذير كمية: اجمالى كميات لا يطابق مجموع أعمدة الفروع في %d صف عبر %d شهر/فترة (أعمدة الفروع هي المرجع)",
				totalQtyRows, countMonthsWith(byMonth, false, true),
			),
		})
	}
	return out
}

func countMonthsWith(byMonth map[string]*monthReconAgg, valueGaps, qtyGaps bool) int {
	n := 0
	for _, agg := range byMonth {
		if valueGaps && agg.valueGapRows > 0 {
			n++
		}
		if qtyGaps && agg.qtyMismatchRows > 0 {
			n++
		}
	}
	return n
}

// mergeWideMatrixReconIntoValidation copies wide-matrix reconciliation anomalies into the
// upload Validation so the UI surfaces amount / months / row counts. Flags status; never rejects.
func mergeWideMatrixReconIntoValidation(v *domain.IngestionValidation, payload *domain.NormalizedRetailIngestionPayload) {
	if v == nil || payload == nil {
		return
	}
	var valueMsgs, qtyMsgs []string
	for _, a := range payload.AnomaliesDetected {
		switch a.IssueType {
		case anomalyValueTotalGap:
			valueMsgs = append(valueMsgs, a.Description)
		case anomalyQtyTotalMismatch:
			qtyMsgs = append(qtyMsgs, a.Description)
		}
	}
	if len(valueMsgs) == 0 && len(qtyMsgs) == 0 {
		return
	}
	if v.Status == "ok" {
		v.Status = "flagged"
	}
	seenReason := map[string]bool{}
	for _, r := range v.DiffReasons {
		seenReason[r] = true
	}
	addReason := func(r string) {
		if !seenReason[r] {
			v.DiffReasons = append(v.DiffReasons, r)
			seenReason[r] = true
		}
	}
	seenIssue := map[string]bool{}
	for _, iss := range v.Issues {
		seenIssue[iss] = true
	}
	addIssue := func(msg string) {
		if msg == "" || seenIssue[msg] {
			return
		}
		v.Issues = append(v.Issues, msg)
		seenIssue[msg] = true
	}
	for _, m := range valueMsgs {
		addIssue(m)
		addReason(diffReasonUnallocated)
	}
	for _, m := range qtyMsgs {
		addIssue(m)
		addReason(diffReasonQtyMismatch)
	}
}
