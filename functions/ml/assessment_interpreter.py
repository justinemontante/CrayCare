"""Post-ML interpretation for CrayCare water-quality assessments.

The ML model produces the overall Good/Moderate/Poor/Critical assessment.
This module explains that assessment using the most recent one-hour sensor
window. It identifies a primary concern, secondary concerns, and conditions
that have returned to range but were abnormal during the recent window.

A final immediate-safety override is applied after ML assessment: an
independently critical current sensor condition can never be displayed below
Critical. The deterministic rolling-risk floor is applied in features.py.
"""

from features import (
    DO_OPTIMAL_MIN, DO_CRIT_MIN,
    PH_GOOD_MIN, PH_GOOD_MAX, PH_CRIT_MIN, PH_CRIT_MAX,
    TEMP_GOOD_MIN, TEMP_GOOD_MAX, TEMP_CRIT_MIN, TEMP_CRIT_MAX,
    TURB_GOOD_MAX, TURB_CRIT_MAX,
    WATER_MIN_CM, WATER_MAX_CM,
    generate_insight,
)

_LABELS = {
    "DO": "Dissolved Oxygen",
    "pH": "pH Level",
    "temp": "Temperature",
    "turbidity": "Turbidity",
    "waterLevel": "Water Level",
}


def _sensor_state(sensor, row):
    if sensor == "DO":
        value = float(row["DO_avg"]); bad = float(row["DO_min"]) < DO_OPTIMAL_MIN
        critical = float(row["DO_min"]) < DO_CRIT_MIN
        severity = max(0.0, (DO_OPTIMAL_MIN - float(row["DO_min"])) / DO_OPTIMAL_MIN)
        return value, "mg/L", DO_OPTIMAL_MIN, None, bad, critical, severity
    if sensor == "pH":
        value = float(row["pH_avg"]); lo = float(row["pH_min"]); hi = float(row["pH_max"])
        bad = lo < PH_GOOD_MIN or hi > PH_GOOD_MAX
        critical = lo < PH_CRIT_MIN or hi > PH_CRIT_MAX
        severity = max(max(0.0, PH_GOOD_MIN - lo), max(0.0, hi - PH_GOOD_MAX)) / 1.5
        return value, "", PH_GOOD_MIN, PH_GOOD_MAX, bad, critical, severity
    if sensor == "temp":
        value = float(row["temp_avg"]); lo = float(row["temp_min"]); hi = float(row["temp_max"])
        bad = lo < TEMP_GOOD_MIN or hi > TEMP_GOOD_MAX
        critical = lo < TEMP_CRIT_MIN or hi > TEMP_CRIT_MAX
        severity = max(max(0.0, TEMP_GOOD_MIN - lo), max(0.0, hi - TEMP_GOOD_MAX)) / 5.0
        return value, "°C", TEMP_GOOD_MIN, TEMP_GOOD_MAX, bad, critical, severity
    if sensor == "turbidity":
        value = float(row["turbidity_avg"]); hi = float(row["turbidity_max"])
        bad = hi > TURB_GOOD_MAX; critical = hi > TURB_CRIT_MAX
        severity = max(0.0, hi - TURB_GOOD_MAX) / TURB_GOOD_MAX
        return value, "NTU", 0.0, TURB_GOOD_MAX, bad, critical, severity
    value = float(row["waterLevel_avg"]); lo = float(row["waterLevel_min"]); hi = float(row["waterLevel_max"])
    bad = lo < WATER_MIN_CM or hi > WATER_MAX_CM
    width = max(WATER_MAX_CM - WATER_MIN_CM, 1.0)
    deviation = max(max(0.0, WATER_MIN_CM - lo), max(0.0, hi - WATER_MAX_CM))
    critical = deviation >= width
    severity = deviation / width
    return value, "cm", WATER_MIN_CM, WATER_MAX_CM, bad, critical, severity


