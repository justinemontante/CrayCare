from docx import Document
from docx.table import Table

for path in ["docs/Data Dictionary.docx", "docs/Chapters 1–3.docx"]:
    document = Document(path)
    print(f"FILE {path}")
    latest_heading = ""
    for block in document.iter_inner_content():
        if isinstance(block, Table):
            fields = [row.cells[0].text.strip() for row in block.rows[1:] if row.cells]
            if latest_heading.lower().startswith("table:") or "data dictionary" in latest_heading.lower():
                print(f"{latest_heading} => {', '.join(fields)}")
            continue
        text = block.text.strip()
        if text:
            latest_heading = text
