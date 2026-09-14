import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:craycare/models/crayfish_batch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('production date fields', () {
    final date = DateTime.utc(2026, 9, 11, 1, 50, 32);

    test('batch and harvest serializers write Firestore Timestamps', () {
      final batch = CrayfishBatch(
        batchId: 'batch-1',
        status: 'active',
        stockingDate: date,
        harvestDate: date,
      );
      final harvest = CrayfishHarvestRecord(
        id: 'harvest-1',
        batchId: 'batch-1',
        date: date,
        harvestedCount: 3,
        totalWeightKg: 0.12,
      );

      expect(batch.toJson()['stocking_date'], isA<Timestamp>());
      expect(batch.toJson()['stocking_date'].toDate().toUtc(), date);
      expect(batch.toJson()['harvest_date'], isA<Timestamp>());
      expect(harvest.toJson()['harvest_date'], isA<Timestamp>());
      expect(harvest.toJson()['harvest_date'].toDate().toUtc(), date);
      expect(harvest.abwGrams, 40);
      expect(harvest.toJson().containsKey('abw_grams'), isFalse);
    });

    test('batch readers accept Firestore Timestamp and legacy epoch-ms', () {
      final expectedMs = date.millisecondsSinceEpoch;
      for (final rawDate in [Timestamp.fromDate(date), expectedMs]) {
        final batch = CrayfishBatch.fromJson({
          'batch_id': 'batch-1',
          'stocking_date': rawDate,
          'harvest_date': rawDate,
        });
        expect(batch.stockingDate.toUtc(), date);
        expect(batch.harvestDate!.toUtc(), date);

        final harvest = CrayfishHarvestRecord.fromJson('harvest-1', {
          'batch_id': 'batch-1',
          'harvest_date': rawDate,
        });
        expect(harvest.date.toUtc(), date);
      }
    });

    test(
      'days in culture derive from stocking and harvest dates, not storage',
      () {
        final stocked = DateTime(2026, 9, 1);
        final harvested = DateTime(2026, 9, 11);
        final completed = CrayfishBatch(
          batchId: 'batch-1',
          status: 'harvested',
          stockingDate: stocked,
          harvestDate: harvested,
        );
        final legacyCompleted = CrayfishBatch.fromJson({
          'batch_id': 'batch-legacy',
          'batch_status': 'harvested',
          'stocking_date': Timestamp.fromDate(stocked),
          'harvest_date': Timestamp.fromDate(harvested),
          'days_in_culture': 999,
        });
        final active = CrayfishBatch(
          batchId: 'batch-2',
          status: 'active',
          stockingDate: DateTime.now().subtract(const Duration(days: 3)),
        );

        expect(completed.daysInCulture, 10);
        expect(legacyCompleted.daysInCulture, 10);
        expect(active.daysInCulture, 3);
        expect(completed.toJson().containsKey('days_in_culture'), isFalse);
      },
    );

    test('superseded batch days stop at ended_at', () {
      final batch = CrayfishBatch.fromJson({
        'batch_id': 'batch-old',
        'batch_status': 'superseded',
        'stocking_date': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'ended_at': Timestamp.fromDate(DateTime(2026, 9, 8)),
      });
      expect(batch.daysInCulture, 7);
    });

    test('batch averages derive from raw totals and are not serialized', () {
      final batch = CrayfishBatch.fromJson({
        'batch_id': 'batch-1',
        'stocking_date': Timestamp.fromDate(date),
        'sample_count': 10,
        'initial_total_weight': 250,
        'initial_total_length': 90,
      });

      expect(batch.initialAbw, 25);
      expect(batch.initialAbl, 9);
      expect(batch.toJson().containsKey('initial_abw'), isFalse);
      expect(batch.toJson().containsKey('initial_abl'), isFalse);
      expect(batch.toJson().containsKey('final_abw'), isFalse);
      expect(batch.toJson().containsKey('final_abl'), isFalse);
    });

    test('batch reader supports legacy averages but prefers raw totals', () {
      final batch = CrayfishBatch.fromJson({
        'batch_id': 'batch-1',
        'stocking_date': Timestamp.fromDate(date),
        'sample_count': 10,
        'initial_total_weight': 250,
        'initial_total_length': 90,
        'initial_abw': 99,
        'initial_abl': 99,
        'final_abw': 80,
        'final_abl': 13,
      });

      expect(batch.initialAbw, 25);
      expect(batch.initialAbl, 9);
      expect(batch.finalAbw, 80);
      expect(batch.finalAbl, 13);
      final hydrated = batch.withFinalSamplingAverages(abw: 82, abl: 14);
      expect(hydrated.finalAbw, 82);
      expect(hydrated.finalAbl, 14);
      expect(batch.finalAbw, 80);
    });

    test('harvest ABW is derived from stored count and total weight', () {
      final record = CrayfishHarvestRecord.fromJson('harvest-1', {
        'batch_id': 'batch-1',
        'harvest_date': Timestamp.fromDate(date),
        'harvest_count': 4,
        'total_weight_kg': 0.34,
        'abw_grams': 999,
      });

      expect(record.abwGrams, 85);
      expect(record.toJson().containsKey('abw_grams'), isFalse);
    });
  });
}
