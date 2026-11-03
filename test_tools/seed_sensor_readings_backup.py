"""Import a sensor-history workbook using the ESP's timestamp-based IDs."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import firebase_admin
from firebase_admin import credentials, firestore
from openpyxl import load_workbook


WORKBOOK_DEFAULT = Path(r"D:\Users\SLUMDUNK\Downloads\sensor_readings_backup.xlsx")
SERVICE_ACCOUNT = Path(__file__).with_name("serviceAccountKey.json")
LOCAL_TZ = ZoneInfo("Asia/Manila")
SENSOR_FIELDS = (
    ("temperature_c", "temperature"),
    ("ph_level", "ph_level"),
    ("dissolved_oxygen_mg_l", "dissolved_oxygen"),
    ("turbidity_ntu", "turbidity"),
)


def load_rows(workbook_path: Path) -> list[dict]:
    workbook = load_workbook(workbook_path, read_only=True, data_only=True)
    if "Estimated Data" not in workbook.sheetnames:
        raise ValueError("Workbook is missing the 'Estimated Data' sheet.")

    sheet = workbook["Estimated Data"]
    values = sheet.iter_rows(values_only=True)
    headers = next(values)
    columns = {str(name).strip(): index for index, name in enumerate(headers) if name}
    required = {"recorded_at_utc", *(source for source, _ in SENSOR_FIELDS)}
    if not required.issubset(columns):
        missing = ", ".join(sorted(required - columns.keys()))
        raise ValueError(f"Workbook is missing required columns: {missing}.")

    rows = []
    seen_timestamps = set()
    for row_number, cells in enumerate(values, start=2):
        timestamp_text = cells[columns["recorded_at_utc"]]
        if timestamp_text is None or str(timestamp_text).strip() == "":
            continue
        timestamp = datetime.fromisoformat(str(timestamp_text).replace("Z", "+00:00"))
        if timestamp.tzinfo is None:
            raise ValueError(f"Row {row_number} timestamp has no timezone.")
        timestamp = timestamp.astimezone(timezone.utc)
        timestamp_ms = int(timestamp.timestamp() * 1000)
        if timestamp_ms in seen_timestamps:
            raise ValueError(f"Duplicate workbook timestamp at row {row_number}.")
        seen_timestamps.add(timestamp_ms)

        data = {"recorded_at": timestamp}
        for source, target in SENSOR_FIELDS:
            raw_value = cells[columns[source]]
            value = float(raw_value)
            if value != value or value in (float("inf"), float("-inf")):
                raise ValueError(f"Invalid {source} value at row {row_number}.")
            data[target] = value

        local_time = timestamp.astimezone(LOCAL_TZ)
        rows.append({
            "date_key": local_time.strftime("%Y-%m-%d"),
            "entry_id": f"r_{timestamp_ms}",
            "timestamp_ms": timestamp_ms,
            "data": data,
        })

    if not rows:
        raise ValueError("Workbook contains no sensor readings.")
    rows.sort(key=lambda item: item["timestamp_ms"])
    return rows


def timestamp_ms(value) -> int | None:
    if not isinstance(value, datetime):
        return None
    aware = value.replace(tzinfo=value.tzinfo or timezone.utc).astimezone(timezone.utc)
    return int(aware.timestamp() * 1000)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, default=WORKBOOK_DEFAULT)
    parser.add_argument("--commit", action="store_true", help="Write the changes to Firestore.")
    args = parser.parse_args()
    if not args.file.is_file():
        raise FileNotFoundError(f"Workbook not found: {args.file}")
    if not SERVICE_ACCOUNT.is_file():
        raise FileNotFoundError(f"Firebase credentials not found: {SERVICE_ACCOUNT}")

    rows = load_rows(args.file)
    app = firebase_admin.initialize_app(credentials.Certificate(str(SERVICE_ACCOUNT)))
    try:
        db = firestore.client(app=app)
        assignment = db.collection("hardware_system").document("currentOwner").get()
        assignment_data = assignment.to_dict() or {}
        tank_id = assignment_data.get("tank_id")
        owner_uid = assignment_data.get("uid")
        if not isinstance(tank_id, str) or not tank_id.strip():
            raise ValueError("No tank is currently assigned in hardware_system/currentOwner.")

        tank_ref = db.collection("tanks").document(tank_id)
        tank = tank_ref.get()
        if not tank.exists:
            raise ValueError("The currently assigned tank document does not exist.")
        if owner_uid and tank.get("owner_uid") != owner_uid:
            raise ValueError("The current hardware owner does not match the assigned tank owner.")

        by_day: dict[str, list[dict]] = {}
        for row in rows:
            by_day.setdefault(row["date_key"], []).append(row)

        plans = []
        counts = {"already_standard": 0, "renamed": 0, "created": 0,
                  "kept_existing_timestamp": 0, "value_conflicts_kept_existing": 0}

        for date_key, day_rows in by_day.items():
            day_ref = tank_ref.collection("sensor_readings_history").document(date_key)
            entry_docs = day_ref.collection("entries").get()
            by_id = {doc.id: (doc.reference, doc.to_dict() or {}) for doc in entry_docs}
            by_time: dict[int, list[tuple[str, object, dict]]] = {}
            for doc in entry_docs:
                data = doc.to_dict() or {}
                captured_ms = timestamp_ms(data.get("recorded_at"))
                if captured_ms is not None:
                    by_time.setdefault(captured_ms, []).append((doc.id, doc.reference, data))

            parent_snap = day_ref.get()
            parent_data = parent_snap.to_dict() or {}
            processed_ids = parent_data.get("processed_entry_ids", [])
            processed_replacements = {}
            actions = []

            for row in day_rows:
                target_id = row["entry_id"]
                target = by_id.get(target_id)
                existing_at_time = by_time.get(row["timestamp_ms"], [])

                if target is not None:
                    target_data = target[1]
                    if timestamp_ms(target_data.get("recorded_at")) != row["timestamp_ms"]:
                        raise ValueError(f"Existing document {target_id} has a different timestamp.")
                    for old_id, old_ref, old_data in existing_at_time:
                        if old_id == target_id:
                            continue
                        if old_id.startswith("backup_est_"):
                            actions.append(("delete", old_ref, None))
                            processed_replacements[old_id] = target_id
                            counts["value_conflicts_kept_existing"] += any(
                                old_data.get(field) != row["data"][field]
                                for _, field in SENSOR_FIELDS
                            )
                    counts["already_standard"] += 1
                    continue

                imported_old = [entry for entry in existing_at_time
                                if entry[0].startswith("backup_est_")]
                other_existing = [entry for entry in existing_at_time
                                  if not entry[0].startswith("backup_est_")]

                if other_existing:
                    # A pre-existing non-import record at this time wins.
                    for old_id, old_ref, old_data in imported_old:
                        actions.append(("delete", old_ref, None))
                        processed_replacements[old_id] = other_existing[0][0]
                        if any(old_data.get(field) != row["data"][field]
                               for _, field in SENSOR_FIELDS):
                            counts["value_conflicts_kept_existing"] += 1
                    counts["kept_existing_timestamp"] += 1
                    continue

                if imported_old:
                    old_id, old_ref, old_data = imported_old[0]
                    # Keep only canonical sensor fields while moving the record
                    # to the same ID format the ESP creates.
                    standard_data = {"recorded_at": old_data.get("recorded_at")}
                    for _, field in SENSOR_FIELDS:
                        standard_data[field] = old_data[field]
                    actions.append(("create", day_ref.collection("entries").document(target_id), standard_data))
                    actions.append(("delete", old_ref, None))
                    processed_replacements[old_id] = target_id
                    for extra_id, extra_ref, _ in imported_old[1:]:
                        actions.append(("delete", extra_ref, None))
                        processed_replacements[extra_id] = target_id
                    counts["renamed"] += 1
                else:
                    actions.append(("create", day_ref.collection("entries").document(target_id), row["data"]))
                    counts["created"] += 1

            next_processed = []
            for entry_id in processed_ids if isinstance(processed_ids, list) else []:
                replacement = processed_replacements.get(entry_id, entry_id)
                if replacement not in next_processed:
                    next_processed.append(replacement)

            plans.append((date_key, day_ref, parent_snap.exists,
                          next_processed, actions))

        print({
            "mode": "commit" if args.commit else "dry-run",
            "destination": "tanks/{tankId}/sensor_readings_history/{dateKey}/entries/r_<capturedAtMs>",
            "workbook_rows": len(rows),
            **counts,
            "start_utc": rows[0]["data"]["recorded_at"].isoformat(),
            "end_utc": rows[-1]["data"]["recorded_at"].isoformat(),
            "tank": "currently assigned tank",
        })

        if not args.commit:
            print("Dry run only; pass --commit to create missing rows and rename imported entries.")
            return

        for _, day_ref, parent_exists, processed, actions in plans:
            if not actions and not (parent_exists and processed):
                continue
            batch = db.batch()
            if parent_exists and processed:
                batch.set(day_ref, {"processed_entry_ids": processed}, merge=True)
            for action, ref, data in actions:
                if action == "create":
                    batch.create(ref, data)
                else:
                    batch.delete(ref)
            batch.commit()

        print("Sensor-history import complete. ESP-style IDs prevent duplicate documents for matching timestamps.")
    finally:
        firebase_admin.delete_app(app)


if __name__ == "__main__":
    main()
