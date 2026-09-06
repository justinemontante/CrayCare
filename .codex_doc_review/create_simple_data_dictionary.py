from __future__ import annotations

import copy
import importlib.util
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(r"C:\Users\SLUMDUNK\Desktop\Crayfish Flutter UI\craycare")
SOURCE = ROOT / ".codex_doc_review" / "update_data_dictionary.py"
PUP_TEMPLATE = ROOT / "docs" / "Chapters 1–3.docx"
OUTPUT = ROOT / "docs" / "Data Dictionary.docx"

TABLE_NAMES = {
    "users/{uid}": "Users",
    "users/{uid}/notification_settings/preferences": "Notification Settings",
    "users/{uid}/notif_markers/{key}": "Notification Markers",
    "hardware_system/currentOwner": "Current Hardware Owner",
    "tanks/{tankId}": "Tanks",
    "tanks/{tankId}/sensor_readings/latest": "Latest Sensor Readings",
    "tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}": "Daily Sensor Summaries",
    "tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}": "Sensor History Entries",
    "tanks/{tankId}/sensors/{sensorName}": "Sensor Thresholds",
    "tanks/{tankId}/actuators/{deviceId}": "Actuators",
    "tanks/{tankId}/actuator_logs/{logId}": "Actuator Logs",
    "tanks/{tankId}/feeder/status": "Feeder Status",
    "tanks/{tankId}/feeder_schedules/{scheduleId}": "Feeder Schedules",
    "tanks/{tankId}/feeder_logs/{logId}": "Feeding History",
    "tanks/{tankId}/feeder_commands/{commandId}": "Feeder Commands",
    "tanks/{tankId}/feeder_notification_receipts/{logId}": "Feeder Notification Records",
    "tanks/{tankId}/water_quality_anomaly_detections/{detectionId}": "Water Quality Anomaly Detections",
    "tanks/{tankId}/batches/{batchId}": "Production Batches",
    "tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}": "Sampling Records",
    "tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}": "Mortality Records",
    "tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}": "Harvest Records",
    "notifications/{notifId}": "Notifications",
    "sensorIngestion/current": "Current ESP32 Sensor Data",
    "sensorIngestion/current/history/{docId}": "ESP32 Sensor Data History",
}


