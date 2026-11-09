package matcher

import (
	"sort"
	"strings"
)

// PriorityBand is a coarse Arabic-facing priority for the review UI.
type PriorityBand string

const (
	PriorityHigh   PriorityBand = "high"
	PriorityMedium PriorityBand = "medium"
	PriorityLow    PriorityBand = "low"
)

// Priority thresholds — high-impact Sell-In rows surface first.
const (
	highValueMin   = 10000.0
	mediumValueMin = 1000.0
	highRowsMin    = 50
	mediumRowsMin  = 10
)

// PriorityOf ranks one review item for human attention.
// Higher business impact (value / row count) comes first.
func PriorityOf(item ReviewItem) PriorityBand {
	v := item.Query.Value
	r := item.Query.Rows
	switch {
	case v >= highValueMin || r >= highRowsMin:
		return PriorityHigh
	case v >= mediumValueMin || r >= mediumRowsMin:
		return PriorityMedium
	default:
		return PriorityLow
	}
}

// PriorityScore is a stable descending sort key (higher = show earlier).
func PriorityScore(item ReviewItem) float64 {
	band := 0.0
	switch PriorityOf(item) {
	case PriorityHigh:
		band = 3e12
	case PriorityMedium:
		band = 2e12
	default:
		band = 1e12
	}
	// Within a band: higher value/rows first; lower confidence next (harder matches).
	conf := item.Result.Confidence
	if conf < 0 {
		conf = 0
	}
	if conf > 1 {
		conf = 1
	}
	return band + item.Query.Value*1e6 + float64(item.Query.Rows)*1e3 + (1-conf)*100
}

// SortReviewItemsByPriority sorts pending/review rows for the prioritized UI.
func SortReviewItemsByPriority(items []ReviewItem) {
	sort.SliceStable(items, func(i, j int) bool {
		si, sj := PriorityScore(items[i]), PriorityScore(items[j])
		if si != sj {
			return si > sj
		}
		return items[i].ID < items[j].ID
	})
}

// BulkApproveEligible reports whether a pending item may be bulk-approved using its
// matched Product Master suggestion. Never invents barcodes — requires a non-empty
// suggested barcode already present on the match result (from input or master).
func BulkApproveEligible(item ReviewItem) bool {
	if strings.TrimSpace(item.Status) != "" && item.Status != StatusPending {
		return false
	}
	if item.Result.Decision != DecisionUncertain {
		return false
	}
	if strings.TrimSpace(item.Result.MatchedItemCode) == "" {
		return false
	}
	if strings.TrimSpace(item.Result.SuggestedBarcode) == "" {
		return false
	}
	return true
}
