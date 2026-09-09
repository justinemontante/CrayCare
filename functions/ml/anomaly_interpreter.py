"""Human-readable, safety-conscious interpretation for WQAD results."""


def interpret_anomaly(is_anomaly, anomaly_score, contributors, recommendations):
    if not contributors:
        return {
            "insight": "No complete sensor contribution profile is available.",
            "recommendation": recommendations["overall"]["verify"],
        }
    primary = contributors[0]
    secondary = contributors[1] if len(contributors) > 1 else None
    if not is_anomaly:
        return {
            "insight": "The latest combined sensor pattern is consistent with the model reference data. This does not establish that all readings are within the configured safety limits.",
            "recommendation": recommendations["overall"]["normal"],
        }

    def trend_phrase(item):
        if item['direction'] == 'stable':
            return f"{item['label']} has little net change over the recent 30-minute window"
        return f"{item['label']} is {item['direction']} over the recent 30-minute window"

    primary_phrase = trend_phrase(primary)
    if secondary and secondary["contribution_score"] >= primary["contribution_score"] * 0.55:
        pattern = f"{primary_phrase}, while {trend_phrase(secondary)}"
    else:
        pattern = primary_phrase
    by_sensor = {item["sensor"]: item for item in contributors}
    if (by_sensor.get("DO", {}).get("direction") == "decreasing"
            and by_sensor.get("turbidity", {}).get("direction") == "increasing"):
        recommendation = recommendations["combined_do_turbidity"]["action"]
    else:
        sensor_rec = recommendations.get(primary["sensor"], recommendations["overall"])
        recommendation = sensor_rec.get(primary["direction"], sensor_rec.get("verify"))
    return {
        "insight": (
            f"An unusual combined sensor pattern was detected: {pattern}. "
            "The combination differs from the model reference data. "
            "These observations do not establish the cause or prove an unsafe condition."
        ),
        "recommendation": recommendation,
    }
