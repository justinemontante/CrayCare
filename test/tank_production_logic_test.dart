import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/services/tank_service.dart';

void main() {
  group('tank production logic', () {
    test('sampling size stays fixed to the baseline size', () {
      expect(baselineSamplingSize(10), 10);
      expect(baselineSamplingSize(0), 0);
    });

    test('in-tank count subtracts both mortality and harvest', () {
      expect(crayfishInTankCount(100, 10, 20), 70);
      expect(crayfishInTankCount(100, 90, 20), 0);
    });

    test('survival rate counts harvested crayfish as survivors', () {
      expect(crayfishSurvivalRatePercent(100, 10), 90);
      expect(crayfishSurvivalRatePercent(100, 150), 0);
      expect(crayfishSurvivalRatePercent(0, 0), 0);
    });

    test('harvest inputs reject non-finite or non-positive values', () {
      expect(() => validateHarvestInput(10, 1.25), returnsNormally);
      expect(() => validateHarvestInput(0, 1.25), throwsArgumentError);
      expect(() => validateHarvestInput(10, 0), throwsArgumentError);
      expect(
        () => validateHarvestInput(10, double.infinity),
        throwsArgumentError,
      );
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
