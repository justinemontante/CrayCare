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
    out_of_range, has_issue = check_thresholds(data, thresholds)

    return jsonify(build_response(prediction, confidence, out_of_range))


@app.route("/", methods=["GET"])
def home():
    return jsonify({"message": "CrayCare ML API is running"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
