# CrayCare WQAD

CrayCare uses **Machine Learning-Based Water Quality Anomaly Detection (WQAD)**. WQAD uses only temperature, pH, dissolved oxygen, and turbidity. Water level and feed level remain outside the ML input. Each ten-minute history record stores the captured mean under its canonical sensor name; min/max readings within the ESP window are not WQAD inputs.

It is not a Good/Moderate/Poor/Critical classifier. Sensor safety thresholds remain a separate feature for immediate alerts and actuator logic. WQAD provides an advisory `Normal`, `Unusual`, or `Insufficient` result, a reference-pattern percentile, ranked contributors, an insight, and a verification-focused recommendation. `Normal` means “fits the model's learned reference pattern,” not “water is safe.” The displayed percentile is a relative rarity rank, not a probability or confidence that the water is unsafe. Contributor ranking is a model-score sensitivity check, not a causal explanation.

## Local tests

From this directory, run:

```powershell
venv\Scripts\python.exe -m unittest discover -p "test_*.py"
```

Unit tests create small deterministic readings in memory. Model training uses `Dataset.csv` as described below.

## Live Firestore integration test

The ML folder has no `npm` runner; its offline prototype commands above use the
Python virtual environment. To exercise the deployed WQAD flow with synthetic
Firestore data, run `npm run ml:seed` from `test_tools`. It writes twelve
ten-minute history records for the verified assigned tank. To analyze those
records immediately, run `npm run ml:run-now` from `test_tools`; this invokes
the same owner/tank checks and inference as the scheduled function and writes
the current detection plus one history detection. Alternatively, wait for the
deployed function's next 30-minute run. For a continuous sensor and history
visualization instead, run `npm run ml:demo` and allow enough time for twelve
valid readings. A single missed ten-minute record is tolerated by inference.
These commands write synthetic data and/or analysis
results to the live tank. They do not change sensor thresholds, retrain the
model, or establish field validity.

## Training dataset and active model

`Dataset.csv` is the original `Ponds1.csv` member selected from the supplied
archive. It contains 74,796 source rows from three stations. The trainer calls
`dataset_preparation.py` in memory and retains 74,729 complete four-sensor rows.
It keeps station, timestamp, temperature, pH, dissolved oxygen, and turbidity;
station and timestamp organize each time series but are not raw model features.
Nitrate, ammonia, manganese, and any labels are excluded. Invalid rows are
removed, duplicate station timestamps keep their last reading, stations remain
separate, and no missing reading is interpolated.

The source cadence is normally 20 minutes. Feature version 3 uses time-based
30-minute, one-hour, and two-hour windows, so the training source and live
ten-minute inference use the same real-time horizons despite different sampling
cadences. The two-hour statistics still contain roughly six source readings
versus twelve live readings, so equal horizons do not prove equal feature
distributions. Train the local model directly from the named dataset:

```powershell
venv\Scripts\python.exe train_model.py --dataset Dataset.csv --output trained_wqad_model.joblib --origin external_freshwater_fishpond_proxy_unvalidated --replace
```

By default, the first 60% of unique timestamps fit the Isolation Forest, the
next 20% calibrate its cutoff, and the final 20% form the chronological holdout.
A 144-minute purge separates partitions. All three stations contribute within
each period. Holdout rows never fit the model or select its cutoff.

## Production requirement

The local `trained_wqad_model.joblib` runtime bundle is feature version 3,
trained directly from `Dataset.csv`. It used 45,814 fit rows, 15,245
later calibration rows, and 13,560 final chronological holdout rows. The fixed
98th-percentile cutoff flagged 2.19% of holdout rows. This percentage is an
alert rate, not accuracy. `Dataset.csv` has no outcome labels, so sensitivity,
specificity, precision, and recall cannot be reproduced or established from
the retained project data. Local checks also showed that stable inputs with
pH 14, dissolved oxygen 0 mg/L, or turbidity 250 NTU can still receive a
`Normal` anomaly result. This detector must not replace the separate sensor
safety alerts, and its field sensitivity requires prospective validation on
the target crayfish tank. The local model has not been
deployed by this training workflow. Any existing cloud deployment remains on
its previously deployed bundle until the Firebase function is explicitly
redeployed.