def _recovery_insight(sensor, recent, latest):
    label = _LABELS[sensor]
    bad_count = sum(1 for _, row in recent.iterrows() if _sensor_state(sensor, row)[4])
    if bad_count <= 0:
        return ""
    value, unit, _, _, latest_bad, _, _ = _sensor_state(sensor, latest)
    if latest_bad:
        return ""
    suffix = f" {unit}" if unit else ""
    return (
        f"{label} is currently back within its operating range at {value:.1f}{suffix}, "
        f"but was outside range in {bad_count} of the last {len(recent)} ten-minute windows. "
        "Continue corrective measures and monitor the next readings before returning to the normal routine."
    )


def enrich_assessment(result, df, recs):
    """Add trend-aware primary/secondary concerns and combined recommendations."""
    if df is None or df.empty or result.get("level") == "Insufficient":
        return result

    recent = df.tail(6)
    latest = recent.iloc[-1]
    concerns = []

    for sensor in ("DO", "pH", "temp", "turbidity", "waterLevel"):
        value, unit, min_v, max_v, latest_bad, critical, current_severity = _sensor_state(sensor, latest)
        bad_count = sum(1 for _, row in recent.iterrows() if _sensor_state(sensor, row)[4])
        recent_ratio = bad_count / max(len(recent), 1)
        recovering = (not latest_bad) and bad_count > 0

        if not latest_bad and recent_ratio < 0.5:
            continue

        score = current_severity + (0.65 * recent_ratio) + (0.75 if critical else 0.0)
        rec = recs.get(sensor, recs.get("overall", {}))
        action_key = "critical_action" if critical else "action"
        action = rec.get(action_key, rec.get("action", "Continue monitoring."))
        if recovering:
            action = "RECOVERING — Continue the corrective action and monitor the next readings before returning to the normal routine. " + action

        insight = _recovery_insight(sensor, recent, latest)
        if not insight:
            insight = generate_insight(sensor, latest, result.get("level", "Moderate"))

        concerns.append({
            "sensor": sensor,
            "label": _LABELS[sensor],
            "status": "recovering" if recovering else ("critical" if critical else "active"),
            "value": round(value, 3),
            "unit": unit,
            "min": min_v,
            "max": max_v,
            "recent_bad_windows": bad_count,
            "recent_window_count": len(recent),
            "severity": round(score, 3),
            "problem": rec.get("problem", f"{_LABELS[sensor]} outside operating range"),
            "insight": insight,
            "action": action,
        })

    concerns.sort(key=lambda item: item["severity"], reverse=True)

    if not concerns:
        result["driver"] = "overall"
        result["driver_label"] = "All monitored parameters"
        result["driver_value"] = None
        result["driver_unit"] = ""
        result["driver_min"] = None
        result["driver_max"] = None
        result["concerns"] = []
        result["secondary_concerns"] = []
        return result

    # Never understate an independently critical current reading. The rolling
    # deterministic floor was already applied to the model output in features.py.
    if any(c["status"] == "critical" for c in concerns):
        if result.get("level") != "Critical":
            result["safety_override"] = True
        result["level"] = "Critical"

    primary = concerns[0]
    result["driver"] = primary["sensor"]
    result["driver_label"] = primary["label"]
    result["driver_value"] = primary["value"]
    result["driver_unit"] = primary["unit"]
    result["driver_min"] = primary["min"]
    result["driver_max"] = primary["max"]
    result["problem"] = primary["problem"]
    result["insight"] = primary["insight"]
    result["concerns"] = concerns
    result["secondary_concerns"] = [c["label"] for c in concerns[1:]]

    if len(concerns) == 1:
        result["action"] = primary["action"]
    else:
        lines = []
        for idx, concern in enumerate(concerns, 1):
            state = " (recovering)" if concern["status"] == "recovering" else ""
            lines.append(f"{idx}. {concern['label']}{state}: {concern['action']}")
        result["action"] = "\n\n".join(lines)
        secondary = ", ".join(c["label"] for c in concerns[1:])
        result["insight"] = primary["insight"] + f" Other recent concerns detected: {secondary}."

    return result
