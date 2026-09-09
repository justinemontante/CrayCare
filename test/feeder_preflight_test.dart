import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  String check({
    bool online = true,
    bool busy = false,
    bool loaded = true,
    double level = 8,
    double available = 50,
    double? grams = 40,
    Set<String>? fresh,
    double oxygen = 6,
  }) => feederPreflightIssue(
    internetOnline: online,
    feederOnline: true,
    busy: busy,
    schedulesLoaded: loaded,
    turbidityAir: false,
    values: {'temp': 27, 'do': oxygen, 'ph': 7, 'turb': 10, 'feedlevel': level},
    freshSensors: fresh ?? {'temp', 'do', 'ph', 'turb', 'feedlevel'},
    ranges: {
      'temp': {'min': 24, 'max': 32},
      'do': {'min': 5},
      'ph': {'min': 6, 'max': 8},
      'turb': {'max': 50},
    },
    availableGrams: available,
    grams: grams,
  );
  test('critical percentage still allows enough estimated feed', () {
    expect(check(), isEmpty);
    expect(check(available: 20), contains('Insufficient feed'));
    expect(check(level: 0), contains('empty'));
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
      expect(check(grams: 21), isNotEmpty);
    },
  );
}
