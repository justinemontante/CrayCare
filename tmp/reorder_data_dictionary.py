"""Reorder Data Dictionary tables: users, tanks, notification_settings,
notifications, then the rest in original order. Renumbers Table captions."""

from docx import Document

SRC = "docs/Deliverables/Data Dictionary.docx"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

WANT = [
    "users",
    "tanks",
    "notification_settings",
    "notifications",
    "hardware_assignments",
    "sensor_thresholds",
    "sensor_readings_history",
    "sensor_readings",
    "actuators",
    "actuator_logs",
    "feeder_status",
    "feeder_schedules",
    "feeder_schedule_days",
    "feeder_commands",
    "feeder_logs",
    "water_quality_anomaly_detections",
    "water_quality_anomaly_contributors",
    "batches",
    "sampling_records",
    "mortality_records",
    "harvest_records",
]

HAVE = [
    "users",
    "notification_settings",
    "tanks",
    "hardware_assignments",
    "notifications",
    "sensor_thresholds",
    "sensor_readings_history",
    "sensor_readings",
    "actuators",
    "actuator_logs",
    "feeder_status",
    "feeder_schedules",
    "feeder_schedule_days",
    "feeder_commands",
    "feeder_logs",
    "water_quality_anomaly_detections",
    "water_quality_anomaly_contributors",
    "batches",
    "sampling_records",
    "mortality_records",
    "harvest_records",
]


def texts(el):
    return "".join(n.text or "" for n in el.findall(f".//{{{W}}}t"))


doc = Document(SRC)
body = doc.element.body
elems = list(body)

triples = []
for idx, el in enumerate(elems):
    if not el.tag.endswith("}tbl"):
        continue
    prev_ps = [e for e in elems[:idx] if e.tag.endswith("}p")]
    num_p, name_p = prev_ps[-2], prev_ps[-1]
    assert texts(num_p).strip().startswith("Table "), texts(num_p)
    assert texts(name_p).strip().endswith(" Table"), texts(name_p)
    name = texts(name_p).strip()[: -len(" Table")]
    triples.append((num_p, name_p, el, name))

assert [t[3] for t in triples] == HAVE, [t[3] for t in triples]
by_name = {t[3]: t for t in triples}
ordered = [by_name[n] for n in WANT]

for el in list(body):
    if el.tag.endswith("}tbl") or (
        el.tag.endswith("}p")
        and (
            texts(el).strip().startswith("Table ")
            or texts(el).strip().endswith(" Table")
        )
        and el is not elems[0]
    ):
        body.remove(el)

anchor = list(body).index(elems[0]) + 1
for n, (num_p, name_p, tbl, _name) in enumerate(ordered, 1):
    runs = num_p.findall(f".//{{{W}}}r")
    assert runs, "caption has no runs"
    t_el = runs[0].find(f"{{{W}}}t")
    t_el.text = f"Table {n}"
    for r in runs[1:]:
        t2 = r.find(f"{{{W}}}t")
        if t2 is not None:
            t2.text = ""
    body.insert(anchor, num_p)
    body.insert(anchor + 1, name_p)
    body.insert(anchor + 2, tbl)
    anchor += 3
    nxt = list(body)[anchor] if anchor < len(list(body)) else None
    if nxt is not None and nxt.tag.endswith("}p") and not texts(nxt).strip():
        anchor += 1  # skip existing spacer

doc.save(SRC)
print("saved", SRC)
