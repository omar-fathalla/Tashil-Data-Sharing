# Sell-Out category refresh — plan (not executed)

Status: **PLAN ONLY.** Nothing in this PR runs against production. No BigQuery DML, no backfill, no
deploy, no workflow change. Client files (archives, Excel, mapping CSVs) stay outside the repo; the
dry-run tool refuses to write or read them inside a git work tree.

## Problem

PR #225 (`0ad4d0d`, live v217) takes the Sell-Out category from each chain's own «المجموعة» cell, for
Adeco and competitors alike. Product Master fills only a blank cell. Normalization is spelling only.
But `tashil_analytics.sell_out_facts` (tenant-adeco, ~109,313 rows) still holds the category written at
upload time, from the old Product Master grouping. Examples: bleach rows merged under «كلور عادى», and
Adeco dish soap at ~34.42M where Excel 2026 gives 43.44M.

## 1. Root cause (code paths on `main` @ `0ad4d0d`)

The startup sequence in `backend-go/cmd/server/main.go`, function `loadData`, runs in this order:

1. **L186-188**: `ClearTenantData("all")`, then `RestoreOrReplay`. PR #225 bumped
   `SnapshotParserVersion` (`internal/service/ingestion/snapshot.go` L144). That makes the old
   snapshot stale, so `RestoreOrReplay` (snapshot.go L481-485) serves the stale snapshot and starts
   `runBackgroundRebuild`. The rebuild re-parses every archived sheet with the new rule, so memory
   briefly holds the **correct** categories.
2. **L200-208**: `ReconcileArchivesToSink`. `PlanArchiveSync`
   (`internal/service/ingestion/archive_reconcile.go` L135-137) marks a file for rewrite only when
   `StoredBefore == 0`, meaning BigQuery has no rows under its archive id. Every Sell-Out file already
   has rows, so every file is reported `ok` and **nothing is rewritten**. A parser change never reaches
   BigQuery through this path.
3. **L209**: `SyncDurableFromStore(..., force=true)`. This goes to `durableSync.sync`
   (`internal/service/ingestion/sellin_store.go` L143-187). Because `force` is set, the version check
   at L163 is skipped, and `apply()` at L184 calls the reader registered in `WithSellOutStore`
   (L103-113). That reader is `bqsink.ReadSellOut` (`internal/service/bqsink/read.go` L152), which
   uses `SellOutReadSQL` (L97-106) and `DecodeSellOutRow` (L128-149). The rows then go to
   `bigquery.Client.ReplaceSellOutFacts` (`internal/service/bigquery/sellout_store.go` L12-33). That
   function **swaps the tenant's whole fact set** and keeps every fact "exactly as stored". It never
   re-enriches the rows or re-derives the category.
4. **L160-164**: when the background rebuild finishes, `OnRebuilt` runs
   `SyncDurableFromStore(..., true)` again. This replaces the freshly re-parsed facts with the stored
   ones a second time.
5. `RunDurableSync` (L223) later reloads from BigQuery on every `data_versions` bump. It also reads
   the stored category.

There is also a second path that reads the stored category directly. When the sink is live
(main.go L245-250), the explorer, Compare and target breakdown query `sell_out_facts` in BigQuery
instead of memory:

- `bqsink/records.go` L116 and L166
- `bqsink/competitive_monthly.go` L46
- `bqsink/target_breakdown.go` L54

So fixing only the in-memory copy would still leave those screens showing the old categories.

The new rule lives only in the parse path (`ingestion/processor.go` L486-509 and L590-597). The
dedup key, `RecordID = fact_{tenant}_{chain}_{store}_{supplier}_{barcode}_{date}` at L550-551, does
**not** include the category. So a category change never changes row identity.

## 2. Options

