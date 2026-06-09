from flask import Flask, request, jsonify
from flask_cors import CORS
import joblib
import pandas as pd

app = Flask(__name__)
CORS(app)

model = joblib.load("models/craycare_model.pkl")


def check_thresholds(data, thresholds):
    out_of_range = []
    threshold_map = {
        "temperature": "temperature",
        "phLevel": "phLevel",
        "dissolvedOxygen": "dissolvedOxygen",
        "turbidity": "turbidity",
        "waterLevel": "waterLevel",
    }

    if not thresholds:
        return [], False

    for key, label in threshold_map.items():
        if key not in thresholds or key not in data:
            continue
        t = thresholds[key]
        val = data[key]
        t_min = t.get("min")
        t_max = t.get("max")

        if t_min is not None and val < t_min:
            out_of_range.append(
                f"{label} ({val}) is below the ideal minimum of {t_min}"
            )
        elif t_max is not None and val > t_max:
            out_of_range.append(
                f"{label} ({val}) is above the ideal maximum of {t_max}"
            )

    has_issue = len(out_of_range) > 0
    return out_of_range, has_issue


def build_response(status, confidence, out_of_range):
    if out_of_range:
        details = "; ".join(out_of_range)
        return {
            "predictedStatus": "CRITICAL",
            "confidence": confidence,
            "insight": f"Sensor reading out of ideal range: {details}.",
            "prediction": "The model predicts that the current condition needs attention to bring readings back within ideal range.",
            "recommendation": "Adjust the affected sensors to bring them back within the configured ideal ranges. Check your stage settings for the recommended ranges.",
        }

    if status == "CRITICAL":
        return {
            "predictedStatus": status,
            "confidence": confidence,
            "insight": "The current water condition shows possible environmental stress based on the sensor values.",
            "prediction": "The model predicts that the current condition may require immediate monitoring or corrective action.",
            "recommendation": "Check aeration, water circulation, filtration, and water quality immediately.",
        }

    return {
        "predictedStatus": status,
        "confidence": confidence,
        "insight": "The current water condition is within the acceptable range based on the sensor values.",
        "prediction": "The model predicts that the water condition is likely to remain acceptable if current readings stay stable.",
        "recommendation": "Continue regular monitoring and maintain the current setup.",
    }


def build_per_sensor_response(status, confidence, data, thresholds):
    sensor_configs = [
        {"key": "temperature", "label": "Temperature", "unit": "\u00b0C"},
        {"key": "phLevel", "label": "pH Level", "unit": ""},
        {"key": "dissolvedOxygen", "label": "Dissolved Oxygen", "unit": "mg/L"},
        {"key": "turbidity", "label": "Turbidity", "unit": "NTU"},
        {"key": "waterLevel", "label": "Water Level", "unit": "%"},
    ]

    sensors = []
    out_of_range = []

    for cfg in sensor_configs:
        key = cfg["key"]
        val = data.get(key, 0)
        t = thresholds.get(key, {}) if thresholds else {}
        t_min = t.get("min")
        t_max = t.get("max")

        sensor_status = "OPTIMAL"
        if t_min is not None and val < t_min:
            sensor_status = "CRITICAL"
            out_of_range.append(
                f"{cfg['label']} ({val}) is below the ideal minimum of {t_min}"
            )
        elif t_max is not None and val > t_max:
            sensor_status = "CRITICAL"
            out_of_range.append(
                f"{cfg['label']} ({val}) is above the ideal maximum of {t_max}"
            )

        if sensor_status == "CRITICAL":
            if t_min is not None and val < t_min:
                insight = f"{cfg['label']} at {val}{cfg['unit']} is below the ideal minimum of {t_min}{cfg['unit']}."
                prediction = "The model predicts this may cause environmental stress if not corrected."
                recommendation = f"Increase {cfg['label'].lower()} to bring it within the ideal range ({t_min}{cfg['unit']} - {t_max}{cfg['unit']})."
            elif t_max is not None and val > t_max:
                insight = f"{cfg['label']} at {val}{cfg['unit']} is above the ideal maximum of {t_max}{cfg['unit']}."
                prediction = "The model predicts this may cause environmental stress if not corrected."
                recommendation = f"Reduce {cfg['label'].lower()} to bring it within the ideal range ({t_min}{cfg['unit']} - {t_max}{cfg['unit']})."
            else:
                insight = f"{cfg['label']} reading is {val}{cfg['unit']} and requires attention."
                prediction = "The model predicts that corrective action is needed."
                recommendation = "Check equipment and water quality parameters."
        else:
            if t_min is not None and t_max is not None:
                insight = f"{cfg['label']} at {val}{cfg['unit']} is within the ideal range ({t_min}{cfg['unit']} - {t_max}{cfg['unit']})."
            else:
                insight = f"{cfg['label']} is currently at {val}{cfg['unit']}."
            prediction = (
                "The model predicts stable conditions if current readings persist."
            )
            recommendation = "Continue regular monitoring."

        sensors.append(
            {
                "key": key,
                "label": cfg["label"],
                "value": val,
                "unit": cfg["unit"],
                "min": t_min,
                "max": t_max,
                "status": sensor_status,
                "insight": insight,
                "prediction": prediction,
                "recommendation": recommendation,
            }
        )

    overall = build_response(status, confidence, out_of_range)
    overall["sensors"] = sensors
    overall["sensorValues"] = data
    return overall


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()

    X = pd.DataFrame(
        [
            {
                "temperature": float(data["temperature"]),
                "phLevel": float(data["phLevel"]),
                "dissolvedOxygen": float(data["dissolvedOxygen"]),
                "turbidity": float(data["turbidity"]),
                "waterLevel": float(data["waterLevel"]),
            }
        ]
    )

    prediction = model.predict(X)[0]
    probabilities = model.predict_proba(X)[0]
    confidence = round(float(max(probabilities)), 2)

    thresholds = data.get("thresholds")

    return jsonify(build_per_sensor_response(prediction, confidence, data, thresholds))


@app.route("/", methods=["GET"])
def home():
    return jsonify({"message": "CrayCare ML API is running"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
