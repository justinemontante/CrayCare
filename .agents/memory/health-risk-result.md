---
name: HealthRiskResult Flutter model
description: Flutter HealthRiskResult model fields — no score field; classification-only
---

## Rule
`HealthRiskResult` in `lib/services/health_risk_service.dart` has NO `score` field.

**Why:** The ML pipeline no longer outputs a 0–100 score. The score was internal-only during training and was removed from Firestore output. Adding it back would cause a runtime mismatch.

## Current fields
```dart
class HealthRiskResult {
  final String level;       // "Low" | "Moderate" | "High" | "Critical" | "Insufficient"
  final int confidence;     // 0–100
  final String driver;      // sensor name e.g. "pH"
  final String problem;     // short description
  final String action;      // recommended action
  final String source;      // "ml" | "insufficient_data"
  final DateTime timestamp;
}
```

## UI components that use HealthRiskResult
- `lib/widgets/dashboard/health_risk_card.dart` — dashboard summary card
- `lib/widgets/analytics/movable_ai_logo.dart` — floating AI button → bottom sheet
  - Uses `_buildClassificationCard()` (level badge + confidence chip + driver chip)
  - OLD: `_buildScoreCard()` — **deleted**, do not restore

## How to apply
- If adding a new widget that displays health risk data, use `level`, `confidence`, `driver` — never `score`
- `fromMap()` reads `level`, `confidence`, `driver`, `problem`, `action`, `source`, `timestamp` from Firestore — no `score` key
