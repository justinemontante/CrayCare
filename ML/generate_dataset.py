import random
import pandas as pd
import os

os.makedirs("dataset", exist_ok=True)

rows = []

for _ in range(10000):
    temperature = round(random.uniform(20, 35), 2)
    phLevel = round(random.uniform(6.0, 9.5), 2)
    dissolvedOxygen = round(random.uniform(2.0, 9.0), 2)
    turbidity = round(random.uniform(0, 80), 2)
    waterLevel = round(random.uniform(90, 210), 2)

    isCritical = (
        temperature < 24 or temperature > 31 or
        phLevel < 7.0 or phLevel > 8.5 or
        dissolvedOxygen < 4.0 or
        turbidity > 45 or
        waterLevel < 110 or waterLevel > 190
    )

    status = "CRITICAL" if isCritical else "OPTIMAL"

    rows.append({
        "temperature": temperature,
        "phLevel": phLevel,
        "dissolvedOxygen": dissolvedOxygen,
        "turbidity": turbidity,
        "waterLevel": waterLevel,
        "status": status
    })

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset.csv", index=False)

print("Dataset created successfully!")
print("Saved to dataset/craycare_dataset.csv")
print("Total rows:", len(df))
print(df["status"].value_counts())