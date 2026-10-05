import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/services/tank_service.dart';

void main() {
  group('tank production logic', () {
    test('sampling size stays fixed to the baseline size', () {
      expect(baselineSamplingSize(10), 10);
      expect(baselineSamplingSize(0), 0);
    });

    test('sampling averages derive from raw totals and sample size', () {
      expect(deriveSamplingAverage(total: 40, sampleSize: 10), 4);
      expect(deriveSamplingAverage(total: 30, sampleSize: 10), 3);
    });

    test('legacy sampling average is used when source totals are absent', () {
      expect(
        deriveSamplingAverage(total: null, sampleSize: 0, legacyAverage: 4.5),
        4.5,
      );
      expect(deriveSamplingAverage(total: 40, sampleSize: 0), 0);
    });

    test(
      'sampling biomass derives from source measurements and live count',
      () {
        final entry = SamplingEntry(
          date: DateTime(2026, 9, 13),
          abw: 4,
          avgLength: 3,
          sampleSize: 10,
          totalWeight: 40,
          totalLength: 30,
          liveCount: 100,
        );

        expect(entry.biomass, 400);
      },
    );

  });
}
