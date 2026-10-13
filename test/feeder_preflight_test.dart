import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  const ranges = {
    'temp': {'min': 24.0, 'max': 32.0},
    'do': {'min': 5.0, 'max': 9.0},
    'ph': {'min': 6.0, 'max': 8.0},
    'turb': {'min': 3.0, 'max': 50.0},
    'feedlevel': {'min': 20.0, 'max': 100.0, 'critical': 10.0},
  };

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
    ranges: ranges,
    grams: grams,
  );

  test('out-of-range water readings warn but do not block feeding', () {
    expect(check(turbidity: 55), isEmpty);
    expect(check(oxygen: 3), isEmpty);
    expect(check(oxygen: 10), isEmpty);
    expect(check(temperature: 33), isEmpty);
    expect(check(ph: 9), isEmpty);

    final warnings = feederWaterQualityWarnings(
      values: {'temp': 33, 'do': 3, 'ph': 9, 'turb': 55},
      freshSensors: {'temp', 'do', 'ph', 'turb'},
      ranges: ranges,
    );
    expect(warnings, hasLength(4));
    expect(warnings.join(' '), contains('Temperature is above range'));
    expect(warnings.join(' '), contains('Dissolved oxygen is below range'));
    expect(warnings.join(' '), contains('pH is above range'));
    expect(warnings.join(' '), contains('Turbidity is above range'));
  });

  test(
    'critical hopper, missing/stale sensors, and probe in air still block',
    () {
      expect(check(level: 10), contains('critical'));
      expect(check(level: 0), contains('critical'));
      expect(
        check(fresh: {'temp', 'do', 'ph', 'feedlevel'}),
        contains('Waiting for fresh turbidity data'),
      );
      expect(check(turbidityAir: true), contains('Turbidity probe is in air'));
      expect(
        feederWaterQualityWarnings(
          values: {'turb': 55},
          freshSensors: {'turb'},
          ranges: ranges,
          turbidityAir: true,
        ),
        isEmpty,
      );
    },
  );

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
      expect(check(grams: 21), isEmpty);
      expect(check(grams: 5), isEmpty);
      expect(check(grams: null), isEmpty);
      expect(check(grams: 0), isNotEmpty);
      expect(check(grams: 2.5), isNotEmpty);
      expect(check(grams: 201), isNotEmpty);
    },
  );
}
