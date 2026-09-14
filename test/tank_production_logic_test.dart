import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/services/tank_service.dart';

void main() {
  group('tank production logic', () {
    test('sampling size uses the planned size when enough crayfish remain', () {
      expect(effectiveSamplingSize(10, 80), 10);
    });

    test('sampling size safely follows a smaller in-tank population', () {
      expect(effectiveSamplingSize(10, 8), 8);
      expect(effectiveSamplingSize(10, 0), 0);
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

    test('growth stage uses ABW as the primary classification basis', () {
      expect(classifyGrowthStage(abw: 55, abl: 3), GrowthStage.marketSize);
      expect(
        classifyGrowthStage(abw: 12, abl: 10),
        GrowthStage.advancedJuvenile,
      );
    });

    test('growth stage falls back to ABL when ABW is unavailable', () {
      expect(classifyGrowthStage(abw: 0, abl: 7), GrowthStage.preAdult);
    });
  });
}
