# CrayCare WQAD

CrayCare uses **Machine Learning-Based Water Quality Anomaly Detection (WQAD)**. WQAD uses only temperature, pH, dissolved oxygen, and turbidity. Water level and feed level remain outside the ML input. Each ten-minute history record stores the captured mean under its canonical sensor name; min/max readings within the ESP window are not WQAD inputs.

It is not a Good/Moderate/Poor/Critical classifier. Sensor safety thresholds remain a separate feature for immediate alerts and actuator logic. WQAD provides an advisory `Normal`, `Unusual`, or `Insufficient` result, a reference-pattern percentile, ranked contributors, an insight, and a verification-focused recommendation. `Normal` means “fits the model's learned reference pattern,” not “water is safe.” The displayed percentile is a relative rarity rank, not a probability or confidence that the water is unsafe. Contributor ranking is a model-score sensitivity check, not a causal explanation.

## Prototype workflow

From this directory, run:

```powershell
venv\Scripts\python.exe generate_dataset.py
venv\Scripts\python.exe train_model.py --dataset sensor_dataset.csv --output "$env:TEMP\wqad_synthetic_candidate.joblib" --train-days 60 --origin synthetic_bootstrap_not_field_validated
venv\Scripts\python.exe -m unittest discover -p "test_*.py"
```

`generate_dataset.py` creates reproducible ten-minute example readings and holdout events for software tests only. Their event labels are not supplied to model fitting. Training writes a separate candidate artifact and report; it does not overwrite the runtime model unless `--replace` is explicitly provided. Synthetic data are not field evidence.

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

## External freshwater-fishpond candidate

`prepare_fishpond_candidate.py` creates a derived four-sensor training file from
the public Zenodo freshwater-fishpond CSV. It keeps timestamp, temperature, pH,
dissolved oxygen, and turbidity. It excludes `class`, sample ID, EC, TDS, and
ORP. Each complete 10-minute bucket is the arithmetic mean of its two 5-minute
records; incomplete buckets are discarded and never interpolated. The original
CSV is not modified or stored in this repository. The Zenodo record identifies
the source as CC BY 4.0. Attribute the authors (Giva Andriana Mutiara, Muhammad
Rizqy Alfarisi, and Lisda Meisaroh), link DOI 10.5281/zenodo.19210095 and the
license, and describe the changes (four selected sensors, complete-pair
ten-minute means, excluded fields). Keep that attribution beside any shared
derived dataset; this is project guidance, not legal advice.

Example PowerShell workflow from this directory:

```powershell
$prepared = Join-Path $env:TEMP 'fishpond_four_sensor_10min.csv'
$candidate = Join-Path $env:TEMP 'wqad_fishpond_candidate.joblib'
venv\Scripts\python.exe prepare_fishpond_candidate.py --dataset "D:\Users\SLUMDUNK\Downloads\fishpond_dataset_multiclass_2153.csv" --output $prepared
venv\Scripts\python.exe train_model.py --dataset $prepared --output $candidate --report "$env:TEMP\wqad_fishpond_evaluation.json" --sensors temp,pH,DO,turbidity --train-days 5 --origin external_freshwater_fishpond_proxy_unvalidated
venv\Scripts\python.exe evaluate_source_classes.py --dataset "D:\Users\SLUMDUNK\Downloads\fishpond_dataset_multiclass_2153.csv" --model $candidate --report "$env:TEMP\wqad_source_label_audit.json"
```

The fit, separate calibration period, and final chronological holdout are
purged by 144 minutes so overlapping two-hour windows do not cross splits. The
fixed 98th-percentile cutoff is calibrated without labels. `evaluation.json`
reports alert frequency and distribution shifts; neither is accuracy or a
guaranteed 2% false-alarm rate under temporal drift. A separate
`evaluate_source_classes.py` audit can compare final holdout alerts with the
dataset's `class` labels after training. Those labels are rule-generated from
seven sensors, not independent biological truth, and never affect fitting or
cutoff selection.

The dataset covers about 7.5 days and represents freshwater fishponds, not
CrayCare's crayfish tank. The current chronological holdout has no `Normal`
source-label rows; it therefore cannot estimate normal-water specificity or
meaningful overall accuracy. On this holdout, the candidate flagged 90 of 330
source-labeled `Warning`/`Severe` records (27.3%), missing the other 240. This
is only a post-hoc comparison to the source's rule labels, not a biological
accuracy claim. The candidate is deployed only for monitored integration
testing, not validated production use. Do not lower or raise its cutoff merely
to make the dashboard show fewer alerts.

## Production requirement

For testing, feature-version-2 is now the checked-in and deployed runtime bundle for `run_wqad_analysis` in Firebase project `craycare-8436c` (deployed 2026-10-03). It runs on the existing 30-minute schedule and writes only the WQAD `current` and detection-history results for the active assigned tank; this deployment did not seed or alter sensor readings. The earlier version-1 rollback copy was intentionally removed after version 2 became the test model. The deployed version-2 bundle remains an unvalidated freshwater-fishpond proxy, not a validated crayfish detector; the deployment is for monitored testing only.

Before final field claims:

1. Calibrate the four water-quality sensors and collect continuous ten-minute history from the real pond.
2. Review gaps, impossible values, maintenance periods, and known sensor failures.
3. Select a stable reference period that represents normal tank operation.
4. Retrain the same unsupervised pipeline using that reference history.
5. Validate alerts prospectively and record farmer or aquaculture-review outcomes without converting sensor safety thresholds into ML class labels.
6. Update `training_data_origin` only after that validation is documented.

The 98th-percentile decision boundary is a statistical rarity cutoff learned from a separate reference calibration block. It is not a biological water-quality threshold, a probability, or a guarantee of a fixed alert rate after drift, and must not directly switch pumps or aerators. There is no honest way to promise fewer unusual results from this short proxy dataset alone: collect a sufficiently long, calibrated, representative period from the actual tank, freeze a normal reference interval in advance, and evaluate future periods separately. Stop or roll back the test deployment if it creates confusing or excessive alerts; do not treat the ML output as an automatic husbandry action.

## Training from collected history

`export_firestore.py` exports the selected tank to `real_sensor_history.csv`, without overwriting the synthetic dataset. It reads canonical sensor fields and remains compatible with older average-field records. Configure `CRAYCARE_TANK_ID` and application credentials before exporting. Exported timestamps are UTC. Export one tank at a time; do not mix tanks in a single reference history.

```powershell
venv\Scripts\python.exe train_model.py --dataset real_sensor_history.csv --origin real_field_unvalidated --train-days 40 --output wqad_candidate.joblib
```

The 40-day reference period is an example, not a required biological duration. Select it before inspecting the later holdout. The pipeline requires a later holdout and at least 100 usable reference rows. It rejects invalid aggregates, sorts and deduplicates timestamps, and restarts the twelve-row warm-up after a gap greater than one missed ten-minute slot, matching inference. One missed slot is tolerated; repeated or longer gaps restart the usable suffix. No future interpolation is used. Real-history fitting does not require labels. Without independent labels, the report contains alert frequency and drift diagnostics, not accuracy, precision, or recall. Synthetic event metrics are explicitly simulation-only. Back up the current runtime bundle before any future model replacement and document target-tank validation before production claims.

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
- [Zenodo dataset record, DOI 10.5281/zenodo.19210095](https://zenodo.org/records/19210095) and [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
