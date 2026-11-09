---
cursor:
  subagentId: "bc-c458e397-32ee-5f05-a5fe-2e7cd211dee3"
---

# Adeco branch master — dry-run proposal

**Status: HOLD — owner approval required before any production write.**

- Tenant: `adeco`
- Generated (UTC): `2026-11-09T17:40:32Z`
- Live input: `adeco-live-occurrences.json`
- **Unification sources only:** `in26.xlsx` (Sell-In + Returns) + `out26.xlsx` (Sell-Out)
- **Excluded (BQ untouched):** `Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx` / `arch_sellin_adeco_fathalla_1794179188685072646` — no parent/mini/Regional/16 codes in this proposal
- Raw name observations: **91**
- Unique normalized keys / proposed branches: **40**
- Chains: **1**

## Source of prior false names (corrected)

Earlier dry-runs listed «كيه اتش جمله ماركت …» and «فتح الله بيت الجمله …» (BET).
Those came from **embedded fixtures**, not live Adeco BQ:

- `backend-go/internal/service/customers/seed_customers.json` (199 names; ~60 KH, ~30 BET)
- `backend-go/internal/service/customers/seed_aliases.json` (~60 KH alias pairs)
- wired by `cmd/branchmasterdryrun` via `customers.SeedCustomerNames()` / `SeedAliasPairs()`
- plus an **old local archive xlsx** header pass (`arch_adeco_fathalla_1792258238476465882_2026 out.xlsx`), not current `out26`

Checked and **not** the source: live `sell_in_records`, live `sell_out_facts`, and `sell_in_records_backup_20261109_in26` contain **no** `كيه اتش` / `بيت الجمله` tokens.
This dry-run uses **live BQ in26+out26 only** (Plan archive excluded from unification; not deleted).

## Data provenance (live)

- returns ← tashil_analytics.sell_in_records / in26.xlsx (arch_sellin_adeco_fathalla_1794178032976473890)
- sell_in ← tashil_analytics.sell_in_records / in26.xlsx (arch_sellin_adeco_fathalla_1794178032976473890)
- sell_out ← tashil_analytics.sell_out_facts / out26.xlsx (arch_adeco_fathalla_1794146334922507694)

## Per-source branch count reconciliation

| Source file | Table | Raw spellings | Care | Grocery/other | Unique locations | Note |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `in26.xlsx` | `tashil_analytics.sell_in_records` | 56 | 27 | 29 | 30 | in26: 29 grocery + 27 care spellings → 30 locations after مواد عناية merge with grocery (طنطا Out Let care-only stays separate). |
| `out26.xlsx` | `tashil_analytics.sell_out_facts` | 35 | 0 | 35 | 35 | Sell-Out wide-matrix stores = 35 (this is the «35» live branch count from out26). |

