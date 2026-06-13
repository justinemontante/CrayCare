import sys, os, json, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
import pandas as pd
import joblib

SERVICE_ACCOUNT = os.path.join(
    os.path.dirname(__file__), "..", "notification_worker", "serviceAccountKey.json"
)

DATABASE_URL = (
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
)

cred = credentials.Certificate(SERVICE_ACCOUNT)
firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})

latest_ref = db.reference("sensor_readings/latest")
config_ref = db.reference("sensor_readings/config")
prediction_ref = db.reference("ml_predictions/latest")

# Load status model
model_path = os.path.join(os.path.dirname(__file__), "models", "craycare_status_model.pkl")
if os.path.exists(model_path):
    status_model = joblib.load(model_path)
    print("[ML Worker] Loaded status model successfully.")
else:
    status_model = None
    print(f"[ML Worker] WARNING: Status model not found at {model_path}")

class SensorHistory:
    def __init__(self, max_len=5):
        self.max_len = max_len
        self.history = []
        
    def add(self, value):
        self.history.append(value)
        if len(self.history) > self.max_len:
            self.history.pop(0)
            
    def get_rate(self):
        if len(self.history) < 2:
            return 0.0
        delta = self.history[-1] - self.history[0]
        return delta / (len(self.history) - 1)

# Keep track of history per sensor for trend rates
histories = {
    "temp": SensorHistory(),
    "do": SensorHistory(),
    "turb": SensorHistory(),
    "ph": SensorHistory(),
    "waterlevel": SensorHistory()
}

def get_current_stage_ranges():
    """Read current stage and its sensor ranges from sensor_readings/config."""
    config = config_ref.get() or {}
    stage = config.get("selectedStage") or "pre_adult"
    
    stage_config = config.get(stage, {})
    
    # Default fallback values
    defaults = {
        "temp": {"min": 24.0, "max": 30.0},
        "ph": {"min": 7.0, "max": 8.5},
        "do": {"min": 4.5, "max": 999.0},
        "turb": {"min": 0.0, "max": 35.0},
        "waterlevel": {"min": 130.0, "max": 180.0}
    }
    
    ranges = {}
    for key in ["temp", "ph", "do", "turb", "waterlevel"]:
        sensor_range = stage_config.get(key, {}) if isinstance(stage_config, dict) else {}
        if not sensor_range:
            sensor_range = config.get("ranges", {}).get(key, {})
            
        if not sensor_range:
            sensor_range = defaults[key]
            
        ranges[key] = {
            "min": float(sensor_range.get("min") if sensor_range.get("min") is not None else defaults[key]["min"]),
            "max": float(sensor_range.get("max") if sensor_range.get("max") is not None else defaults[key]["max"])
        }
        
    return stage, ranges

