from __future__ import annotations

import re
from pathlib import Path

from docx import Document

ROOT = Path(__file__).resolve().parents[1]
extensions = {".dart", ".js", ".py", ".cpp", ".h", ".ino"}
files = []
for folder in ("lib", "functions", "esp"):
    files.extend(
        path for path in (ROOT / folder).rglob("*")
        if path.is_file()
        and path.suffix.lower() in extensions
        and "node_modules" not in path.parts
        and "build" not in path.parts
        and ".pio" not in path.parts
        and ".dart_tool" not in path.parts
        and ".venv" not in path.parts
        and "venv" not in path.parts
    )
files.append(ROOT / "firestore.rules")
corpus = "\n".join(path.read_text(encoding="utf-8", errors="ignore") for path in files)

doc_path = ROOT / "docs" / "Data Dictionary.pending.docx"
if not doc_path.exists():
    doc_path = ROOT / "docs" / "Data Dictionary.docx"
document = Document(doc_path)
checked = []
missing = []
invalid = []
for table in document.tables:
    for row in table.rows[1:]:
        field_name = row.cells[0].text.strip()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", field_name):
            invalid.append(field_name)
            continue
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(field_name)}(?![A-Za-z0-9_])", corpus):
            checked.append(field_name)
        else:
            missing.append(field_name)

print(f"source_files={len(files)}")
print(f"exact_fields_found={len(checked)}")
print(f"exact_fields_not_found={len(missing)}")
print(f"invalid_grouped_field_names={len(invalid)}")
for name in missing:
    print(name)
for name in invalid:
    print(f"GROUPED::{name}")