def load_collections():
    spec = importlib.util.spec_from_file_location("dictionary_source", SOURCE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    collections = copy.deepcopy(module.COLLECTIONS)
    daily_path = "tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}"
    entry_path = daily_path + "/entries/{docId}"
    esp_history_path = "sensorIngestion/current/history/{docId}"
    sensor_specs = (
        ("temp", "temperature", "degrees Celsius"),
        ("pH", "pH", "pH"),
        ("DO", "dissolved oxygen", "mg/L"),
        ("turbidity", "turbidity", "NTU"),
        ("waterLevel", "water level", "centimeters"),
    )
    for collection in collections:
        path = collection["path"]
        if path == daily_path:
            kept = [row for row in collection["fields"] if "/" not in row[0]]
            expanded = []
            for prefix, label, unit in sensor_specs:
                expanded.extend(
                    [
                        (
                            f"{prefix}_min",
                            "number",
                            f"Optional; {unit}",
                            f"Lowest daily {label} reading.",
                        ),
                        (
                            f"{prefix}_max",
                            "number",
                            f"Optional; {unit}",
                            f"Highest daily {label} reading.",
                        ),
                        (
                            f"{prefix}_avg",
                            "number",
                            f"Optional; {unit}",
                            f"Average daily {label} reading.",
                        ),
                        (
                            f"{prefix}_sum",
                            "number",
                            "Optional",
                            f"Sum used to calculate the daily average for {label}.",
                        ),
                        (
                            f"{prefix}_count",
                            "number",
                            "Optional",
                            f"Number of valid {label} readings included in the daily summary.",
                        ),
                    ]
                )
            # Keep the summary-control fields first and updated_at last.
            collection["fields"] = kept[:-1] + expanded + kept[-1:]
        elif path in (entry_path, esp_history_path):
            kept = []
            for row in collection["fields"]:
                name = row[0]
                if "," in name or "/" in name or name == "sensor MIN/MAX/AVG fields":
                    continue
                kept.append(row)
            expanded = []
            for prefix, label, unit in sensor_specs:
                expanded.extend(
                    [
                        (
                            f"{prefix}_min",
                            "number",
                            unit,
                            f"Lowest {label} reading in the ten-minute period.",
                        ),
                        (
                            f"{prefix}_max",
                            "number",
                            unit,
                            f"Highest {label} reading in the ten-minute period.",
                        ),
                        (
                            f"{prefix}_avg",
                            "number",
                            unit,
                            f"Average {label} reading in the ten-minute period.",
                        ),
                    ]
                )
            if path == entry_path:
                # Sensor fields are followed by the optional feed values and recorded_at.
                collection["fields"] = expanded + kept
            else:
                # ESP identity/time fields remain before the sensor values; routing fields remain after them.
                split = next(
                    (i for i, row in enumerate(kept) if row[0] == "routing_status"),
                    len(kept),
                )
                collection["fields"] = kept[:split] + expanded + kept[split:]
    return collections


EXACT = {
    "Canonical profile-image URL. photoUrl may remain only as a legacy alias.": "Main link to the user's profile image. photoUrl is kept only so older app versions can still read it.",
    "Stores idempotency markers used by scheduled checks so that the same reminder is not created repeatedly.": "Stores records that prevent the same scheduled reminder from being created more than once.",
    "A valid unassigned state uses both uid and tank_id as null. Disabling the assigned owner clears this document atomically.": "When no owner is assigned, both uid and tank_id are null. If the assigned owner is disabled, both values are cleared together.",
    "Latest routed sensor snapshot used by the live dashboard. It is updated from the assigned ESP32's staging document.": "Stores the newest sensor readings shown on the live dashboard. The values come from the ESP32 assigned to the tank.",
    "Original sensor capture time preserved during routing.": "Time when the ESP32 collected the sensor reading.",
    "Daily summary document used for efficient long-range analytics. Only complete and sanitized summaries are consumed by the optimized reader.": "Stores the daily sensor summary used for longer analytics ranges. The app reads it only after the summary is complete and invalid values have been removed.",
    "Confirms invalid sentinel and non-finite values have been removed.": "Shows that invalid sensor values have already been removed from the summary.",
    "Entry IDs already included, used for idempotent summary maintenance.": "IDs of readings already included, preventing the same reading from being counted twice.",
    "Audit record for actuator operations.": "Stores the history of pump and aerator actions.",
    "True only for a completed latest occurrence; not the authoritative outcome.": "Older field that becomes true only when the latest feeding was completed. Use last_outcome for the latest result.",
    "Creation/edit/re-enable time; prevents earlier occurrences from being marked missed.": "Time the schedule was created, edited, or enabled again. Earlier schedule times will not be marked as missed.",
    "Reconciled outcome of the latest applicable occurrence.": "Latest confirmed result of the schedule.",
    "Append-only audit log for manual, scheduled, missed, blocked, skipped, failed, and completed feeding events.": "Stores feeding history for manual and scheduled feeding, including missed, blocked, skipped, failed, and completed results. Saved history records cannot be edited or deleted by the app.",
    "Original schedule time shown in the audit record.": "Scheduled feeding time saved in the history record.",
    "Original occurrence time retained through offline retries.": "Original scheduled time, even if the device sends the result later after reconnecting.",
    "Servo-cycle estimate; not scale-measured proof of actual mass.": "Estimated amount based on the feeder motor cycle. It is not an exact weight measured by a scale.",
    "Explains the basis of the estimated dispensed amount.": "Shows that the dispensed amount was estimated from the feeder motor cycle.",
    "Authoritative request-creation time.": "Official time when the feeding request was created.",
    "Server-only at-most-once claim used to prevent duplicate push attempts for feeder outcome logs.": "Backend record that prevents the same feeding-result push notification from being sent more than once.",
    "Time the backend claimed the notification attempt.": "Time when the backend reserved this feeding result for one notification attempt.",
    "A receipt proves that the push attempt was claimed, not that the device received the FCM message. The notification inbox record remains available.": "This record confirms that the backend attempted the push notification. It does not guarantee that the phone received it. The notification is still saved in the app inbox.",
    "Raw Random Forest class when model inference is applied.": "Water-quality class produced by the Random Forest model.",
    "Deterministic rolling-risk safety floor used by the interpretation layer.": "Optional rule result used as an additional safety check when recent readings show risk.",
    "Distinguishes trained model output, deterministic fallback, insufficient data, or stale data.": "Shows whether the result came from the trained model, a backup rule, insufficient readings, or old readings.",
    "Algorithm recorded for traceability.": "Name of the method used to produce the assessment.",
    "Availability and freshness classification of the input history.": "Shows whether enough recent sensor history was available for the assessment.",
    "Sortable processing timestamp used by history queries.": "Numeric processing time used to arrange assessment records in order.",
    "Inference requires at least six valid contiguous ten-minute records. A newest source record older than 20 minutes produces Insufficient/stale instead of inferring a current condition. Feed level is not a WQA feature.": "The assessment needs at least six valid ten-minute records in a row. If the newest reading is more than 20 minutes old, the result becomes Insufficient or Stale. Feed level is not included in the Water Quality Assessment.",
    "User notification inbox record. Deterministic IDs are used where duplicate backend events must collapse into one notification.": "Stores a notification shown in the user's inbox. A fixed ID is used when needed so the same backend event creates only one notification.",
    "Five-second ESP32 staging snapshot. Cloud Functions validate its capture-time assignment before routing it to the active tank.": "Temporary five-second sensor record received from the ESP32. The backend checks the owner and tank assignment before saving it under the active tank.",
    "Assignment identity used to reject stale or cross-owner payloads.": "Owner and tank assignment used to reject data from an old or different owner.",
    "Ten-minute ESP32 aggregate staging record. Matching assignments are routed to tank history; mismatched or unbound records remain quarantined.": "Temporary ten-minute sensor summary received from the ESP32. Correctly assigned data is saved in the tank history; unassigned or mismatched data stays here and is not added to a tank.",
    "Capture-time assignment identity.": "Owner and tank assignment recorded when the sensor data was collected.",
    "Routing result when the payload cannot be safely assigned.": "Result used when the data cannot be safely assigned to a tank.",
    "Reason the payload remains in staging.": "Reason the data remains in the temporary receiving area.",
}


REPLACEMENTS = (
    (
        "legacy timestamp forms remain readable",
        "older timestamp formats can still be read",
    ),
    ("Legacy compatibility", "For older app versions"),
    ("Epoch milliseconds", "milliseconds since January 1, 1970"),
    ("epoch ms", "milliseconds since January 1, 1970"),
    ("UTC epoch milliseconds", "UTC time stored as milliseconds"),
    ("UTC epoch seconds/ms by implementation", "UTC time stored as a number"),
    ("derived from", "calculated from"),
    ("Operational hopper-level snapshot", "Feed level reading"),
)


def simple(text):
    if not isinstance(text, str):
        return text
    text = EXACT.get(text, text)
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    return text


def shade(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=55, start=90, bottom=55, end=90):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for tag, value in (
        ("top", top),
        ("start", start),
        ("bottom", bottom),
        ("end", end),
    ):
        node = tc_mar.find(qn(f"w:{tag}"))
        if node is None:
            node = OxmlElement(f"w:{tag}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def cant_split(row):
    tr_pr = row._tr.get_or_add_trPr()
    element = OxmlElement("w:cantSplit")
    tr_pr.append(element)


def set_repeat_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    element = OxmlElement("w:tblHeader")
    element.set(qn("w:val"), "true")
    tr_pr.append(element)


def set_table_widths(table, widths):
    table.autofit = False
    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(int(width.inches * 1440)))
        grid.append(col)
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(int(sum(w.inches for w in widths) * 1440)))
    tbl_w.set(qn("w:type"), "dxa")
    for row in table.rows:
        for cell, width in zip(row.cells, widths):
            cell.width = width
            tc_w = cell._tc.get_or_add_tcPr().find(qn("w:tcW"))
            if tc_w is not None:
                tc_w.set(qn("w:w"), str(int(width.inches * 1440)))
                tc_w.set(qn("w:type"), "dxa")


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend([begin, instr, end])


