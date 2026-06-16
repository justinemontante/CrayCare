from flask import Flask, request, jsonify
from flask_cors import CORS
import joblib
import pandas as pd
import os

app = Flask(__name__)
CORS(app)

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

SENSOR_KEYS = ["temp", "ph", "do", "turb", "wl"]
models = {}

for key in SENSOR_KEYS:
    path = os.path.join(MODELS_DIR, f"craycare_{key}_model.pkl")
    if os.path.exists(path):
        models[key] = joblib.load(path)
        print(f"Loaded {key} model")
    else:
        models[key] = None
        print(f"WARNING: {key} model not found at {path}")

status_path = os.path.join(MODELS_DIR, "craycare_status_model.pkl")
if os.path.exists(status_path):
    models["status"] = joblib.load(status_path)
    print("Loaded overall status model")
else:
    models["status"] = None
    print("WARNING: Overall status model not found")

FEATURE_ORDER = [
    "temperature",
    "phLevel",
    "dissolvedOxygen",
    "turbidity",
    "waterLevel",
    "temp_rate",
    "ph_rate",
    "do_rate",
    "turb_rate",
    "wl_rate",
    "temp_min",
    "temp_max",
    "ph_min",
    "ph_max",
    "do_min",
    "turb_max",
    "wl_min",
    "wl_max",
]

SENSOR_OUTPUT_MAP = [
    {
        "model_key": "temp",
        "name": "temperature",
        "label": "Temperature",
        "unit": "\u00b0C",
    },
    {"model_key": "ph", "name": "phLevel", "label": "pH Level", "unit": ""},
    {
        "model_key": "do",
        "name": "dissolvedOxygen",
        "label": "Dissolved Oxygen",
        "unit": "mg/L",
    },
    {"model_key": "turb", "name": "turbidity", "label": "Turbidity", "unit": "NTU"},
    {"model_key": "wl", "name": "waterLevel", "label": "Water Level", "unit": "cm"},
]


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()

    try:
        features = {
            "temperature": float(data["temperature"]),
            "phLevel": float(data["phLevel"]),
            "dissolvedOxygen": float(data["dissolvedOxygen"]),
            "turbidity": float(data["turbidity"]),
            "waterLevel": float(data["waterLevel"]),
            "temp_rate": float(data.get("temp_rate", 0.0)),
            "ph_rate": float(data.get("ph_rate", 0.0)),
            "do_rate": float(data.get("do_rate", 0.0)),
            "turb_rate": float(data.get("turb_rate", 0.0)),
            "wl_rate": float(data.get("wl_rate", 0.0)),
            "temp_min": float(data["temp_min"]),
            "temp_max": float(data["temp_max"]),
            "ph_min": float(data["ph_min"]),
            "ph_max": float(data["ph_max"]),
            "do_min": float(data["do_min"]),
            "turb_max": float(data["turb_max"]),
            "wl_min": float(data["wl_min"]),
            "wl_max": float(data["wl_max"]),
        }
    except KeyError as e:
        return jsonify({"error": f"Missing required parameter: {e.args[0]}"}), 400
    except ValueError as e:
        return jsonify({"error": f"Invalid numeric parameter: {str(e)}"}), 400

    X = pd.DataFrame([features])
    X = X[FEATURE_ORDER]

    response = {}

    # Per-sensor predictions
    sensors_output = []
    for cfg in SENSOR_OUTPUT_MAP:
        model = models.get(cfg["model_key"])
        if model is not None:
            pred = str(model.predict(X)[0])
            proba = model.predict_proba(X)[0]
            confidence = round(float(max(proba)), 2)
        else:
            pred = "OPTIMAL"
            confidence = 1.0

        sensors_output.append(
            {
                "key": cfg["name"],
                "label": cfg["label"],
                "unit": cfg["unit"],
                "status": pred,
                "confidence": confidence,
            }
        )

    response["sensors"] = sensors_output

    # Overall status prediction
    if models.get("status") is not None:
        status_pred = str(models["status"].predict(X)[0])
        status_proba = models["status"].predict_proba(X)[0]
        status_confidence = round(float(max(status_proba)), 2)
    else:
        status_pred = "OPTIMAL"
        status_confidence = 1.0

    response["predictedStatus"] = status_pred
    response["statusConfidence"] = status_confidence

    return jsonify(response)


@app.route("/", methods=["GET"])
def home():
    loaded = [k for k, v in models.items() if v is not None]
    return jsonify(
        {
            "message": "CrayCare ML API with per-sensor predictions",
            "loaded_models": loaded,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
