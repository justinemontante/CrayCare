from flask import Flask, request, jsonify
from flask_cors import CORS
import joblib
import pandas as pd
import os

app = Flask(__name__)
CORS(app)

models = {}
for name in ["aerator", "pump", "status"]:
    path = os.path.join(os.path.dirname(__file__), "models", f"craycare_{name}_model.pkl")
    if os.path.exists(path):
        models[name] = joblib.load(path)
        print(f"Loaded {name} model")
    else:
        print(f"WARNING: Model not found at {path}")

@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()
    
    # Required inputs: sensor readings, trends, and dynamic thresholds
    try:
        features = {
            "temperature": float(data["temperature"]),
            "phLevel": float(data["phLevel"]),
            "dissolvedOxygen": float(data["dissolvedOxygen"]),
            "turbidity": float(data["turbidity"]),
            "waterLevel": float(data["waterLevel"]),
            
            "temp_rate": float(data.get("temp_rate", 0.0)),
            "do_rate": float(data.get("do_rate", 0.0)),
            "turb_rate": float(data.get("turb_rate", 0.0)),
            
            "temp_min": float(data["temp_min"]),
            "temp_max": float(data["temp_max"]),
            "ph_min": float(data["ph_min"]),
            "ph_max": float(data["ph_max"]),
            "do_min": float(data["do_min"]),
            "turb_max": float(data["turb_max"]),
            "wl_min": float(data["wl_min"]),
            "wl_max": float(data["wl_max"])
        }
    except KeyError as e:
        return jsonify({"error": f"Missing required parameter: {e.args[0]}"}), 400
    except ValueError as e:
        return jsonify({"error": f"Invalid numeric parameter: {str(e)}"}), 400

    X = pd.DataFrame([features])
    
    response = {}
    
    if "status" in models:
        response["predictedStatus"] = str(models["status"].predict(X)[0])
        response["statusConfidence"] = float(max(models["status"].predict_proba(X)[0]))
    else:
        response["predictedStatus"] = "OPTIMAL"
        response["statusConfidence"] = 1.0
        
    if "aerator" in models:
        response["aeratorState"] = int(models["aerator"].predict(X)[0])
        response["aeratorConfidence"] = float(max(models["aerator"].predict_proba(X)[0]))
    else:
        response["aeratorState"] = 0
        response["aeratorConfidence"] = 1.0
        
    if "pump" in models:
        response["pumpState"] = int(models["pump"].predict(X)[0])
        response["pumpConfidence"] = float(max(models["pump"].predict_proba(X)[0]))
    else:
        response["pumpState"] = 0
        response["pumpConfidence"] = 1.0

    return jsonify(response)

@app.route("/", methods=["GET"])
def home():
    return jsonify({
        "message": "CrayCare Dynamic Threshold-Aware ML API is running",
        "loaded_models": list(models.keys())
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
