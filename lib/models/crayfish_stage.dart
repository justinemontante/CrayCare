class CrayfishStage {
  final String name;
  final String label;
  final String description;

  const CrayfishStage({
    required this.name,
    required this.label,
    required this.description,
  });

  static const List<CrayfishStage> all = [
    CrayfishStage(
      name: 'nursery',
      label: 'Nursery',
      description: '0–30 days — hatchlings',
    ),
    CrayfishStage(
      name: 'juvenile',
      label: 'Juvenile',
      description: '30–60 days — growing',
    ),
    CrayfishStage(
      name: 'growout',
      label: 'Grow-out',
      description: '60–120 days — main growth',
    ),
    CrayfishStage(
      name: 'preharvest',
      label: 'Pre-harvest',
      description: '120+ days — mature',
    ),
  ];

  static CrayfishStage fromName(String name) =>
      all.firstWhere((s) => s.name == name, orElse: () => all[2]);
}

const Map<String, Map<String, Map<String, double>>> defaultStageRanges = {
  'nursery': {
    'temp': {'min': 26.0, 'max': 28.0},
    'ph': {'min': 7.5, 'max': 8.0},
    'do': {'min': 5.0, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 25.0},
    'waterlevel': {'min': 120.0, 'max': 160.0},
  },
  'juvenile': {
    'temp': {'min': 25.0, 'max': 30.0},
    'ph': {'min': 7.0, 'max': 8.5},
    'do': {'min': 5.0, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 30.0},
    'waterlevel': {'min': 120.0, 'max': 170.0},
  },
  'growout': {
    'temp': {'min': 24.0, 'max': 30.0},
    'ph': {'min': 7.0, 'max': 8.5},
    'do': {'min': 4.5, 'max': 999.0},
    'turb': {'min': 0.0, 'max': 35.0},
    'waterlevel': {'min': 130.0, 'max': 180.0},
  },
  'preharvest': {
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
