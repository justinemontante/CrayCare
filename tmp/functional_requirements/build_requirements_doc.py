from copy import deepcopy
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from lxml import etree


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "Deliverables" / "Chapters 1–3.docx"
OUTPUT = ROOT / "docs" / "Deliverables" / "Functional and Non-Functional Requirements.docx"

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}


def text_of(element):
    return " ".join(element.xpath(".//w:t/text()", namespaces=NS)).strip()


with ZipFile(SOURCE, "r") as source_zip:
    document_xml = source_zip.read("word/document.xml")
    root = etree.fromstring(document_xml)
    body = root.find("w:body", NS)
    children = list(body)

    start = next(
        i
        for i, child in enumerate(children)
        if text_of(child).upper().startswith("3.1 REQUIREMENTS ANALYSIS")
    )
    non_functional_heading = next(
        i
        for i, child in enumerate(children[start + 1 :], start + 1)
        if text_of(child).strip().upper() == "NON-FUNCTIONAL REQUIREMENTS MATRIX"
    )
    end = next(
        i
        for i, child in enumerate(children[non_functional_heading + 1 :], non_functional_heading + 1)
        if text_of(child).strip().upper().endswith("USE CASE DIAGRAM")
    )

    original_section = next(
        (deepcopy(child) for child in reversed(children) if child.tag == f"{{{W}}}sectPr"),
        None,
    )

    selected = [deepcopy(child) for child in children[start:end]]

    for child in list(body):
        body.remove(child)
    for child in selected:
        body.append(child)
    if original_section is not None:
        body.append(original_section)

    updated_xml = etree.tostring(
        root,
        xml_declaration=True,
        encoding="UTF-8",
        standalone="yes",
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(OUTPUT, "w", ZIP_DEFLATED) as output_zip:
        for item in source_zip.infolist():
            payload = updated_xml if item.filename == "word/document.xml" else source_zip.read(item.filename)
            output_zip.writestr(item, payload)


with ZipFile(OUTPUT, "r") as check_zip:
    check_root = etree.fromstring(check_zip.read("word/document.xml"))
    check_body = check_root.find("w:body", NS)
    all_text = "\n".join(text_of(child) for child in check_body)
    tables = check_body.findall("w:tbl", NS)

    required = (
        "REQUIREMENTS ANALYSIS",
        "Functional Requirements Matrix",
        "Non-Functional Requirements Matrix",
    )
    missing = [label for label in required if label not in all_text]
    forbidden = [label for label in ("DESIGN SPECIFICATIONS",) if label in all_text]
    if missing or forbidden or len(tables) < 3:
        raise RuntimeError(
            f"Verification failed: missing={missing}, forbidden={forbidden}, tables={len(tables)}"
        )

    print(f"Created: {OUTPUT}")
    print(f"Body blocks: {len(list(check_body))}")
    print(f"Tables preserved: {len(tables)}")
