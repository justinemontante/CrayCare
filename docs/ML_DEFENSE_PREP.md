# ML Defense Prep — CrayCare WQAD

Working sheet for the panel defense of the Machine Learning component.
Every answer here is traceable to the code, the model artifact, or the test
suite. Nothing in this file is an estimate.

---

## How to use this sheet

1. Memorize the 30-second model description below. If the panel remembers one
   thing about your ML, make it this.
2. Answer in three beats: claim, evidence, boundary. Never skip the boundary.
   The boundary is what makes the rest believable.
3. When you do not know, say what you would measure and how. That answer
   scores better than a guess.

---

## The 30-second model description

CrayCare uses an unsupervised Isolation Forest that reads four water-quality
sensors, temperature, pH, dissolved oxygen, and turbidity, over a continuous
two-hour window. It learns what the usual combined pattern looks like from a
reference dataset, then flags readings whose pattern is rare relative to that
reference. The result is advisory only. It never operates the pump, the
aerator, or the feeder. Those stay with the configured sensor thresholds.

---

## The 8 panel questions

### Q1. Why Isolation Forest? Why not a neural network, Random Forest, or LSTM?

Short answer:
Isolation Forest fits the problem we actually have. We have no outcome
labels, roughly 75,000 rows, and four correlated sensors on a slow-moving
physical system. Isolation Forest detects rare patterns without labels, trains
in seconds, is stable on small feature counts, and gives a continuous score
we can calibrate, which lets us explain every result.

If pressed:
Isolation Forest isolates anomalies by random partitioning, so it measures
rarity rather than learning a boundary between classes. That is what we need
when the question is "does this pattern look unusual" and not "is this
disease". A neural network or LSTM would need labeled examples and would
overfit a dataset with only three source series. Random Forest would also
require labels. We use 300 trees, a maximum of 256 samples per tree, all
features per split, and contamination set to auto, with a fixed random seed
of 42 so every run is reproducible.

Boundary to state:
Isolation Forest gives a similarity score, not a diagnosis. It cannot tell
you why water is unusual, only that the pattern is rare.

Evidence:
`functions/ml/train_model.py` lines 56 to 57, `functions/ml/test_model_artifact.py`,
model artifact fields `algorithm`, `n_estimators`, `random_state`.

---

### Q2. Your model is unsupervised. Where did the labels come from?

Short answer:
There are no labels, and that was deliberate. We did not want to convert
sensor safety thresholds into class labels, because then the model would only
reproduce the thresholds we already have and would lose the ability to catch
combined patterns that no single threshold covers.

If pressed:
The bundle records `training_labels_used: False`. The model is fitted on
sensor-derived features only. Then we split the data chronologically, fit on
the first part, choose the decision boundary on a later unseen part, and
measure the alert rate on a final later part. The evaluation label origin is
recorded as none. We report an alert rate, not accuracy, and we say so
explicitly in the training report.

Boundary to state:
Unsupervised means the model learns what normal looks like, not what bad
means. It finds unusual combinations. It cannot prove that water is unsafe,
and it is not a substitute for the separate threshold alerts.

Evidence:
`functions/ml/train_model.py` line 71 `training_labels_used: False`,
artifact field `training_labels_used`, report field `evaluation_label_origin`,
and the limitations list in the training report.

---

### Q3. What is your accuracy? I need precision, recall, and F1.

Short answer:
We cannot report precision, recall, or F1, and the bundle says so rather
than publishing a number we cannot defend. The dataset has no outcome labels,
so those metrics are not computable. Instead we report a calibrated alert rate
of 2.19 percent on a purged chronological holdout, and we list the limitations
explicitly.

If pressed:
A self-supervised alert rate is not accuracy. Our fixed 98th percentile
cutoff flagged 2.19 percent of holdout rows, which is consistent with the
cutoff we chose and was not tuned on the holdout. To produce real
precision and recall we need an independent outcome record, for example
farmer-confirmed events, and then we can label against it without converting
thresholds into labels. That is step five of our field validation plan.

Boundary to state:
The 2.19 percent is an alert rate, not a false-positive rate, and it is not
guaranteed to hold after drift. Our own training report states that the
alert fraction is not accuracy or a measured false-positive rate.

Evidence:
Artifact `prototype_metrics: {precision: None, recall: None, f1: None}`,
artifact `holdout_alert_fraction: 0.0219`, report `limitations` list,
`functions/ml/README.md` production requirement section.

---

### Q4. You trained on a fishpond dataset. Shouldn't you have used your own crayfish tank data?

Short answer:
Yes, and that is exactly what we intend to do next. We used an external
freshwater fishpond dataset as a proxy because we did not yet have a long,
calibrated, continuous ten-minute history from our own tank. The bundle
records that origin honestly as an unvalidated proxy, and it is the first
limitation our own training report lists.

