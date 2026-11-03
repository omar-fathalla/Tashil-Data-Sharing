"""Builds the synthetic live-test workbooks. Every customer/branch/item name starts with 'QA' so cleanup
is one filter; values are small round numbers so they are easy to spot in totals."""
from openpyxl import Workbook

PLAN = ["Customer", "net V", "Item 1", "Year", "Month", "net Q"]
SOP = ["SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "U Of M", "QTY",
       "Location Code", "Customer Number", "Customer Name", "Customer Class", "Extended Price", "Branch"]
SO = ["Date", "Branch", "Barcode", "Item Name", "Quantity", "Net Sales"]
C = "QA عميل تجريبي"

def sop(no, date, value, cust=C, item="QA-1", desc="QA صنف 1", qty="1", branch="ALX", custno="QA1"):
    return ["Invoice", no, date, item, desc, "CTN", qty, "L", custno, cust, "KA", value, branch]

def save(name, header, rows, formula=None):
    wb = Workbook(); ws = wb.active; ws.title = "Sheet1"
    ws.append(header)
    for r in rows: ws.append(r)
    if formula:  # openpyxl writes the formula with NO cached value (like a file never saved in Excel)
        ws[formula[0]] = formula[1]
    wb.save(name); print("wrote", name)

save("01_month_formats.xlsx", PLAN, [
    [C, 100, "QA صنف 1", 2026, "يناير", 1], [C, 100, "QA صنف 1", 2026, "فبراير", 1],
    [C, 100, "QA صنف 1", 2026, "آذار", 1], [C, 100, "QA صنف 1", 2026, "4", 1],
    [C, 100, "QA صنف 1", 2026, "2026-05", 1], [C, 100, "QA صنف 1", 2026, "Jun", 1]])
save("02_bad_month.xlsx", PLAN, [[C, 100, "QA صنف 1", 2026, "شهر غلط", 1]])
save("03_empty_year.xlsx", PLAN, [[C, 100, "QA صنف 1", None, "مارس", 1]])
save("04_empty_year_qa_2026.xlsx", PLAN, [[C, 100, "QA صنف 1", None, "مارس", 1]])
save("05a_full_month.xlsx", SOP, [sop(f"QA{i}", "2026-07-%02d" % (1 + i % 28), "100") for i in range(30)])
save("05b_partial_month.xlsx", SOP, [sop(f"QB{i}", "2026-07-10", "50") for i in range(2)])
save("06_form_vs_sheet.xlsx", SOP, [sop("QC1", "2026-08-05", "100"), sop("QC2", "2026-09-05", "100")])
save("07_year_2027.xlsx", SOP, [sop("QD1", "2027-01-15", "100")])
save("08_unknown_customer.xlsx", SOP, [sop("QE1", "2026-10-05", "77", cust="QA عميل جديد خالص", custno="QA9")])
save("09_reordered_columns.xlsx", ["Month", "net Q", "Customer", "Year", "Item 1", "net V"], [["مارس", 1, C, 2026, "QA صنف 1", 100]])
save("10_missing_value_column.xlsx", ["SOP Type", "SOP Number", "Document Date", "Item Number", "Item Description", "QTY", "Customer Name", "Branch"],
     [["Invoice", "QF1", "2026-10-05", "QA-1", "QA صنف 1", "1", C, "ALX"]])
save("11_formula_cells.xlsx", SOP, [sop("QG1", "2026-10-05", "100"), sop("QG2", "2026-10-06", None, qty="")], formula=("L3", "=L2*2"))
save("12_unknown_barcode.xlsx", SOP, [sop("QH1", "2026-10-07", "55", item="QA-NOT-IN-MASTER-999", desc="QA صنف مش موجود")])
save("13_fuzzy_near_match.xlsx", SOP, [sop("QI1", "2026-10-08", "33", cust="QA عميل تجريبى", custno="QA2")])
save("14_two_fathalla_cities.xlsx", SOP, [
    sop("QJ1", "2026-10-09", "10", cust="QA فتح الله جملة (الغردقة)", custno="QA3", branch="HRG"),
    sop("QJ2", "2026-10-09", "20", cust="QA فتح الله جملة (طنطا)", custno="QA4", branch="TNT")])
save("15_sellout_form_vs_sheet.xlsx", SO, [["2026-08-03", "QA فرع تجريبي", "6220000000001", "QA صنف 1", 1, 100],
                                         ["2026-09-03", "QA فرع تجريبي", "6220000000001", "QA صنف 1", 1, 100]])
