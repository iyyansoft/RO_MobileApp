"""Stock-entry spreadsheet for the 78 PDF-catalogue products.

  python scripts/stock_entry_template.py generate OUT.xlsx
      Builds the template from assets/product_pdfs/extracted/ (local, git-ignored
      supplier data). "New Stock Quantity" is left BLANK for manual entry; no
      quantity is ever filled in or assumed.

  python scripts/stock_entry_template.py read FILLED.xlsx OUT.json
      Reads the filled template. Only rows with a New Stock Quantity are taken;
      blank rows are skipped (never treated as 0). Anything that is not a whole
      number >= 0 is reported and nothing is written. Apply OUT.json with
      scripts/stock_entry_import.cjs (dry run first).
"""
import json
import re
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Protection, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "assets" / "product_pdfs" / "extracted"
SHEET = "Stock Entry"
CATEGORY_TITLES = {
    "systems": "RO Systems", "membranes": "Membranes", "filters": "Filters & Cartridges",
    "pumps": "Booster Pumps", "pipes": "Pipes & Tubing", "spares": "Spare Parts & Valves",
}
HEADERS = [
    ("Product Name", 44), ("SKU", 11), ("Category", 21), ("Dealer Price (₹)", 14), ("MRP (₹)", 12),
    ("Bulk Price (₹ / piece)", 17), ("Minimum Order Qty (normal)", 18), ("Bulk Pack Size / Minimum", 26),
    ("Current Stock", 12), ("New Stock Quantity", 16), ("Notes (optional)", 28), ("Product ID", 16),
]
COL = {name: i + 1 for i, (name, _) in enumerate(HEADERS)}
ENTRY_COLUMNS = ("New Stock Quantity", "Notes (optional)")


def product_id(sku):
    """Same id rule as scripts/pdf_catalog_import.cjs."""
    return "PDF_" + re.sub(r"[^A-Za-z0-9]+", "_", sku).upper()


def load_products():
    catalog = json.loads((DATA / "catalog_import.json").read_text(encoding="utf-8"))["products"]
    bulk = {p["sku"]: p for p in json.loads((DATA / "bulk_pricing.json").read_text(encoding="utf-8"))["products"]}
    rows = []
    for p in catalog:
        if p.get("status") != "import":
            continue
        b = bulk.get(p["sku"])
        if b and b.get("status") == "bulk":
            step = f"then +{b['step']}" if b["step"] == 1 else f"in packs of {b['step']}"
            bulk_price, bulk_pack = b["box_price"], f"{b['pack_label']} (min {b['min_qty']}, {step})"
        elif b:
            bulk_price, bulk_pack = "Held for review", "Not offered in Bulk Orders"
        else:
            bulk_price, bulk_pack = "—", "Not in Bulk Orders"
        rows.append({
            "Product Name": p["name"], "SKU": p["sku"],
            "Category": CATEGORY_TITLES.get(p["category_key"], p["category_key"]),
            "Dealer Price (₹)": p["dealer_price"], "MRP (₹)": p["mrp"],
            "Bulk Price (₹ / piece)": bulk_price,
            "Minimum Order Qty (normal)": p.get("pdf_qty_text") or "Not set in PDF",
            "Bulk Pack Size / Minimum": bulk_pack,
            "Current Stock": 0, "New Stock Quantity": None, "Notes (optional)": None,
            "Product ID": product_id(p["sku"]),
        })
    order = list(CATEGORY_TITLES.values())
    rows.sort(key=lambda r: (order.index(r["Category"]) if r["Category"] in order else 99, r["SKU"]))
    return rows