| | What | Fixes BQ-side screens | Touches measures / identity | Ongoing cost | Risk |
|---|---|---|---|---|---|
| (a) code-only | On load, re-derive category from the archived sheet, or let the replay win over BigQuery for `category` | **No** (records, Compare and target breakdown still read BQ) | No | Every instance must finish the full archive replay before it serves. The overlay must be re-applied after each `RunDurableSync` reload. | Two sources of truth that can disagree. Cold start stays slow. |
| (b) one-time refresh | Re-parse the archives offline, then `UPDATE sell_out_facts SET category` for matched rows only | Yes | **No.** Only `category` is written, keyed by `record_id` + `ingestion_batch_id` and guarded by the old value | None. New uploads already write sheet categories (PR #225). | Low and fully reversible (backup + reverse mapping). Needs one controlled DML. |
| (c) re-upload / replay | Force-rewrite every Sell-Out archive through the sink (DELETE + INSERT by archive id) | Yes | **Yes.** Every column is rewritten: factory cost is re-enriched from today's Product Master, and `ingested_at`/`batch_id` change. That reorders "latest batch wins" in `SellOutReadSQL`, which can change **which** rows are served. | None | Revenue and row totals can move. Heavier write. |

**Recommendation: (b).** It is the only option that fixes every screen and leaves measures and
identity untouched by construction. Option (a) leaves BigQuery-backed screens wrong. Option (c)
rewrites far more than the category and can change totals.

## 3. Safety guarantees (enforced by the planner, `ingestion/sellout_category_refresh.go`)

- **Dedup key and SUMs unchanged.** The UPDATE sets `category` only. `record_id`, `quantity_sold`,
  `net_revenue`, chain, store and every other column are not written. The planner recomputes row
  count, SUM(quantity) and SUM(net revenue) before and after. If any of them differs,
  `Violations()` returns the problem, the report prints `RESULT: UNSAFE`, and the tool exits 1.
- **No cross-customer attribution.** A row changes only when its re-parsed twin has the same
  match key and the same chain, store, supplier, own-brand flag, barcode, date, quantity and
  revenue. The match key is the stored `record_id` with one leading `tenant-` / `tenant_` stripped
  from the segment after `fact_` (the same one-prefix strip `bqsink.NormalizeTenant` uses). The
  mapping CSV and the UPDATE keep the stored id (`fact_adeco_…`), so a replay id of
  `fact_tenant-adeco_…` still hits the BigQuery row. A stacked prefix is not stripped twice, so
  `fact_tenant-tenant-adeco_…` cannot land on `adeco`. Duplicate ids, empty re-parsed categories
  and any other drift are **blocked**: the row
  keeps its stored category and is listed by reason. Rows found only in the re-parsed data are
  reported and **never inserted**.
- **Unknown customers stay quarantined.** Customer quarantine (Sell-In registry,
  `upload_guards.go` `quarantineSellIn`) and alias remaps act on `sell_in_records`. This plan touches
  neither `sell_in_records` nor the Firestore registry. The re-parse runs on mock Firestore with no
  sink attached (`ReplaySellOutArchivesForCategoryPlan`, replay mode), so it cannot approve, merge or
  write anything.
- **Deleted files stay deleted.** Only Sell-Out archives that BigQuery currently stores rows for
  (from `ArchiveRowCounts`) are re-parsed, so tombstoned uploads are skipped even without Firestore.
- **Idempotent DML.** `AND IFNULL(t.category,'') = m.old_category` turns a re-run, or a row changed
  since the dry run, into a no-op instead of an overwrite.

## 4. Read-only dry run

`backend-go/cmd/selloutcategoryplan` has **no write mode**. Its only BigQuery calls are `SELECT`s
(`ReadSellOut`, `ArchiveRowCounts`).

```bash
cd backend-go
TASHIL_ARCHIVE_DIR=/secure/archive PROJECT_ID=tashil-data-sharing BIGQUERY_DATASET=tashil_analytics \
  go run ./cmd/selloutcategoryplan -tenant=tenant-adeco \
  -expected=/secure/excel_2026_category_totals.csv \
  -mapping-out=/secure/sellout_category_fix_YYYYMMDD.csv
```

- `-expected` is a CSV. With a header the columns are named, in any order:
  `chain,category,scope,year,net_revenue` (`year` may be omitted). Without a header, four columns
  are `chain,category,scope,net_revenue` (every year) and five are
  `chain,category,scope,year,net_revenue`. `scope` is `own` (Adeco), `competitor`, or `all`.
  `year` empty, `*` or `all` sums every year; `2026` is that transaction year only. `chain` `*`
  means every chain. Categories are matched after spelling normalization. The 2026 Adeco check is:

```csv
chain,category,scope,year,net_revenue
*,صابون سائل اطباق,own,2026,43438310.05
*,كلور عادى,own,2026,7312599.10
*,كلور ألوان,own,2026,7801322.10
*,كلور ارضيات,own,2026,522531
```
- The report prints:
  - the counts: stored, re-parsed, matched, unchanged, to change, blocked, only-stored, only-re-parsed
  - rows, quantity and net revenue **before and after**, which must be identical
  - category moves, per chain and own/competitor: `from -> to | rows | revenue`
  - per-chain category totals before and after, for the focus words (default: كلور, اطباق, صحون)
  - the Excel reconciliation: chain, year, scope, expected, before, after, and after minus expected
  - blocked rows grouped by reason, and `RESULT: SAFE/UNSAFE`
- Independent SQL cross-checks (read-only, run in the BigQuery console):

```sql
-- served rows / units / revenue per chain × category (compare before vs after)
SELECT retailer_chain, is_own_brand, category, COUNT(*) n, SUM(quantity_sold) qty, ROUND(SUM(net_revenue),2) rev
FROM (/* SellOutReadSQL view body, tenant_id = 'tenant-adeco' */) GROUP BY 1,2,3 ORDER BY 1,2,6 DESC;
-- superseded physical rows that share a record_id with a mapped row but are not served (left as is; report count)
SELECT COUNT(*) FROM `tashil_analytics.sell_out_facts` t JOIN `tashil_analytics.sell_out_category_fix_YYYYMMDD` m
  ON t.record_id = m.record_id WHERE t.tenant_id='tenant-adeco' AND IFNULL(t.ingestion_batch_id,'') != m.ingestion_batch_id;
```

Acceptance criteria for the dry run:

- `RESULT: SAFE`
- `only re-parsed` = 0, or every such row explained
- blocked rows reviewed
- Adeco 2026 own-brand "after" matches the Excel figures in the CSV above. The read-only run on
  2026-11-17 landed at 43,438,262.05 (dish soap, Excel 43,438,310.05), 7,312,599.10 (كلور عادى),
  7,801,322.10 (كلور ألوان) and 522,528 (كلور ارضيات, Excel 522,531). The 48 and 3 EGP gaps are
  inside those categories; row count and the revenue SUM did not move. They stay visible as
  after-minus-expected and need a spot check before approval.

## 4.1 What the read-only run showed

Nothing was written. Two findings:

**Record id prefix (blocking, fixed in this PR).** The first run matched 0 rows. Re-parse builds
`fact_{tenantID}_…` and the archive tenant is `tenant-adeco`, so replay ids are `fact_tenant-adeco_…`.
BigQuery stores `fact_adeco_…`: ingest used the slug it was given (`processor.go`, the `fact_%s_…`
format) and the sink writes `record_id` unchanged while it normalizes the `tenant_id` column.
Folding that one prefix the way `bqsink.NormalizeTenant` does, offline, gave matched 109,313,
blocked 0, duplicate ids 0, totals identical, and 28,646 category changes. The mapping keeps the
stored `fact_adeco_…` id.

**Competitor rows that move are the old alias, not an own-flag bug.** Two competitor moves showed
up: منظف ارضيات → مطهر ارضيات (238 rows, 1.62M) and منظف ارضيات → كلور ارضيات (30 rows, 0.37M),
both `own=false`. Before #225, `productCategoryAliases` mapped both «مطهر ارضيات» and «كلور ارضيات»
to «منظف ارضيات». The wide-matrix parser runs `NormalizeProductCategory` on «المجموعة» for every
supplier before it splits own-brand from competitor (`wide_matrix_parser.go`, `sheetCat` then
`isOwn` / `wideMatrixRecordCategory`), so competitor rows were stored under the merged name too.
#225 dropped those type-changing aliases and kept spelling-only normalization, for Adeco and
competitors alike. The planner changes a row only when `IsOwnBrand` matches, and this run blocked
0 rows, so the flag did not flip. The moves are the approved rule: the sheet category wins.

## 5. Backup, execution, rollback (each step needs owner approval)

Run in a quiet window with no uploads. Confirm with `scripts/check_cloud_run_one_instance.sh`, or
pause uploads.

1. **Dry run** (section 4). Archive the report and the mapping CSV in secure storage, not git.
   *Owner sign-off on the numbers.*
2. **Backup (DDL):**
   `CREATE TABLE tashil_analytics.sell_out_facts_backup_YYYYMMDD_category CLONE tashil_analytics.sell_out_facts;`
   Verify that its tenant-adeco `COUNT(*)` and `SUM(net_revenue)` equal the live table. BigQuery time
   travel (7 days) is the second fallback.
3. **Load the mapping:** `bq load --source_format=CSV --skip_leading_rows=1 tashil_analytics.sell_out_category_fix_YYYYMMDD /secure/…csv record_id:STRING,ingestion_batch_id:STRING,old_category:STRING,new_category:STRING`.
   Check that the row count equals the dry run's "to change".
4. **Re-run the dry run immediately before the DML.** If its mapping differs from the loaded one
   (data changed in between), stop.
5. **DML:** run the UPDATE that the tool prints, `SellOutCategoryUpdateSQL`, with
   `@tenant_id='tenant-adeco'` inside `BEGIN TRANSACTION … COMMIT`. Expected affected rows = the
   mapping row count. If they differ, `ROLLBACK`.
6. **Verify (read-only):** row count, SUM(quantity) and SUM(net_revenue) are identical to the backup.
   Per-category totals equal the dry-run "after" figures.
7. **Propagate:** bump `data_versions/adeco__sell_out` (Firestore write) so every instance reloads
   within ~30 s (`RunDurableSync`), or restart the Cloud Run revision (startup forced sync). No deploy
   is needed. Spot-check the dashboard: dish soap, bleach split, Compare.
8. **Clean up** after the owner accepts: drop the mapping table after N days, and keep the backup for
   at least 30 days.

**Rollback:** run `SellOutCategoryRollbackSQL` with the same mapping table. Its guard,
`category = new_category`, means only refreshed rows revert. If needed, restore the whole tenant slice
from the clone instead: `DELETE … WHERE tenant_id='tenant-adeco'` plus
`INSERT … SELECT * FROM backup WHERE tenant_id='tenant-adeco'`, in one transaction. Then bump
`data_versions/adeco__sell_out`.

## Risks

- **Parser drift.** The re-parse runs on mock Firestore, so learned mapping corrections are absent and
  a sheet could parse slightly differently. The identity and measure guard blocks those rows instead
  of guessing. Review the blocked counts.
- **Superseded physical rows** (older batches with the same `record_id`) keep the old category. They
  are served only if a newer file is deleted later. The SQL in section 4 counts them, and they can be
  mapped in the same way if the owner wants.
- **Product Master fallback.** Like the server replay, the planner applies the first archived catalog
  for blank cells. Blank cells are rare in the 2026 sheets. Check that "منظفات وعناية منزلية" does
  not grow in the report.
- **Concurrent upload during the DML.** BigQuery retries or aborts on concurrent update. The
  old-value guard prevents overwriting a fresh upload.