def style_cell(cell, *, header=False):
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_margins(cell)
    for paragraph in cell.paragraphs:
        paragraph.paragraph_format.space_before = Pt(0)
        paragraph.paragraph_format.space_after = Pt(0)
        paragraph.paragraph_format.line_spacing = 1.0
        paragraph.paragraph_format.keep_with_next = header
        for run in paragraph.runs:
            run.font.name = "Arial"
            run.font.size = Pt(8.2)
            run.font.bold = header
            run.font.color.rgb = RGBColor(0, 0, 0)


def build():
    collections = load_collections()
    for item in collections:
        if item.get("section") == "9. ESP32 Sensor-Ingestion Staging":
            item["section"] = "9. ESP32 Data Receiving Area"
    # Start from the thesis document so the PUP header, page frame, footer,
    # paper size, and margins remain exactly the same.
    doc = Document(PUP_TEMPLATE)
    body = doc._element.body
    section_properties = body.sectPr
    for child in list(body):
        if child is not section_properties:
            body.remove(child)
    section = doc.sections[0]

    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Arial"
    normal.font.size = Pt(10.5)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.15
    for name, size, before, after, color in (
        ("Title", 16, 0, 12, "000000"),
        ("Heading 1", 12, 12, 6, "000000"),
        ("Heading 2", 11, 8, 4, "000000"),
    ):
        try:
            st = styles[name]
        except KeyError:
            st = styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
        st.font.name = "Arial"
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.color.rgb = RGBColor.from_string(color)
        st.paragraph_format.space_before = Pt(before)
        st.paragraph_format.space_after = Pt(after)
        st.paragraph_format.keep_with_next = True

    title = doc.add_paragraph(style="Title")
    title.alignment = WD_ALIGN_PARAGRAPH.LEFT
    title.add_run("Data Dictionary")
    intro = doc.add_paragraph()
    intro.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    intro.add_run(
        "This data dictionary presents the information stored in the CrayCare Cloud Firestore database. "
        "Each table identifies the field name, data type, description, and required or default value. "
        "It explains in simple terms how the mobile application, backend services, and ESP32 hardware use each field."
    )
    intro2 = doc.add_paragraph()
    intro2.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    intro2.add_run(
        "The database uses common data types such as string, number, boolean, timestamp, array, map, and null. "
        "The table names are written in a readable form, while the field names remain exactly as they appear in the system."
    )

    for item in collections:
        collection_title = doc.add_paragraph()
        collection_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
        collection_title.paragraph_format.keep_with_next = True
        collection_title.paragraph_format.space_before = Pt(10)
        collection_title.paragraph_format.space_after = Pt(6)
        title_run = collection_title.add_run(f"Table: {item['path']}")
        title_run.bold = True
        title_run.font.size = Pt(10.5)

        table = doc.add_table(rows=1, cols=4)
        table.style = "Table Grid"
        table.alignment = WD_TABLE_ALIGNMENT.CENTER
        headers = ["Field Name", "Data Type", "Description", "Constraints / Default"]
        for cell, text in zip(table.rows[0].cells, headers):
            cell.text = text
            style_cell(cell, header=True)
        cant_split(table.rows[0])
        set_repeat_header(table.rows[0])

        for field, dtype, constraints, description in item["fields"]:
            cells = table.add_row().cells
            values = [field, simple(dtype), simple(description), simple(constraints)]
            for cell, value in zip(cells, values):
                cell.text = str(value)
                style_cell(cell)
            cant_split(table.rows[-1])

        # Keep the table inside the narrower content area of the PUP page frame.
        set_table_widths(
            table, [Inches(1.10), Inches(0.85), Inches(2.60), Inches(1.35)]
        )
        after = doc.add_paragraph()
        after.paragraph_format.space_after = Pt(2)
        if item.get("note"):
            note = doc.add_paragraph()
            note.paragraph_format.space_before = Pt(3)
            note.paragraph_format.space_after = Pt(5)
            lead = note.add_run("Note: ")
            lead.bold = True
            note.add_run(simple(item["note"]))

    doc.core_properties.title = "Data Dictionary"
    doc.core_properties.subject = "CrayCare Cloud Firestore Data Dictionary"
    doc.core_properties.author = "CrayCare"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    try:
        doc.save(OUTPUT)
        saved_to = OUTPUT
    except PermissionError:
        saved_to = OUTPUT.with_name("Data Dictionary.pending.docx")
        doc.save(saved_to)
    print(saved_to)
    print(f"tables={len(doc.tables)}")


if __name__ == "__main__":
    build()
