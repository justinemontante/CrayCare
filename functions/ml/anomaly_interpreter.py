"""Human-readable, safety-conscious interpretation for WQAD results."""

SENSOR_LABELS = {
    "temp": "Temperature",
    "pH": "pH Level",
    "DO": "Dissolved Oxygen",
    "turbidity": "Turbidity",
}


def interpret_anomaly(is_anomaly, anomaly_score, contributors, recommendations):
    if not is_anomaly:
        return {
            "insight": "The combined readings are within the model's usual pattern. Continue checking the separate sensor safety alerts.",
            "recommendation": recommendations["overall"]["normal"],
        }
    if not contributors:
        return {
            "insight": "The combined readings differ from the reference pattern; no single sensor explains the score clearly.",
            "recommendation": recommendations["overall"]["verify"],
        }
    primary = contributors[0]
    secondary = contributors[1] if len(contributors) > 1 else None

    def trend_phrase(item):
        label = SENSOR_LABELS.get(item["sensor"], item["sensor"])
        unit = {"temp": "°C", "DO": " mg/L", "turbidity": " NTU"}.get(item["sensor"], "")
        reading = f"{label} ({item['value']:g}{unit})"
        if item["direction"] == "stable":
            return f"{reading} shows little recent net change"
        return f"{reading} is {item['direction']} in recent readings"

    primary_phrase = trend_phrase(primary)
    if secondary and secondary["contribution_score"] >= primary["contribution_score"] * 0.55:
        pattern = f"{primary_phrase}, while {trend_phrase(secondary)}"
    else:
        pattern = primary_phrase
    by_sensor = {item["sensor"]: item for item in contributors}
    if (primary["sensor"] in {"DO", "turbidity"}
            and by_sensor.get("DO", {}).get("direction") == "decreasing"
            and by_sensor.get("turbidity", {}).get("direction") == "increasing"):
        recommendation = recommendations["combined_do_turbidity"]["action"]
    elif (primary["sensor"] in {"DO", "temp"}
            and by_sensor.get("DO", {}).get("direction") == "decreasing"
            and by_sensor.get("temp", {}).get("direction") == "increasing"):
        recommendation = recommendations["combined_temp_do"]["action"]
    else:
        sensor_rec = recommendations.get(primary["sensor"], recommendations["overall"])
        recommendation = sensor_rec.get(primary["direction"], sensor_rec.get("verify"))
    return {
        "insight": (
            f"An unusual combined pattern was detected. Among the readings associated with the score, {pattern}. "
            "Check the readings and tank conditions to establish the cause."
        ),
        "recommendation": recommendation,
    }
