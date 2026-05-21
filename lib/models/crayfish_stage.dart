class CrayfishStage {
  final String name;
  final String label;
  final String description;
  final double threshold;

  const CrayfishStage({
    required this.name,
    required this.label,
    required this.description,
    required this.threshold,
  });

  static const List<CrayfishStage> all = [
    CrayfishStage(
      name: 'early_juvenile',
      label: 'Early Juvenile',
      description: '1–3 mo | 2–4 cm | 1–5 g',
      threshold: 0.0,
    ),
    CrayfishStage(
      name: 'advanced_juvenile',
      label: 'Advanced Juvenile',
      description: '3–4 mo | 4–6 cm | 5–15 g',
      threshold: 5.0,
    ),
    CrayfishStage(
      name: 'growout_phase',
      label: 'Grow-out Phase',
      description: '4–6 mo | 6–10 cm | 15–50 g',
      threshold: 15.0,
    ),
    CrayfishStage(
      name: 'market_size',
      label: 'Market Size / Adult',
      description: '6–9+ mo | > 10 cm | 50 g +',
      threshold: 50.0,
    ),
  ];

  static CrayfishStage fromName(String name) =>
      all.firstWhere((s) => s.name == name, orElse: () => all[2]);
}

const Map<String, Map<String, Map<String, double>>> defaultStageRanges = {
  'early_juvenile': {
    'temp': {'min': 26.0, 'max': 28.0},
    'ph': {'min': 7.5, 'max': 8.0},
    'do': {'min': 5.0, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 25.0},
    'waterlevel': {'min': 120.0, 'max': 160.0},
  },
  'advanced_juvenile': {
    'temp': {'min': 25.0, 'max': 30.0},
    'ph': {'min': 7.0, 'max': 8.5},
    'do': {'min': 5.0, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 30.0},
    'waterlevel': {'min': 120.0, 'max': 170.0},
  },
  'growout_phase': {
    'temp': {'min': 24.0, 'max': 30.0},
    'ph': {'min': 7.0, 'max': 8.5},
    'do': {'min': 4.5, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 35.0},
    'waterlevel': {'min': 130.0, 'max': 180.0},
  },
  'market_size': {
    'temp': {'min': 24.0, 'max': 28.0},
    'ph': {'min': 7.0, 'max': 8.0},
    'do': {'min': 4.0, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 40.0},
    'waterlevel': {'min': 130.0, 'max': 180.0},
  },
};

const Map<String, SensorInfo> sensorInfo = {
  'temp': SensorInfo('Temperature', '\u00B0C'),
  'ph': SensorInfo('pH Level', 'pH'),
  'do': SensorInfo('Dissolved O\u2082', 'mg/L'),
  'turb': SensorInfo('Turbidity', 'NTU'),
  'waterlevel': SensorInfo('Water Level', 'cm'),
};

class SensorInfo {
  final String label;
  final String unit;
  const SensorInfo(this.label, this.unit);
}
