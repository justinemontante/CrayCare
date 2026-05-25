class CrayfishStage {
  final String name;
  final String label;
  final String description;
  final String lengthRange;
  final String weightRange;
  final double threshold;

  const CrayfishStage({
    required this.name,
    required this.label,
    required this.description,
    required this.lengthRange,
    required this.weightRange,
    required this.threshold,
  });

  static const List<CrayfishStage> all = [
    CrayfishStage(
      name: 'early_juvenile',
      label: 'Early Juvenile',
      description: 'Newly stocked young crayfish',
      lengthRange: '2 – 4 cm',
      weightRange: '1 – 5 g',
      threshold: 0.0,
    ),
    CrayfishStage(
      name: 'advanced_juvenile',
      label: 'Advanced Juvenile',
      description: 'Active early growth',
      lengthRange: '4 – 6 cm',
      weightRange: '5 – 15 g',
      threshold: 5.0,
    ),
    CrayfishStage(
      name: 'pre_adult',
      label: 'Pre-Adult',
      description: 'Preparing for full maturity',
      lengthRange: '6 – 10 cm',
      weightRange: '15 – 50 g',
      threshold: 15.0,
    ),
    CrayfishStage(
      name: 'market_size',
      label: 'Market Size',
      description: 'Ready for harvest',
      lengthRange: '> 10 cm',
      weightRange: '50 g+',
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
  'pre_adult': {
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