- «35» (Sell-Out) = distinct store_name in live sell_out_facts for out26 archive arch_adeco_fathalla_1794146334922507694.
- in26: ~29 grocery + care-only طنطا Out Let ≈ 30 locations after owner care=grocery merge.
- Owner (#70): Plan_2026_Clean archive excluded from unification (BQ data untouched). Proposal = in26 + out26 only.
- Proposed branch codes = in26/out26 store locations under chain policy; numbered branches stay separate.

## Top summary

| Metric | Count |
| --- | ---: |
| Sell-In **and** Sell-Out | 25 |
| Sell-In only (normal) | 5 |
| Sell-Out only (normal) | 10 |
| Multi-spelling merges | 28 |
| Branches with Returns coverage | 30 |
| Likely misspelling pairs (informational) | 0 |
| Owner questions / ambiguous | 0 / 0 |

### Per chain

| Chain | Code | Branches | SI+SO | SI only | SO only | +Returns |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| fathalla | `FTH` | 40 | 25 | 5 | 10 | 30 |

### Chain policies in effect

| Slug | Care+grocery merge | Numbered distinct | Quarantine unknown |
| --- | --- | --- | --- |
| `fathalla` | true | true | true |

## Notes

- هذا تقرير تجريبي (dry-run) فقط — لم يُكتب أي شيء في الإنتاج.
- توحيد الفروع = in26.xlsx (Sell-In/Returns) + out26.xlsx (Sell-Out) فقط.
- مستبعد من هذا الـ dry-run: Adco_Fathalla_Sell_In_Plan_2026_Clean.xlsx / arch_sellin_adeco_fathalla_1794179188685072646 — بلا صفوف أب/ميني/Regional ولا 16 كودًا. بيانات BQ لم تُحذف ولم تُعدَّل.
- المصادر = بيانات Adeco الحية فقط (BigQuery). لا seed_customers / seed_aliases.
- قواعد السلسلة قابلة للضبط لكل chain (care+grocery merge، أرقام الفروع، quarantine للأسماء المجهولة).
- قرار المالك: مواد عناية + بقالة لنفس الموقع = فرع واحد (FTH)؛ أرقام مختلفة = فروع مختلفة؛ المسافة فقط مع نفس الرقم تُدمَج.
- Sell-In = شحنات الشركة وقد يشمل مواقع إضافية (مخازن مثل مخزن الافوجادو) — Sell-In-only طبيعي؛ يُعلَّم type=warehouse عند المخزن.
- Sell-Out = نقاط البيع. وجود فرع في ملف واحد فقط (Sell-In فقط أو Sell-Out فقط) طبيعي — لا تحذير ولا سؤال مالك.
- لا ربط تلقائي بين مصادر مختلفة؛ كل صف يبقى مستقلاً بقيمه حتى يقرر المالك الدمج. العرض في التقارير = الاسم القصير فقط (بدون «فرع فتح الله -»).
- عدد الفروع التي دُمجت فيها مواد عناية + بقالة في هذا dry-run: 27.
- جسور المالك: الإبراهيمية = الابراهيمية ريفيرا؛ دمنهور = دمنهور الأندلس؛ سيدي جابر = سيدي جابر المحطة. تبقى منفصلة: الإبراهيمية ميني، دمنهور الاستاد، سيدي جابر ميني.
- مصدر Returns = صفوف sell_in_records ذات قيمة سالبة أو نوع مرتجع (من in26).

## Sell-In vs Sell-Out rules

- **Sell-In** = company shipments; may include warehouses (`location_type=warehouse`).
- **Sell-Out** = points of sale.
- **SI-only / SO-only are normal** — counted and shown as their own rows under their own names/values. **No warning / no owner question.**
- Never auto-link across sources; single-file rows stay their own codes until the owner maps them — never hidden, never guess-merged.
- **Display** in reports = short branch name only (chain prefix stripped, e.g. `الأنفوشي` not `فرع فتح الله - الأنفوشي`). Raw spellings remain in the raw column.

## Proposed branches

| Code | Chain | Type | Display | Raw spellings (with source) | Sources |
| --- | --- | --- | --- | --- | --- |
| `FTH-001` | fathalla (`FTH`) | store | ابو يوسف | عائله فتح الله ماركت - أبو يوسف _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - أبو يوسف _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - ابو يوسف _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-002` | fathalla (`FTH`) | store | أمواج | عائله فتح الله ماركت - أمواج _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - أمواج _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - أمواج - الساحل الشمالي _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-003` | fathalla (`FTH`) | store | أكتوبر | عائله فتح الله ماركت - اكتوبر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - اكتوبر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - أكتوبر _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-004` | fathalla (`FTH`) | store | الأنفوشي | فرع فتح الله - الأنفوشي _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-005` | fathalla (`FTH`) | store | الإبراهيمية | عائله فتح الله ماركت - الابراهيمية ريفيرا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - الابراهيمية ريفيرا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - الإبراهيمية _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-006` | fathalla (`FTH`) | store | الإبراهيمية ميني | فرع فتح الله - الإبراهيمية ميني _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-007` | fathalla (`FTH`) | store | الدخيلة مينى 2 | فرع فتح الله - الدخيلة مينى 2 _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-008` | fathalla (`FTH`) | store | الدخيلة ميني | فرع فتح الله - الدخيلة ميني _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-009` | fathalla (`FTH`) | store | الرحاب | عائله فتح الله ماركت - الرحاب _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - الرحاب _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - مدينة الرحاب _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-010` | fathalla (`FTH`) | store | المحلة الكبرى | عائله فتح الله ماركت - المحلة الكبري _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - المحلة الكبري _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - المحلة الكبرى _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-011` | fathalla (`FTH`) | store | النصر | عائله فتح الله ماركت - ش النصر بلازا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - ش النصر بلازا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - النصر _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-012` | fathalla (`FTH`) | store | بحري | عائله فتح الله ماركت - بحري _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - بحري _(sell_in:in26.xlsx)_ | sell_in+returns |
| `FTH-013` | fathalla (`FTH`) | store | جاردينيا | عائله فتح الله ماركت - جاردينيا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - جاردينيا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - جاردينيا _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-014` | fathalla (`FTH`) | store | دمنهور | عائله فتح الله ماركت - دمنهور _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - دمنهور _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - دمنهور الأندلس _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-015` | fathalla (`FTH`) | store | دمنهور - الاستاد | عائله فتح الله ماركت - دمنهور - الاستاد _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - دمنهور - الاستاد _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - دمنهور - الاستاد _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-016` | fathalla (`FTH`) | store | دمياط الجديدة | عائله فتح الله ماركت - دمياط الجديدة _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - دمياط الجديدة _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - دمياط الجديدة _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-017` | fathalla (`FTH`) | store | روزانا | عائله فتح الله ماركت - قرية روزانا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - قرية روزانا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - روزانا _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-018` | fathalla (`FTH`) | store | ستانلي | عائله فتح الله ماركت - ستانلي _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - ستانلي _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - ستانلي _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-019` | fathalla (`FTH`) | store | سموحة | عائله فتح الله ماركت - سموحة _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - سموحة _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - سموحة _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-020` | fathalla (`FTH`) | store | سموحة ميني | فرع فتح الله - سموحة ميني _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-021` | fathalla (`FTH`) | store | سيتي سكوير | عائله فتح الله ماركت - سيتي سكوير _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - سيتي سكوير _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - سيتي سكوير _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-022` | fathalla (`FTH`) | store | سيدي بشر ميني | فرع فتح الله - سيدي بشر ميني _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-023` | fathalla (`FTH`) | store | سيدي جابر | عائله فتح الله ماركت - سيدي جابر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - سيدي جابر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - سيدي جابر المحطة _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-024` | fathalla (`FTH`) | store | سيدي جابر ميني | فرع فتح الله - سيدي جابر ميني _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-025` | fathalla (`FTH`) | store | طنطا | عائله فتح الله ماركت - طنطا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - طنطا _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - طنطا _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-026` | fathalla (`FTH`) | store | طنطا - اوت ليت مول | عائله فتح الله ماركت مواد عناية - طنطا Out Let _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - طنطا - اوت ليت مول _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-027` | fathalla (`FTH`) | store | طوسون | عائله فتح الله ماركت - طوسون _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - طوسون _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - طوسون _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-028` | fathalla (`FTH`) | store | عجمي ستار | عائله فتح الله ماركت - عجمى ستار _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - عجمى ستار _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - عجمي ستار _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-029` | fathalla (`FTH`) | store | فلمنج | عائله فتح الله ماركت - فلمنج _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - فلمنج _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - فلمنج _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-030` | fathalla (`FTH`) | store | كفر الدوار | عائله فتح الله ماركت - كفر الدوار _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - كفر الدوار _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - كفر الدوار _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-031` | fathalla (`FTH`) | store | كفر الدوار - مول | فرع فتح الله - كفر الدوار - مول _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-032` | fathalla (`FTH`) | store | كفر الدوار 2 | عائله فتح الله ماركت - كفر الدوار 2 _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - كفر الدوار2 _(returns:in26.xlsx, sell_in:in26.xlsx)_ | sell_in+returns |
| `FTH-033` | fathalla (`FTH`) | warehouse | مخزن أبيس 4 المركزى | عائله فتح الله ماركت - مخزن أبيس 4 المركزى _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - مخزن أبيس 4 المركزى _(returns:in26.xlsx, sell_in:in26.xlsx)_ | sell_in+returns |
| `FTH-034` | fathalla (`FTH`) | warehouse | مخزن الافوجادو | عائله فتح الله ماركت - مخزن الافوجادو _(returns:in26.xlsx, sell_in:in26.xlsx)_ | sell_in+returns |
| `FTH-035` | fathalla (`FTH`) | store | مدينه بدر | عائله فتح الله ماركت - مدينه بدر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - مدينه بدر _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - مدينه بدر _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-036` | fathalla (`FTH`) | store | مطروح | عائله فتح الله ماركت - مطروح _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>عائله فتح الله ماركت مواد عناية - مطروح _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - مطروح _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |
| `FTH-037` | fathalla (`FTH`) | store | ملك حفنى | فرع فتح الله - ملك حفنى _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-038` | fathalla (`FTH`) | store | نيس | عائله فتح الله ماركت - نيس _(returns:in26.xlsx, sell_in:in26.xlsx)_ | sell_in+returns |
| `FTH-039` | fathalla (`FTH`) | store | نيس2 | فرع فتح الله - نيس2 _(sell_out:out26.xlsx)_ | sell_out |
| `FTH-040` | fathalla (`FTH`) | store | هانوفيل | عائله فتح الله ماركت - الهانوفيل _(returns:in26.xlsx, sell_in:in26.xlsx)_<br>فرع فتح الله - هانوفيل _(sell_out:out26.xlsx)_ | sell_in+sell_out+returns |

## Next step

Owner answers the PENDING questions above, then `POST /api/v1/branches/bootstrap/confirm` with the JSON payload — **not** done by this dry-run.