If pressed:
The proxy came from three stations, 74,729 complete four-sensor rows after
cleaning, and roughly a 20-minute source cadence. Live inference runs on a
10-minute cadence. We kept the same two-hour feature horizons in both so the
windows line up, but equal horizons do not prove equal feature
distributions, and our README says that. The migration path already exists
in code. `export_firestore.py` exports a real tank, and `train_model.py`
accepts `--origin real_field_unvalidated` to retrain the identical pipeline
on our own history.

Boundary to state:
The current model is a prototype reference pattern, not a validated crayfish
model. We will not change the recorded origin until prospective validation on
the target tank is documented.

Evidence:
Artifact `training_data_origin: external_freshwater_fishpond_proxy_unvalidated`,
`functions/ml/README.md` sections on the training dataset and the six-step
field validation plan, `functions/ml/export_firestore.py`.

---

### Q5. How do you prevent data leakage? How did you split the data?

Short answer:
Chronologically, with a purge, and the cutoff is chosen on a block the model
never saw. The order is fit, then calibrate, then holdout, each later in
time than the last.

If pressed:
The first 80 percent of unique timestamps form the reference block. The first
75 percent of that block fits the forest, 45,814 rows. The remaining 25
percent, after a 144-minute purge, is the calibration block, 15,245 rows,
and it is where the 98th percentile cutoff is computed. The final 20 percent
of the timeline, again after the purge, is the holdout, 13,560 rows. The
144-minute purge exists so that no raw two-hour input window can straddle a
split boundary. The calibration block and the holdout never fit the model.

Boundary to state:
This protects against temporal leakage. It does not protect against the
proxy dataset being different from our tank, which is question 4.

Evidence:
`functions/ml/train_model.py` lines 40 to 55, artifact fields
`training_rows`, `calibration_rows`, `holdout_rows`, `purge_minutes: 144`,
`source_reference_fraction: 0.8`, `validation_strategy:
chronological_fit_then_calibration_then_purged_holdout`.

---

### Q6. What exactly is the anomaly score? Is it a probability that the water is unsafe?

Short answer:
No. It is a percentile showing how rare the current pattern is compared with
the model's learned reference. A higher score means the pattern is less
common in the reference data. It is not a probability, not a confidence, and
not a biological safety level.

If pressed:
We use the negative of scikit-learn's `score_samples` as the raw score, then
convert it to a percentile against the calibration block. The cutoff is the
98th percentile of that later block, computed independently of the holdout.
The app displays Normal, Unusual, or Insufficient. Normal means the pattern
resembles the learned reference, and it does not mean the water is safe. The
contributing sensors are a sensitivity diagnostic. We replace one sensor's
block with its median and measure how much the score drops. That is a
score-reduction diagnostic, not a causal explanation, and it is not SHAP.

Boundary to state:
The same input can be biologically dangerous and still score Normal. Our own
README records that stable inputs with pH 14, dissolved oxygen 0 mg/L, or
turbidity 250 NTU can still receive a Normal result. This is why the detector
never replaces the threshold alerts.

Evidence:
`functions/ml/anomaly_features.py` scoring and contributor code,
artifact `raw_score_method: negative_score_samples`, `decision_basis:
independent_chronological_calibration_percentile`, artifact
`contributor_method: positive_sensor_block_median_replacement_score_reduction`,
`functions/ml/README.md` opening section.

---

### Q7. How is this deployed and triggered? I expected a scheduled job.

Short answer:
It is event-triggered. Every time the ESP32 writes a new ten-minute history
record, the Cloud Function runs once on that new record. There is no
fifteen-minute timer, and no scheduled job.

If pressed:
The trigger is `on_document_created` on
`tanks/{tank_id}/sensor_readings_history/{date}/entries/{entry_id}`. The
function reads back a 2.5-hour slice of history and keeps a continuous
two-hour window based on actual capture times, not an assumed record count.
The window needs at least six valid readings spanning at least 110 minutes.
The observed cadence must be between 480 and 1800 seconds. A gap larger than
2.2 times that cadence rebuilds the window from the last valid record, and
missing readings are never interpolated. If the newest record is older than
20 minutes the result is Insufficient and marked stale rather than analysed.

The write is idempotent. The document id is built from the source reading
timestamp and entry id, so a retried event produces one document, and an
older event never replaces a newer result. Before inference the function
checks that the record belongs to the active assignment, that the tank and
owner match, and that the assignment timestamp matches, so one owner's data
can never be analysed against another owner's tank.

Boundary to state:
The result is written only to
`tanks/{tankId}/water_quality_anomaly_detection_history`. There is no
separate current document. The app reads the newest processed_at record.

Evidence:
`functions/ml/main.py` trigger and guards, `functions/ml/anomaly_window.py`
window constants, `functions/ml/test_anomaly_window.py`, artifact
`analysis_window_minutes: 120`.

---

### Q8. What are the limitations, and how will you validate this on the real tank?

Short answer:
We have four documented limitations, and we have a six-step validation plan.
We are not claiming field validity yet.

