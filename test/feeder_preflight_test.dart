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
    double turbidity = 10,
    bool turbidityAir = false,
    bool allowTurbidityConfirmation = false,
  }) => feederPreflightIssue(
    internetOnline: online,
    feederOnline: true,
    busy: busy,
    schedulesLoaded: loaded,
    turbidityAir: turbidityAir,
    values: {
      'temp': 27,
      'do': oxygen,
      'ph': 7,
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
    availableGrams: available,
    grams: grams,
    allowTurbidityConfirmation: allowTurbidityConfirmation,
  );
  test('critical percentage still allows enough estimated feed', () {
    expect(check(), isEmpty);
    expect(check(available: 20), contains('Insufficient feed'));
    expect(check(level: 0), contains('empty'));
  });
  test('high turbidity needs explicit confirmation to allow feeding', () {
    expect(check(turbidity: 55), contains('Turbidity too high'));
    expect(
      check(turbidity: 55, allowTurbidityConfirmation: true),
      isEmpty,
    );
    expect(
      check(turbidity: 55, allowTurbidityConfirmation: true, oxygen: 3),
      contains('Dissolved oxygen too low'),
    );
    expect(
      check(fresh: {'temp', 'do', 'ph', 'feedlevel'}),
      contains('Waiting for fresh turbidity data'),
    );
    expect(
      check(
        fresh: {'temp', 'do', 'ph', 'feedlevel'},
        allowTurbidityConfirmation: true,
      ),
      isEmpty,
    );
    expect(check(turbidityAir: true), contains('sensor is in air'));
    expect(
      check(turbidityAir: true, allowTurbidityConfirmation: true),
      isEmpty,
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
