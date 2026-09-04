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
            "insight": "The latest combined sensor pattern is consistent with the behaviour learned from the tank's reference history.",
            "recommendation": recommendations["overall"]["normal"],
        }

    primary_phrase = f"{primary['label']} is {primary['direction']}"
    if secondary and secondary["contribution_score"] >= primary["contribution_score"] * 0.55:
        pattern = f"{primary_phrase} while {secondary['label']} is {secondary['direction']}"
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
            f"An unusual multivariate water pattern was detected (anomaly score {anomaly_score:.1f}/100): "
            f"{pattern}. This means the combination differs from the learned tank baseline; "
            "it does not by itself prove an unsafe condition."
        ),
        "recommendation": recommendation,
    }