If pressed:
The four limitations are that the alert fraction is not accuracy, that the
reference data may itself contain degraded conditions since no class labels
were used, that temporal dependence and distribution shift invalidate any
fixed false-alarm guarantee, and that the public fishpond proxy has not been
validated on our target crayfish tank.

The plan is six steps. One, calibrate the four sensors and collect continuous
ten-minute history from the real pond. Two, review gaps, impossible values,
maintenance periods, and known sensor failures. Three, select a stable
reference period that represents normal operation and freeze it in advance.
Four, retrain the same unsupervised pipeline on that reference history.
Five, validate prospectively and record farmer or aquaculture-review outcomes,
without converting safety thresholds into class labels. Six, update the
recorded origin only after that validation is documented.

Boundary to state:
We also have a rollback rule. If the test deployment produces confusing or
excessive alerts we stop or roll it back, and we never treat the ML output as
an automatic husbandry action.

Evidence:
`functions/ml/README.md` production requirement and field validation
sections, `functions/ml/train_model.py` report `limitations` list,
artifact `training_data_origin`.

---

## 2 likely follow-ups

### F1. Why doesn't the ML control the pump or aerator automatically?

Because the model's score is a rarity percentile, not a safety signal. If we
let a statistical rarity score switch actuators, a statistically unusual but
biologically fine reading could switch the pump, and a genuinely dangerous
reading could score Normal, which our own checks show. So the ML produces
advice, and the configured sensor thresholds, with validated actuator rules,
remain the only thing that operates the pump, the aerator, and the feeder.
The recommendations themselves are phrased as verification steps, such as
recheck the probe and inspect aeration, and never as a diagnosis or a
chemical treatment. This is also why the RAS reference document states the
action boundary explicitly.

Evidence:
`functions/ml/anomaly_recommendations.json`, `functions/ml/anomaly_interpreter.py`,
`docs/Deliverables/CrayCare RAS ML Recommendation References.docx`.

### F2. Why only four sensors? Why not water level or feed level?

Water level and feed level are intentionally outside the ML input. The model
learns water-quality patterns, and level and feed are operational context
handled by separate rules, since feed events and level changes are better
handled as configured-threshold checks. Keeping the input to four sensors also
keeps the feature set stable and interpretable, and the runtime refuses to
load any artifact whose sensor list is not exactly those four, so a
five-sensor model cannot be deployed by accident.

Evidence:
`functions/ml/main.py` `_WQAD_SENSORS`, the load-time artifact validation,
`functions/ml/README.md` opening section, artifact `sensors` field.

---

## Numbers you must be able to say without looking

| Item | Value |
|---|---|
| Sensors in the ML | 4: temp, pH, DO, turbidity |
| Features | 36, feature version 3 |
| Model | IsolationForest, 300 trees, random_state 42 |
| Decision cutoff | 98th percentile of a later calibration block |
| Fit rows | 45,814 |
| Calibration rows | 15,245 |
| Holdout rows | 13,560 |
| Purge between splits | 144 minutes |
| Holdout alert rate | 2.19 percent, this is an alert rate, not accuracy |
| Live window | 2 hours, 6 readings minimum, 110 minutes minimum span |
| Cadence accepted | 480 to 1800 seconds |
| Window rebuild | gap over 2.2 times the cadence |
| Stale cutoff | 20 minutes |
| Labels used | None |
| Precision, recall, F1 | Not computable, no labels, and we say so |
| Training origin | External freshwater fishpond proxy, unvalidated on the target tank |
| Tests | 54 passing in the ML package, including 12 subtests |

---

## What not to say

1. Do not say the model detects disease. It does not.
2. Do not say Normal means the water is safe. It means the pattern resembles
   the reference.
3. Do not quote 2.19 percent as an accuracy or a false-positive rate.
4. Do not say the contributors are the cause. They are a score-reduction
   diagnostic.
5. Do not say the ML controls the actuators. It does not.
6. Do not say the model is validated. It is a proxy-based prototype, and the
   training origin field says so.

---

## If you are asked something not on this sheet

Answer like this. Name what you would measure, name the file or subsystem
that would change, and name the boundary of the current claim. For example:
we do not have a measured false-positive rate, and we can only get one by
running the six-step field validation on our own tank and recording outcomes.
That is more convincing than a number you cannot defend, because it shows you
know exactly what your model does not know.

---

## One-paragraph summary you can repeat

CrayCare's machine learning component is an unsupervised Isolation Forest
that reads temperature, pH, dissolved oxygen, and turbidity over a continuous
two-hour window of at least six valid readings. It is trained without
outcome labels, split chronologically with a 144-minute purge so no window
crosses a boundary, and its 98th percentile cutoff is chosen on a later
calibration block that never fits the model. It flagged 2.19 percent of a
final holdout, which we report as an alert rate and explicitly not as
accuracy. It is triggered by each new sensor history record, writes one
idempotent history document, and never operates the pump, aerator, or feeder.
Its results are advisory, its training data is an unvalidated external proxy,
and we have a documented six-step plan to validate it on the real tank before
any field claim.
