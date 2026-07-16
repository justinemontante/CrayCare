const Map<String, Map<String, double>> defaultRanges = {
  'temp': {'min': 24.0, 'max': 30.0},
  'ph': {'min': 7.0, 'max': 8.5},
  'do': {'min': 4.5, 'max': 999.0},
  'turb': {'min': 0.0, 'max': 35.0},
  'waterlevel': {'min': 5.0, 'max': 10.0},
};

const Map<String, SensorInfo> sensorInfo = {
  'temp': SensorInfo('Temperature', '°C'),
  'ph': SensorInfo('pH Level', 'pH'),
  'do': SensorInfo('Dissolved O₂', 'mg/L'),
  'turb': SensorInfo('Turbidity', 'NTU'),
  'waterlevel': SensorInfo('Water Level', 'cm'),
};

class SensorInfo {
  final String label;
  final String unit;
  const SensorInfo(this.label, this.unit);
}