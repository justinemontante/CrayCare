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
  }) => feederPreflightIssue(
    internetOnline: online,
    feederOnline: true,
    busy: busy,
    schedulesLoaded: loaded,
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

  test('only invalid or critical feed-level data blocks on sensor status', () {
    expect(check(level: 10), contains('critical'));
    expect(check(level: 0), contains('critical'));
    expect(check(level: 101), contains('valid feed-level'));
    expect(check(fresh: {'temp', 'do', 'ph', 'turb'}), contains('feed-level'));
    expect(check(fresh: {'temp', 'do', 'ph', 'turb', 'feedlevel'}), isEmpty);
  });

  test('turbidity in air is omitted from water-quality warnings', () {
    expect(check(fresh: {'feedlevel'}), isEmpty);

    final warnings = feederWaterQualityWarnings(
      values: {'temp': 27, 'do': 6, 'ph': 7.5, 'turb': 55},
      freshSensors: {'temp', 'do', 'ph', 'turb'},
      ranges: ranges,
      turbidityAir: true,
    );
    expect(warnings, isEmpty);
  });

  test('dispatch preflight rejects operationally invalid requests', () {
    expect(check(online: false), contains('internet'));
    expect(check(busy: true), contains('progress'));
    expect(check(loaded: false), contains('schedules'));
    expect(check(fresh: {'feedlevel'}), isEmpty);
    expect(check(oxygen: -1), isEmpty);
    expect(check(grams: 21), isEmpty);
    expect(check(grams: 5), isEmpty);
    // General readiness can be checked before the owner opens the dose form.
    expect(check(grams: null), isEmpty);
    expect(check(grams: 0), isNotEmpty);
    expect(check(grams: 2.5), isNotEmpty);
    expect(check(grams: 201), isNotEmpty);
  });

  test('a missing dose is invalid when validating a feeding input', () {
    expect(validateFeederGrams(null), 'Grams is required.');
  });
}
