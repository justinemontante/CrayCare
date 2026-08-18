---
name: HealthRiskResult Flutter model
description: Flutter HealthRiskResult model fields — classification-only current contract
---

## Rule
`HealthRiskResult` in `lib/services/health_risk_service.dart` has NO `score`, `source`, `analysisMode`, `samplesAnalyzed`, or `requiredSamples` fields.

**Why:** The ML pipeline exposes only the fields needed by the app for the current WQC assessment. Internal model requirements and processing metadata are not stored as public result fields.

## Current fields
```dart
class HealthRiskResult {
  final String level;
  final int confidence;
  final String driver;
  final String problem;
  final String insight;
  final String action;
  final String driverLabel;
  final double? driverValue;
  final String driverUnit;
  final double? driverMin;
  final double? driverMax;
  final DateTime timestamp;
}
```

## UI components that use HealthRiskResult
- `lib/widgets/analytics/movable_ai_logo.dart` — floating AI button → bottom sheet
  - Uses classification level, confidence, driver details, insight, recommendation, and timestamp.
  - The source/analysis/sample-count metadata is intentionally not displayed.

## How to apply
- If adding a new widget that displays WQC data, use only the current model fields above.
- Do not restore `score`, `source`, `analysisMode`, `samplesAnalyzed`, or `requiredSamples` unless the Firestore output contract is deliberately redesigned first.
