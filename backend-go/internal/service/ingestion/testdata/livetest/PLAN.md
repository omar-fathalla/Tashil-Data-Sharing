# Tashil live test plan: upload normalization (PR #21)

TOP RULE: NEVER attribute one customer's data to another customer. No guessing in customer attribution, ever.

## Setup (needs Mohamed)
- A chain named **QA Test** (code `qa_test`) must exist: صفحة الأدمن → السلاسل → إضافة (or `POST /api/v1/admin/chains`).
  It was NOT created automatically (no admin login was used).
- Every customer, branch and item in these files starts with `QA`, so nothing matches a real customer.
- Sell-In files (SOP and plan layout): Sell-In explorer → رفع ملف توريد, chain **QA Test**.
- Sell-Out file (15): بوابة الرفع, chain **QA Test**.
- Write down the Sell-In/Sell-Out totals for real chains before you start. They must be unchanged at the end.

| # | File | Tab | Chain | Period in the form | Expected outcome |
|---|------|-----|-------|--------------------|------------------|
| 01 | 01_month_formats.xlsx | Sell-In | QA Test | none | Accepted: 6 rows, Jan to Jun 2026, 100 EGP each. The customer is quarantined (see 08) until approved. |
| 02 | 02_bad_month.xlsx | Sell-In | QA Test | none | Rejected (Arabic: month could not be read). Nothing stored. |
| 03 | 03_empty_year.xlsx | Sell-In | QA Test | none | Rejected: no year in the row or the filename. No 2026 default. |
| 04 | 04_empty_year_qa_2026.xlsx | Sell-In | QA Test | none | Accepted as March 2026 (year taken from the filename). |
| 05a | 05a_full_month.xlsx | Sell-In | QA Test | none | Accepted: July 2026, 30 rows, 3,000 EGP. |
| 05b | 05b_partial_month.xlsx | Sell-In | QA Test | none | Partial-month dialog (2 rows / 100 EGP vs 30 / 3,000). Cancel saves nothing. "أيوه، استبدل" replaces. |
| 06 | 06_form_vs_sheet.xlsx | Sell-In | QA Test | Jan 2026 | Period dialog listing Aug + Sep 2026. "استخدم شهور الملف" (recommended) gives Aug/Sep. "فترة الفورم" puts both rows in Jan. |
| 07 | 07_year_2027.xlsx | Sell-In | QA Test | none | Accepted. After a reload, 2027 shows in the year filters (Executive, Sell-In explorer, pricing, competitor). |
| 08 | 08_unknown_customer.xlsx | Sell-In | QA Test | none | Accepted, but "QA عميل جديد خالص" (77 EGP) is out of the totals and shows under الأخطاء → عملاء محتاجين تأكيد. Approve it (optionally with chain qa_test): the 77 EGP appears right away. Unmerge removes it again. Reject keeps it out. Each step adds an audit log entry. |
| 09 | 09_reordered_columns.xlsx | Sell-In | QA Test | none | Same result as the March row of 01. Columns are matched by header name. |
| 10 | 10_missing_value_column.xlsx | Sell-In | QA Test | none | Rejected: the value column is missing. Nothing stored. |
| 11 | 11_formula_cells.xlsx | Sell-In / Sell-Out | QA Test | none | Rejected: "افتح الملف في إكسل واحفظه مرة تانية". After opening and saving in Excel, row 2 is accepted. |
| 12 | 12_unknown_barcode.xlsx | Sell-In | QA Test | none | Accepted, 55 EGP kept, with an unknown-item warning. It shows on الأخطاء with source "ملف توريد: 12_unknown_barcode.xlsx". |
| 13 | 13_fuzzy_near_match.xlsx | Sell-In | QA Test | none | "QA عميل تجريبى" (ى instead of ي) normalizes to the same name as "QA عميل تجريبي": it follows that name's status. It is never merged into a different name. If it shows as pending, any suggestion is a hint only. |
| 14 | 14_two_fathalla_cities.xlsx | Sell-In | QA Test | none | Two separate pending customers (الغردقة 10 EGP, طنطا 20 EGP). They never merge into each other. |
| 15 | 15_sellout_form_vs_sheet.xlsx | Sell-Out (بوابة الرفع) | QA Test | Jan 2026 | Period dialog with Aug and Sep 2026. Pick an option, then analyze and commit. Choosing only the year or only the month shows a validation message instead of a guessed value. |

Approve "QA عميل تجريبي" once (step 08 flow) to see 01/04/05/06/07/09 rows in the totals.

## Cleanup
1. Sell-In explorer → archive: delete each archived QA file (filter chain QA Test). The derived rows are removed with the archive.
2. Upload portal archive: delete 15_sellout_form_vs_sheet.xlsx.
3. عملاء محتاجين تأكيد: reject every `QA…` name. Registry entries are kept for audit; rejected names stay out of totals.
4. الأخطاء: the QA unknown-item issue resolves when its file is deleted (or mark it resolved).
5. Delete chain QA Test.
6. Check that real-chain totals equal the numbers you wrote down before starting.

Rebuild the files with `python3 build.py` (openpyxl).