def generate(out):
    rows = load_products()
    if len(rows) != 78:
        raise SystemExit(f"expected 78 products, found {len(rows)}")
    wb = Workbook()
    ws = wb.active
    ws.title = SHEET
    thin = Side(style="thin", color="CBD5E1")
    head_fill, entry_fill = PatternFill("solid", fgColor="0B3D91"), PatternFill("solid", fgColor="FFF7D6")
    for c, (name, width) in enumerate(HEADERS, start=1):
        cell = ws.cell(row=1, column=c, value=name)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="B45309") if name in ENTRY_COLUMNS else head_fill
        cell.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        cell.border = Border(top=thin, bottom=thin, left=thin, right=thin)
        ws.column_dimensions[get_column_letter(c)].width = width
    ws.row_dimensions[1].height = 36
    for r, row in enumerate(rows, start=2):
        for name, _ in HEADERS:
            cell = ws.cell(row=r, column=COL[name], value=row[name])
            cell.border = Border(top=thin, bottom=thin, left=thin, right=thin)
            cell.alignment = Alignment(vertical="center", wrap_text=name in ("Product Name", "Bulk Pack Size / Minimum"))
            if name in ("Dealer Price (₹)", "MRP (₹)") or (name == "Bulk Price (₹ / piece)" and isinstance(row[name], (int, float))):
                cell.number_format = "₹#,##0.00"
            if name in ENTRY_COLUMNS:
                cell.fill = entry_fill
                cell.protection = Protection(locked=False)
    last = len(rows) + 1
    stock_col = get_column_letter(COL["New Stock Quantity"])
    dv = DataValidation(type="whole", operator="between", formula1="0", formula2="1000000", allow_blank=True,
                        showErrorMessage=True, errorTitle="Stock quantity",
                        error="Enter the actual stock as a whole number (0 or more), or leave it blank.")
    dv.add(f"{stock_col}2:{stock_col}{last}")
    ws.add_data_validation(dv)
    ws.freeze_panes = "C2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(HEADERS))}{last}"
    ws.protection.sheet = True          # no password: prevents accidental edits only
    ws.protection.autoFilter = False
    ws.protection.sort = False

    info = wb.create_sheet("Instructions")
    lines = [
        ("NeeroPlus – stock entry for the 78 new PDF-catalogue products", True),
        ("", False),
        ("1. Fill only the yellow column 'New Stock Quantity' with the counted stock (whole number, 0 or more).", False),
        ("2. Leave it BLANK for any product you have not counted. Blank is never treated as 0 or any other number.", False),
        ("3. Do not change the other columns; they are locked. 'Product ID' and 'SKU' are used to match each row.", False),
        ("4. 'Current Stock' is 0: these products are created with stock 0 by the catalogue import and are", False),
        ("   NOT in production yet. Until stock is entered they show as Out of Stock and cannot be ordered.", False),
        ("5. Bulk Orders: a product is orderable in bulk only after its stock is entered and verified,", False),
        ("   and bulk prices are applied only after that (see the release runbook).", False),
        ("6. 'Held for review' bulk items are not offered in Bulk Orders (pack type / price range needs review).", False),
        ("7. Two PDF items are not in this list because their PDF prices are ranges: DOM-53, DOM-54.", False),
        ("", False),
        ("Return the filled file. It is read with: python scripts/stock_entry_template.py read <file> <out.json>", False),
        ("then checked with a dry run (scripts/stock_entry_import.cjs) before anything is written.", False),
    ]
    for i, (text, bold) in enumerate(lines, start=1):
        info.cell(row=i, column=1, value=text).font = Font(bold=bold, size=13 if bold else 11)
    info.column_dimensions["A"].width = 110

    summary = wb.create_sheet("Summary")
    summary.append(["Category", "Products", "With bulk offer", "Bulk held for review"])
    for cat in CATEGORY_TITLES.values():
        cat_rows = [r for r in rows if r["Category"] == cat]
        summary.append([cat, len(cat_rows),
                        sum(isinstance(r["Bulk Price (₹ / piece)"], (int, float)) for r in cat_rows),
                        sum(r["Bulk Price (₹ / piece)"] == "Held for review" for r in cat_rows)])
    summary.append(["Total", len(rows), sum(isinstance(r["Bulk Price (₹ / piece)"], (int, float)) for r in rows),
                    sum(r["Bulk Price (₹ / piece)"] == "Held for review" for r in rows)])
    for c in summary[1]:
        c.font = Font(bold=True)
    for c in summary[summary.max_row]:
        c.font = Font(bold=True)
    for col, width in zip("ABCD", (24, 12, 16, 20)):
        summary.column_dimensions[col].width = width
    wb.active = 0
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    wb.save(out)
    print(f"Wrote {out}: {len(rows)} products; New Stock Quantity left blank.")


def read(filled, out):
    ws = load_workbook(filled, data_only=True)[SHEET]
    header = [c.value for c in ws[1]]
    missing = [h for h, _ in HEADERS if h not in header]
    if missing:
        raise SystemExit(f"not the stock-entry template (missing columns: {missing})")
    idx = {h: header.index(h) for h, _ in HEADERS}
    entries, errors, blank = [], [], 0
    for r, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        if not any(v not in (None, "") for v in row):
            continue
        value = row[idx["New Stock Quantity"]]
        if value is None or str(value).strip() == "":
            blank += 1
            continue
        text = str(value).strip()
        if isinstance(value, float) and value.is_integer():
            text = str(int(value))
        if not re.fullmatch(r"\d+", text):
            errors.append(f"row {r} ({row[idx['SKU']]}): '{value}' is not a whole number >= 0")
            continue
        entries.append({"product_id": row[idx["Product ID"]], "sku": row[idx["SKU"]], "name": row[idx["Product Name"]],
                        "new_stock": int(text), "note": row[idx["Notes (optional)"]] or ""})
    skus = [e["sku"] for e in entries]
    errors += [f"SKU {s} appears more than once" for s in sorted({s for s in skus if skus.count(s) > 1})]
    if errors:
        print("Not written. Fix these rows:\n  " + "\n  ".join(errors))
        sys.exit(1)
    Path(out).write_text(json.dumps({"source": str(filled), "entries": entries}, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(entries)} stock entries read, {blank} left blank (not changed). Wrote {out}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "generate":
        generate(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "read":
        read(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(2)
