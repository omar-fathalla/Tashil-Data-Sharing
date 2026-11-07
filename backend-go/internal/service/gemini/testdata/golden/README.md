# Gemini golden regression set

Sanitized fixtures that mirror **historical Adeco sell-out / sell-in layouts** (wide Fathalla pivot-style matrix, long Carrefour-like rows, QA Sell-In SOP, form-vs-sheet Sell-Out). No production customer PII — barcodes and branch names are synthetic or QA-prefixed.

Each case directory has:

- `expected.json` — stable totals / mapping expectations for regression
- `mapping_plan.json` (optional) — Gemini column-map schema sample that must validate
- Rows are built in `golden_test.go` (or the shared livetest workbook is loaded) so large real archives are never copied into git

**Success metrics (Phase A7):** schema_valid, mock_blocked_in_prod, human_approval_required, pii_minimized, per_call_logged.
