# Branch master data (unified branch codes)

**HOLD:** no merge/deploy until owner reviews. Dry-run proposal does **not** write production.

## Design

Per-tenant durable tables (Firestore `branch_master/{tenant}`):

| Table | Role |
| --- | --- |
| `chains` | Internal chain code (`FTH`, `CRF`, …) + slug |
| `branches` | Internal branch code (`FTH-001`) + short display name |
| `branch_aliases` | Raw name → branch code, source, confidence, who/when |
| `pending` | Ambiguous / low-confidence names awaiting owner pick |

**Query/report-time mapping only.** Sell-Out / Sell-In / Returns facts keep raw `store_name` / `customer_name`. Reports group by branch code and show the short display name. Removing mapping reverts display; totals are unchanged (same fact sums).

**Unallocated** (`غير موزع على فرع`) is a reserved bucket (`FTH-UNALLOC`, …) and is **never** auto-linked.

## Resolution order (later uploads)

1. Exact / normalized alias hit → instant map (no AI)
2. Else deterministic similarity (+ optional Gemini `AIProposer`)
3. High confidence → auto-link + save alias + notice
4. Ambiguous (close to two, e.g. دمنهور vs دمنهور الاستاد) or low → `PENDING`
5. Genuinely new → new code + notify owner

## Bootstrap

First confirmation applies a dry-run proposal sheet once (`POST /api/v1/branches/bootstrap/confirm`). Adeco dry-run artifact is generated with:

```bash
go run ./cmd/branchmasterdryrun -out /tmp -tenant adeco
```

## APIs

- `GET /api/v1/branches/master`
- `GET /api/v1/branches` · `GET /api/v1/branches/aliases` · `GET /api/v1/branches/pending`
- `PUT /api/v1/branches` (edit display name)
- `POST /api/v1/branches/pending/confirm` · `…/reject`
- `POST /api/v1/branches/dry-run` · `POST /api/v1/branches/bootstrap/confirm`

## UI

«إدارة الفروع» from Data Quality (الأخطاء) — RTL Arabic, M3.

## Package

`backend-go/internal/service/branchmaster/`