Before final field claims:

1. Calibrate the four water-quality sensors and collect continuous ten-minute history from the real pond.
2. Review gaps, impossible values, maintenance periods, and known sensor failures.
3. Select a stable reference period that represents normal tank operation.
4. Retrain the same unsupervised pipeline using that reference history.
5. Validate alerts prospectively and record farmer or aquaculture-review outcomes without converting sensor safety thresholds into ML class labels.
6. Update `training_data_origin` only after that validation is documented.

The 98th-percentile decision boundary is a statistical rarity cutoff learned from a separate reference calibration block. It is not a biological water-quality threshold, a probability, or a guarantee of a fixed alert rate after drift, and must not directly switch pumps or aerators. There is no honest way to promise fewer unusual results from this short proxy dataset alone: collect a sufficiently long, calibrated, representative period from the actual tank, freeze a normal reference interval in advance, and evaluate future periods separately. Stop or roll back the test deployment if it creates confusing or excessive alerts; do not treat the ML output as an automatic husbandry action.

## Training from collected history

`export_firestore.py` exports the selected tank to `real_sensor_history.csv`, without overwriting `Dataset.csv`. It reads canonical sensor fields and remains compatible with older average-field records, including entries whose day-summary parent does not yet exist. Configure `CRAYCARE_TANK_ID` and application credentials before exporting. Exported timestamps are UTC. Export one tank at a time; do not mix tanks in a single reference history.

```powershell
venv\Scripts\python.exe train_model.py --dataset real_sensor_history.csv --origin real_field_unvalidated --train-days 40 --output wqad_candidate.joblib
```

The 40-day reference period is an example, not a required biological duration. Select it before inspecting the later holdout. The pipeline requires a later holdout and at least 100 usable reference rows. It rejects invalid aggregates, sorts and deduplicates timestamps per series, and rebuilds the two-hour warm-up after a material cadence gap. Live inference still requires twelve recent ten-minute readings and tolerates one missed slot. No future interpolation is used. Real-history fitting does not require labels. Without independent labels, the report contains alert frequency and drift diagnostics, not accuracy, precision, or recall. Synthetic event metrics are explicitly simulation-only. Back up the current runtime bundle before any future model replacement and document target-tank validation before production claims.

## Evidence behind user-facing checks

The recommendation text is deliberately phrased as verification steps and
possible explanations, not a diagnosis or chemical treatment. It asks users to
confirm probes and readings because continuous-monitoring guidance emphasizes
calibration, fouling checks, and quality assurance. The DO guidance notes that
warmer water holds less oxygen and that photosynthesis affects DO. Turbidity
guidance lists sediment, algae, plankton, and organic particles as possible
sources, so the app does not claim a single cause from turbidity alone. The
RAS guidance supports checking filtration and leftover solids/feed. pH advice
asks users to measure alkalinity and seek aquaculture guidance before chemical
changes; it does not instruct automatic dosing. These are general references,
not a substitute for site-specific crayfish husbandry or the app's separately
configured safety thresholds.

- [Queensland Government: Redclaw crayfish aquaculture](https://www.business.qld.gov.au/industries/farms-fishing-forestry/fisheries/aquaculture/species/redclaw-crayfish)
- [Queensland Government: Recirculating aquaculture systems](https://www.business.qld.gov.au/industries/farms-fishing-forestry/fisheries/aquaculture/production/recirculate)
- [USGS: Dissolved Oxygen and Water](https://www.usgs.gov/water-science-school/science/dissolved-oxygen-and-water)
- [USGS: Turbidity and Water](https://www.usgs.gov/water-science-school/science/turbidity-and-water)
- [USGS continuous-monitoring guidance (Wagner et al., 2006)](https://doi.org/10.3133/tm1D3)
- [scikit-learn: IsolationForest](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.IsolationForest.html)
- [UF/IFAS: Alkalinity and Hardness](https://edis.ifas.ufl.edu/publication/SS540)
