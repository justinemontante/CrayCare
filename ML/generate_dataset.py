import random
import pandas as pd
import numpy as np
import os

os.makedirs("dataset", exist_ok=True)

# Generate 50,000 samples for robust training
num_rows = 50000
rows = []

for _ in range(num_rows):
    # 1. Randomize farmer thresholds (so model learns to adapt to any inputs)
    temp_min = round(random.uniform(22.0, 26.0), 1)
    temp_max = round(random.uniform(28.0, 32.0), 1)
    
    ph_min = round(random.uniform(6.5, 7.5), 1)
    ph_max = round(random.uniform(8.0, 9.0), 1)
    
    do_min = round(random.uniform(4.0, 6.0), 1)
    
    turb_max = round(random.uniform(20.0, 40.0), 1)
    
    wl_min = round(random.uniform(100.0, 140.0), 1)
    wl_max = round(random.uniform(160.0, 200.0), 1)
    
    # 2. Randomize current sensor values (sometimes optimal, sometimes critical)
    temperature = round(random.uniform(18.0, 35.0), 2)
    phLevel = round(random.uniform(5.5, 10.0), 2)
    dissolvedOxygen = round(random.uniform(1.0, 10.0), 2)
    turbidity = round(random.uniform(0.0, 100.0), 2)
    waterLevel = round(random.uniform(80.0, 220.0), 2)
    
    # 3. Randomize trend rates
    temp_rate = round(random.uniform(-0.3, 0.3), 3)
    do_rate = round(random.uniform(-0.4, 0.4), 3)
    turb_rate = round(random.uniform(-2.0, 2.0), 3)
    
    # 4. Determine Overall Status
    # - CRITICAL if any sensor is outside range
    # - WARNING if any sensor is in its 15% warning range OR if a critical drop is imminent
    # - OPTIMAL otherwise
    status = "OPTIMAL"
    
    # Temp checks
    if temperature < temp_min or temperature > temp_max:
        status = "CRITICAL"
    elif (temperature >= temp_min and temperature < temp_min + (temp_max-temp_min)*0.15) or \
         (temperature <= temp_max and temperature > temp_max - (temp_max-temp_min)*0.15) or \
         (temp_rate > 0.15 and temperature > temp_max - (temp_max-temp_min)*0.3) or \
         (temp_rate < -0.15 and temperature < temp_min + (temp_max-temp_min)*0.3):
        if status != "CRITICAL": status = "WARNING"
        
    # pH checks
    if phLevel < ph_min or phLevel > ph_max:
        status = "CRITICAL"
    elif (phLevel >= ph_min and phLevel < ph_min + (ph_max-ph_min)*0.15) or \
         (phLevel <= ph_max and phLevel > ph_max - (ph_max-ph_min)*0.15):
        if status != "CRITICAL": status = "WARNING"
        
    # DO checks
    if dissolvedOxygen < do_min:
        status = "CRITICAL"
    elif dissolvedOxygen < do_min + do_min*0.15 or (do_rate < -0.05 and dissolvedOxygen < do_min + do_min*0.3):
        if status != "CRITICAL": status = "WARNING"
        
    # Turbidity checks
    if turbidity > turb_max:
        status = "CRITICAL"
    elif turbidity > turb_max - turb_max*0.15 or (turb_rate > 0.5 and turbidity > turb_max - turb_max*0.3):
        if status != "CRITICAL": status = "WARNING"
        
    # Water level checks
    if waterLevel < wl_min or waterLevel > wl_max:
        status = "CRITICAL"
    elif (waterLevel >= wl_min and waterLevel < wl_min + (wl_max-wl_min)*0.15) or \
         (waterLevel <= wl_max and waterLevel > wl_max - (wl_max-wl_min)*0.15):
        if status != "CRITICAL": status = "WARNING"

    rows.append({
        # Inputs
        "temperature": temperature,
        "phLevel": phLevel,
        "dissolvedOxygen": dissolvedOxygen,
        "turbidity": turbidity,
        "waterLevel": waterLevel,
        
        "temp_rate": temp_rate,
        "do_rate": do_rate,
        "turb_rate": turb_rate,
        
        "temp_min": temp_min,
        "temp_max": temp_max,
        "ph_min": ph_min,
        "ph_max": ph_max,
        "do_min": do_min,
        "turb_max": turb_max,
        "wl_min": wl_min,
        "wl_max": wl_max,
        
        # Target
        "status": status
    })

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset.csv", index=False)
print(f"Generated status dataset with {len(df)} rows.")