def on_sensor_change(event):
    data = event.data
    if not data:
        return

    # Extract values
    temp = data.get("temperature")
    ph = data.get("phLevel")
    d_o = data.get("dissolvedOxygen")
    turb = data.get("turbidity")
    wl = data.get("waterLevel")
    
    # If any value is missing, skip
    if any(v is None for v in [temp, ph, d_o, turb, wl]):
        return
        
    # Update histories and get rates
    histories["temp"].add(temp)
    histories["ph"].add(ph)
    histories["do"].add(d_o)
    histories["turb"].add(turb)
    histories["waterlevel"].add(wl)
    
    temp_rate = histories["temp"].get_rate()
    ph_rate = histories["ph"].get_rate()
    do_rate = histories["do"].get_rate()
    turb_rate = histories["turb"].get_rate()
    wl_rate = histories["waterlevel"].get_rate()
    
    # Get farmer configured thresholds
    stage, ranges = get_current_stage_ranges()
    
    # Prepare features
    features = {
        "temperature": float(temp),
        "phLevel": float(ph),
        "dissolvedOxygen": float(d_o),
        "turbidity": float(turb),
        "waterLevel": float(wl),
        
        "temp_rate": float(temp_rate),
        "do_rate": float(do_rate),
        "turb_rate": float(turb_rate),
        
        "temp_min": float(ranges["temp"]["min"]),
        "temp_max": float(ranges["temp"]["max"]),
        "ph_min": float(ranges["ph"]["min"]),
        "ph_max": float(ranges["ph"]["max"]),
        "do_min": float(ranges["do"]["min"]),
        "turb_max": float(ranges["turb"]["max"]),
        "wl_min": float(ranges["waterlevel"]["min"]),
        "wl_max": float(ranges["waterlevel"]["max"])
    }
    
    X = pd.DataFrame([features])
    
    # Predict Overall Status using Random Forest
    if status_model is not None:
        status_pred = str(status_model.predict(X)[0])
        status_prob = status_model.predict_proba(X)[0]
        confidence = round(float(max(status_prob)), 2)
    else:
        status_pred = "OPTIMAL"
        confidence = 1.0

    # Build the 'sensors' list dynamically with rich predictive texts
    sensor_configs = [
        {"key": "temperature", "name": "temp", "label": "Temperature", "unit": "°C"},
        {"key": "phLevel", "name": "ph", "label": "pH Level", "unit": ""},
        {"key": "dissolvedOxygen", "name": "do", "label": "Dissolved Oxygen", "unit": "mg/L"},
        {"key": "turbidity", "name": "turb", "label": "Turbidity", "unit": "NTU"},
        {"key": "waterLevel", "name": "waterlevel", "label": "Water Level", "unit": "cm"}
    ]
    
    sensors_list = []
    
    for cfg in sensor_configs:
        key = cfg["key"]
        name = cfg["name"]
        val = float(features[key])
        r_min = ranges[name]["min"]
        r_max = ranges[name]["max"]
        unit = cfg["unit"]
        
        # Calculate rate
        if name == "temp": rate = temp_rate
        elif name == "ph": rate = ph_rate
        elif name == "do": rate = do_rate
        elif name == "turb": rate = turb_rate
        else: rate = wl_rate
        
        # Calculate status
        is_max_bound = r_max < 999.0
        range_span = (r_max - r_min) if is_max_bound else r_min
        warn_span = range_span * 0.15
        
        check_lower = r_min > 0.0
        check_upper = is_max_bound
        
        if val < r_min or val > r_max:
            sensor_status = "CRITICAL"
        elif (check_lower and (val - r_min) < warn_span) or (check_upper and (r_max - val) < warn_span):
            sensor_status = "WARNING"
        else:
            sensor_status = "OPTIMAL"
            
        # Insights & Recommendations
        if sensor_status == "CRITICAL":
            if val < r_min:
                insight = f"{cfg['label']} is critical at {val}{unit} (below ideal min of {r_min}{unit})."
                recommendation = f"Urgent action required: Increase {cfg['label'].lower()}."
            else:
                insight = f"{cfg['label']} is critical at {val}{unit} (above ideal max of {r_max}{unit})."
                recommendation = f"Urgent action required: Reduce {cfg['label'].lower()}."
            prediction = "Crayfish are under high physiological stress. Mortality risk if prolonged."
            
        elif sensor_status == "WARNING":
            if check_lower and (val - r_min) < warn_span:
                insight = f"{cfg['label']} is warning-low at {val}{unit} (approaching {r_min}{unit})."
                recommendation = f"Adjust parameters: Raise {cfg['label'].lower()} soon."
            else:
                insight = f"{cfg['label']} is warning-high at {val}{unit} (approaching {r_max}{unit})."
                recommendation = f"Adjust parameters: Lower {cfg['label'].lower()} soon."
            
            sign = "+" if rate >= 0 else ""
            prediction = f"Reading is warning-close to limits and moving at {sign}{rate:.3f}{unit}/rdg."
            
        else:
            insight = f"{cfg['label']} is optimal at {val}{unit} (Ideal: {r_min} - {r_max if is_max_bound else '∞'}{unit})."
            sign = "+" if rate >= 0 else ""
            prediction = f"Stable condition. Moving slowly at {sign}{rate:.3f}{unit}/rdg."
            recommendation = "No action needed. Maintain current system setup."
            
        # Specific predictions based on rate
        if name == "do" and rate < -0.05 and val < r_min + warn_span * 2:
            prediction = f"CRITICAL PREDICTION: DO is dropping rapidly ({rate:.3f} mg/L per reading) and will cross limit soon!"
            recommendation = "Activate aerator/oxygen support immediately."
        elif name == "turb" and rate > 0.5 and val > r_max - warn_span * 2:
            prediction = f"WARNING PREDICTION: Turbidity is rising fast (+{rate:.2f} NTU per reading)."
            recommendation = "Turn on water filter / recirculation pump to clear water."
        elif name == "waterlevel" and val < r_min:
            recommendation = "Fill tank immediately. Do NOT run water pump if water level is too low to prevent motor damage."

        sensors_list.append({
            "key": key,
            "label": cfg["label"],
            "status": sensor_status,
            "insight": insight,
            "prediction": prediction,
            "recommendation": recommendation
        })

    # Overall recommendation summaries
    overall_insights = [s["insight"] for s in sensors_list if s["status"] != "OPTIMAL"]
    overall_recs = [s["recommendation"] for s in sensors_list if s["status"] != "OPTIMAL"]
    
    if not overall_insights:
        insight_text = "All water quality parameters are within their optimal ranges. The aquaculture system is healthy."
        rec_text = "Continue regular monitoring and routine maintenance."
    else:
        insight_text = " | ".join(overall_insights)
        rec_text = " | ".join(overall_recs)

    result = {
        "predictedStatus": status_pred,
        "confidence": confidence,
        "sensors": sensors_list,
        "insight": insight_text,
        "prediction": f"Machine Learning Model predicts a {status_pred} overall status ({int(confidence*100)}% confidence) based on sensor values and rates of change.",
        "recommendation": rec_text,
        "timestamp": int(time.time() * 1000),
        "stage": stage
    }
    
    print(f"[ML Worker] Stage={stage} Status={status_pred} (Conf={confidence})")
    prediction_ref.set(result)

print("[ML Worker] Listening to sensor_readings/latest...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
