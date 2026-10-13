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
            "insight": (
                "The recent temperature, pH, dissolved-oxygen, and turbidity pattern resembles "
                "the model's learned reference. This is not a water-safety assessment."
            ),
            "recommendation": recommendations["overall"]["normal"],
        }
    if not contributors:
        return {
            "insight": (
                "The recent combined pattern differs from the model's learned reference, but "
                "the model did not identify a main sensor."
            ),
            "recommendation": recommendations["overall"]["verify"],
        }
    primary = contributors[0]
    secondary = contributors[1] if len(contributors) > 1 else None

    def trend_phrase(item):
        label = SENSOR_LABELS.get(item["sensor"], item["sensor"])
        unit = {"temp": "°C", "DO": " mg/L", "turbidity": " NTU"}.get(item["sensor"], "")
        reading = f"{label} ({item['value']:g}{unit})"
        if item["direction"] == "stable":
            return f"{reading} shows little net change in recent readings"
        direction = {"increasing": "trending up", "decreasing": "trending down"}.get(
            item["direction"], "has an unclear recent trend"
        )
        return f"{reading} is {direction}"

    primary_phrase = trend_phrase(primary)
    if secondary and secondary["contribution_score"] >= primary["contribution_score"] * 0.55:
        pattern = f"{primary_phrase}, while {trend_phrase(secondary)}"
    else:
        pattern = primary_phrase
    by_sensor = {item["sensor"]: item for item in contributors}

    def pair_is_material(first, second):
        first_item, second_item = by_sensor.get(first), by_sensor.get(second)
        if first_item is None or second_item is None:
            return False
        strongest = max(first_item["contribution_score"], second_item["contribution_score"])
        weakest = min(first_item["contribution_score"], second_item["contribution_score"])
        return strongest > 0 and weakest >= strongest * 0.55

    if (primary["sensor"] in {"DO", "turbidity"}
            and pair_is_material("DO", "turbidity")
            and by_sensor.get("DO", {}).get("direction") == "decreasing"
            and by_sensor.get("turbidity", {}).get("direction") == "increasing"):
        recommendation = recommendations["combined_do_turbidity"]["action"]
    elif (primary["sensor"] in {"DO", "temp"}
            and pair_is_material("DO", "temp")
            and by_sensor.get("DO", {}).get("direction") == "decreasing"
            and by_sensor.get("temp", {}).get("direction") == "increasing"):
        recommendation = recommendations["combined_temp_do"]["action"]
    elif (primary["sensor"] in {"pH", "DO"}
            and pair_is_material("pH", "DO")
            and by_sensor.get("pH", {}).get("direction")
            == by_sensor.get("DO", {}).get("direction")
            and by_sensor.get("pH", {}).get("direction") in {"increasing", "decreasing"}):
        recommendation = recommendations["combined_ph_do"]["action"]
    else:
        sensor_rec = recommendations.get(primary["sensor"], recommendations["overall"])
        recommendation = sensor_rec.get(primary["direction"], sensor_rec.get("verify"))
    return {
        "insight": (
            f"An unusual combined water-quality pattern was detected. {pattern}."
        ),
        "recommendation": recommendation,
    }
