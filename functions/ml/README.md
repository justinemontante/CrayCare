# CrayCare WQAD

CrayCare uses **Machine Learning-Based Water Quality Anomaly Detection (WQAD)**. The deployed `IsolationForest` learns the usual combined behavior of temperature, pH, dissolved oxygen, turbidity, and water level, including short-term changes and trends.

It is not a Good/Moderate/Poor/Critical classifier. Sensor safety thresholds remain a separate feature for immediate alerts and actuator logic. WQAD provides an advisory `Normal`, `Unusual`, or `Insufficient` result, a reference-pattern percentile, ranked contributors, an insight, and a verification-focused recommendation.

## Prototype workflow

From this directory, run:

```powershell
venv\Scripts\python.exe generate_dataset.py
venv\Scripts\python.exe train_model.py --origin synthetic_bootstrap_not_field_validated
venv\Scripts\python.exe -m unittest discover -p "test_*.py"
```

`generate_dataset.py` creates reproducible ten-minute RAS-like readings and holdout operational events. Event labels are used only to evaluate the finished prototype; they are never given to the model during fitting. `train_model.py` stores the fitted artifact and its provenance in `wqad_model.joblib`.

## Production requirement

The bundled artifact is explicitly marked `synthetic_bootstrap_not_field_validated`. It is suitable for integration testing and a prototype demonstration, but it must not be presented as proven for the actual Cherax tank.

Before final field claims:

1. Calibrate all five water sensors and collect continuous ten-minute history from the real RAS tank.
2. Review gaps, impossible values, maintenance periods, and known sensor failures.
3. Select a stable reference period that represents normal tank operation.
4. Retrain the same unsupervised pipeline using that reference history.
5. Validate alerts prospectively and record farmer or aquaculture-review outcomes without converting sensor safety thresholds into ML class labels.
6. Update `training_data_origin` and the model version only after that validation is documented.

The 98th-percentile decision boundary is a statistical rarity cutoff learned from reference anomaly scores. It is not a biological water-quality threshold and must not be used to directly switch pumps or aerators.

## Training from collected history

`export_firestore.py` exports the selected tank to `real_sensor_history.csv`, without overwriting the synthetic dataset. Configure `CRAYCARE_TANK_ID` and application credentials before exporting. Exported timestamps are UTC. Export one tank at a time; do not mix tanks in a single reference history.

```powershell
venv\Scripts\python.exe train_model.py --dataset real_sensor_history.csv --origin real_field_unvalidated --train-days 40 --output wqad_candidate.joblib
```

The 40-day reference period is an example, not a required biological duration. Select it before inspecting the later holdout. The pipeline requires a later holdout and at least 100 usable reference rows. It rejects invalid aggregates, sorts and deduplicates timestamps, and restarts the twelve-row warm-up after gaps outside 8–12 minutes, matching inference. No future interpolation is used. It does not require labels to fit real history. Without independent labels it reports the holdout alert fraction, not accuracy, precision, or recall. Synthetic event metrics are explicitly simulation-only. Review candidate models before replacing the deployed artifact; this code update does not retrain or deploy the current artifact.
