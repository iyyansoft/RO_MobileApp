"""Product-information spreadsheet (Description / Specifications / Key Features).

  python scripts/product_info_template.py generate CURRENT.json OUT.xlsx
      CURRENT.json comes from `node scripts/product_info_import.cjs --export` (read only).
      Every product is listed with what is saved now. The three "New ..." columns
      are left BLANK for manual entry; nothing is filled in, copied or invented.

  python scripts/product_info_template.py read FILLED.xlsx OUT.json
      Reads the filled sheet. Only "New ..." cells that have text are taken; a blank
      cell means "keep what is saved" (never "clear it"). Apply OUT.json with
      scripts/product_info_import.cjs (dry run first). The format of each cell
      (one "Name: Value" per specification line, one feature per line) is checked
      there, with the same rules as the Admin Dashboard.
"""
import json
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Protection, Side
from openpyxl.utils import get_column_letter

SHEET = "Product Information"
HEADERS = [
    ("Product ID", 18), ("SKU", 13), ("Product Name", 34), ("Category", 18),
    ("Current Description", 40), ("Current Specifications", 34), ("Current Key Features", 32),
    ("New Description", 44), ("New Specifications", 38), ("New Key Features", 36), ("Notes (optional)", 26),
]
COL = {name: i + 1 for i, (name, _) in enumerate(HEADERS)}
ENTRY = ("New Description", "New Specifications", "New Key Features", "Notes (optional)")
FIELD = {"New Description": "description", "New Specifications": "specs", "New Key Features": "features"}


def generate(current, out):
    products = json.loads(Path(current).read_text(encoding="utf-8"))["products"]
    wb = Workbook()
    ws = wb.active
    ws.title = SHEET
    thin = Side(style="thin", color="CBD5E1")
    border = Border(top=thin, bottom=thin, left=thin, right=thin)
    entry_fill, current_fill = PatternFill("solid", fgColor="FFF7D6"), PatternFill("solid", fgColor="F1F5F9")
    for c, (name, width) in enumerate(HEADERS, start=1):
        cell = ws.cell(row=1, column=c, value=name)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="B45309" if name in ENTRY else "0B3D91")
        cell.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        cell.border = border
        ws.column_dimensions[get_column_letter(c)].width = width
    ws.row_dimensions[1].height = 34
    values = {
        "Product ID": "product_id", "SKU": "sku", "Product Name": "name", "Category": "category",
        "Current Description": "description", "Current Specifications": "specs", "Current Key Features": "features",
    }
    for r, p in enumerate(products, start=2):
        for name, _ in HEADERS:
            text = p.get(values[name]) if name in values else None
            cell = ws.cell(row=r, column=COL[name], value=(text or ("(none)" if name.startswith("Current") else None)))
            cell.border = border
            cell.alignment = Alignment(vertical="top", wrap_text=True)
            if name in ENTRY:
                cell.fill = entry_fill
                cell.protection = Protection(locked=False)
            elif name.startswith("Current"):
                cell.fill = current_fill
                if not text:
                    cell.font = Font(italic=True, color="94A3B8")
    last = len(products) + 1
    ws.freeze_panes = "D2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(HEADERS))}{last}"
    ws.protection.sheet = True          # no password: prevents accidental edits of the current values only
    ws.protection.autoFilter = False
    ws.protection.sort = False
    ws.protection.formatRows = False
    ws.protection.formatColumns = False

    info = wb.create_sheet("Instructions")
    lines = [
        ("NeeroPlus – product information (Description, Specifications, Key Features)", True),
        ("", False),
        ("Fill only the yellow columns, with the real information for the product. Leave a cell BLANK to keep what is saved.", False),
        ("A blank cell never clears or changes anything. Nothing is filled in automatically.", False),
        ("", False),
        ("New Description: plain text. Several lines are fine (Alt+Enter starts a new line in a cell).", False),
        ("New Specifications: one specification per line, written as  Name: Value", False),
        ("      e.g.   Body: ABS plastic   (Alt+Enter)   Storage tank: 10 L   (Alt+Enter)   Voltage: 24V", False),
        ("      Every line needs a name and a value; a line without them is reported and nothing is saved.", False),
        ("New Key Features: one feature per line (Alt+Enter between features). Commas stay inside a feature.", False),
        ("", False),
        ("A filled New cell REPLACES that part of the product's information (the whole description, all", False),
        ("specifications or all features). Products that already have information are shown in the grey", False),
        ("'Current' columns; the dry run lists every replacement with the old text before anything is saved.", False),
        ("Do not change Product ID, SKU or the grey columns; they are locked and used to match each row.", False),
        ("", False),
        ("Return the filled file. It is read with: python scripts/product_info_template.py read <file> <out.json>", False),
        ("then checked with a dry run (scripts/product_info_import.cjs) before anything is written.", False),
    ]
    for i, (text, bold) in enumerate(lines, start=1):
        info.cell(row=i, column=1, value=text).font = Font(bold=bold, size=13 if bold else 11)
    info.column_dimensions["A"].width = 115

    summary = wb.create_sheet("Summary")
    summary.append(["Category", "Products", "With description", "With specifications", "With key features"])
    cats = list(dict.fromkeys(p["category"] for p in products))
    for cat in cats + ["Total"]:
        rows = products if cat == "Total" else [p for p in products if p["category"] == cat]
        summary.append([cat, len(rows), sum(bool(p["description"]) for p in rows),
                        sum(bool(p["specs"]) for p in rows), sum(bool(p["features"]) for p in rows)])
    for c in list(summary[1]) + list(summary[summary.max_row]):
        c.font = Font(bold=True)
    for col, width in zip("ABCDE", (24, 11, 17, 20, 18)):
        summary.column_dimensions[col].width = width
    wb.active = 0
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    wb.save(out)
    print(f"Wrote {out}: {len(products)} products; New columns left blank.")


def read(filled, out):
    ws = load_workbook(filled, data_only=True)[SHEET]
    header = [c.value for c in ws[1]]
    missing = [h for h, _ in HEADERS if h not in header]
    if missing:
        raise SystemExit(f"not the product-information template (missing columns: {missing})")
    idx = {h: header.index(h) for h, _ in HEADERS}
    entries, errors, untouched = [], [], 0
    for r, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        if not any(v not in (None, "") for v in row):
            continue
        entry = {"row": r, "product_id": row[idx["Product ID"]], "sku": row[idx["SKU"]], "name": row[idx["Product Name"]]}
        for col, field in FIELD.items():
            value = row[idx[col]]
            if value is not None and str(value).strip():
                entry[field] = str(value).replace("\r\n", "\n").strip()
        if not any(f in entry for f in FIELD.values()):
            untouched += 1
            continue
        if not entry["product_id"] or not entry["sku"]:
            errors.append(f"row {r}: Product ID and SKU must not be empty")
            continue
        entry["note"] = row[idx["Notes (optional)"]] or ""
        entries.append(entry)
    ids = [e["product_id"] for e in entries]
    errors += [f"Product {p} appears more than once" for p in sorted({p for p in ids if ids.count(p) > 1})]
    if errors:
        print("Not written. Fix these rows:\n  " + "\n  ".join(errors))
        sys.exit(1)
    Path(out).write_text(json.dumps({"source": str(filled), "entries": entries}, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(entries)} products with new information, {untouched} left blank (not changed). Wrote {out}")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "generate":
        generate(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "read":
        read(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(2)
