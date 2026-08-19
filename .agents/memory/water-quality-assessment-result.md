---
name: WaterQualityAssessmentResult Flutter model
description: Canonical Flutter result fields for Machine Learning-Based Water Quality Assessment
---

## Rule

`WaterQualityAssessmentResult` in
`lib/services/water_quality_assessment_service.dart` is the canonical Flutter
model. It does not expose the internal numeric hazard score.

## Current fields

- `level`: Good | Moderate | Poor | Critical | Insufficient
- `modelLevel`, `ruleLevel`, `safetyOverride`
- `confidence`
- `driver`, `driverLabel`, `driverValue`, `driverUnit`, `driverMin`, `driverMax`
- `problem`, `insight`, `action`, `timestamp`

The dashboard card, assessment history, AI insight sheet, and report export all
consume this model. Legacy stored condition values are normalized when read so
older assessment history remains usable.
