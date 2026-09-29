import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  String check({
    bool online = true,
    bool busy = false,
    bool loaded = true,
    double level = 50,
    double? grams = 40,
    Set<String>? fresh,
    double temperature = 27,
    double oxygen = 6,
    double ph = 7,
    double turbidity = 10,
    bool turbidityAir = false,
    bool allowWaterQualityOverride = false,
  }) => feederPreflightIssue(
    internetOnline: online,
    feederOnline: true,
    busy: busy,
    schedulesLoaded: loaded,
    turbidityAir: turbidityAir,
    values: {
      'temp': temperature,
      'do': oxygen,
      'ph': ph,
      'turb': turbidity,
      'feedlevel': level,
    },
    freshSensors: fresh ?? {'temp', 'do', 'ph', 'turb', 'feedlevel'},
    ranges: {
      'temp': {'min': 24, 'max': 32},
      'do': {'min': 5},
      'ph': {'min': 6, 'max': 8},
      'turb': {'max': 50},
      'feedlevel': {'min': 20, 'max': 100, 'critical': 10},
    },
    grams: grams,
    allowWaterQualityOverride: allowWaterQualityOverride,
  );
  test('feed safety uses the configured percentage threshold only', () {
    expect(check(), isEmpty);
    expect(check(level: 20), isEmpty);
    expect(check(level: 10), contains('critical'));
    expect(check(level: 0), contains('critical'));
  });
  test('water-quality range override is explicit and request-scoped', () {
    expect(check(turbidity: 55), contains('Turbidity too high'));
    expect(check(turbidity: 55, allowWaterQualityOverride: true), isEmpty);
    expect(
      check(turbidity: 55, allowWaterQualityOverride: true, oxygen: 3),
      isEmpty,
    );
    expect(check(oxygen: 3, allowWaterQualityOverride: true), isEmpty);
    expect(check(temperature: 33), contains('Temperature outside range'));
    expect(check(temperature: 33, allowWaterQualityOverride: true), isEmpty);
    expect(check(ph: 9), contains('pH outside range'));
    expect(check(ph: 9, allowWaterQualityOverride: true), isEmpty);
    expect(
      check(level: 10, allowWaterQualityOverride: true),
      contains('critical'),
    );
    expect(
      check(fresh: {'temp', 'do', 'ph', 'feedlevel'}),
      contains('Waiting for fresh turbidity data'),
    );
    expect(
      check(
        fresh: {'temp', 'do', 'ph', 'feedlevel'},
        allowWaterQualityOverride: true,
      ),
      contains('Waiting for fresh turbidity data'),
    );
    expect(check(turbidityAir: true), contains('sensor is in air'));
    expect(
      check(turbidityAir: true, allowWaterQualityOverride: true),
      contains('sensor is in air'),
    );
    expect(
      check(
        fresh: {'do', 'ph', 'turb', 'feedlevel'},
        allowWaterQualityOverride: true,
      ),
      contains('Waiting for fresh temperature data'),
    );
  });
  test(
    'dispatch preflight rejects offline, busy, stale and invalid requests',
    () {
      expect(check(online: false), contains('internet'));
      expect(check(busy: true), contains('progress'));
      expect(check(loaded: false), contains('schedules'));
      expect(
        check(fresh: {'temp', 'ph', 'turb', 'feedlevel'}),
        contains('fresh'),
      );
      expect(check(oxygen: -1), contains('fresh'));
      expect(check(oxygen: 3), contains('too low'));
      expect(check(grams: 21), isEmpty);
      expect(check(grams: 5), isEmpty);
      expect(check(grams: null), isEmpty);
      expect(check(grams: 0), isNotEmpty);
      expect(check(grams: 2.5), isNotEmpty);
      expect(check(grams: 201), isNotEmpty);
    },
  );
}
