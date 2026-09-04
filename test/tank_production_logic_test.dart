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

    test('growth stage uses ABW as the primary classification basis', () {
      expect(
        classifyGrowthStage(abw: 55, abl: 3),
        GrowthStage.marketSize,
      );
      expect(
        classifyGrowthStage(abw: 12, abl: 10),
        GrowthStage.advancedJuvenile,
      );
    });

    test('growth stage falls back to ABL when ABW is unavailable', () {
      expect(
        classifyGrowthStage(abw: 0, abl: 7),
        GrowthStage.preAdult,
      );
    });
  });
}
