# Agent Memory Index

- [WQC model renaming](wqc-rename.md) — WQRI renamed to WQC everywhere; score field fully removed from all layers
- [ML pipeline architecture](ml-pipeline.md) — XGBoost classifier flow, output schema, Firestore paths, model file
- [HealthRiskResult model](health-risk-result.md) — Flutter model has no score field; classification-only output
- [Multi-device isolation gaps](multi-device-gaps.md) — feeder + healthRisk collections have no uid filter; known limitation
- [Firestore index requirement](firestore-index.md) — sensorReadings/history needs composite index on timestamp ASC
