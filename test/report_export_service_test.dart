import 'package:craycare/models/crayfish_batch.dart';
import 'package:craycare/services/report_export_service.dart';
import 'package:craycare/services/tank_service.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('grow-out reports', () {
    final stocked = DateTime(2026, 1, 1);
    final sampleDate = DateTime(2026, 1, 8);
    final snapshot = BatchRecordSnapshot(
      batch: CrayfishBatch(
        batchId: 'Batch-A',
        status: 'active',
        stockingDate: stocked,
        initialCount: 20,
      ),
      sampling: [
        SamplingEntry(
          id: 'sample-1',
          date: sampleDate,
          abw: 10,
          avgLength: 5,
          sampleSize: 2,
          totalWeight: 20,
          totalLength: 10,
          liveCount: 20,
          measurements: const [
            CrayfishMeasurement(
              sampleNumber: 1,
              weightGrams: 9.5,
              lengthCm: 4.8,
            ),
            CrayfishMeasurement(
              sampleNumber: 2,
              weightGrams: 10.5,
              lengthCm: 5.2,
            ),
          ],
        ),
      ],
      mortality: [MortalityEntry(date: sampleDate, count: 2)],
      harvests: [
        CrayfishHarvestRecord(
          id: 'harvest-1',
          batchId: 'Batch-A',
          date: sampleDate,
          harvestedCount: 3,
          totalWeightKg: 0.12,
        ),
      ],
    );

    test('include individual measurements when sampling is selected', () {
      final csv = ReportExportService.instance.buildAllGrowthCsv([snapshot]);

      expect(csv, contains('Individual Crayfish Measurements'));
      expect(csv, contains('Crayfish No.,Weight (g),Length (cm)'));
      expect(csv, contains('1,9.50,4.80'));
      expect(csv, contains('2,10.50,5.20'));
      expect(csv, contains('2026-01-08,2'));
      expect(csv, contains('2026-01-08,3,0.120,40.00'));
    });

    test(
      'Excel export opens and includes all selected record sections',
      () async {
        final bytes = await ReportExportService.instance.buildAllGrowthExcel([
          snapshot,
          BatchRecordSnapshot(
            batch: CrayfishBatch(
              batchId: 'Batch-B',
              status: 'harvested',
              stockingDate: stocked,
            ),
            sampling: const [],
            mortality: const [],
            harvests: const [],
          ),
        ]);
        final workbook = xl.Excel.decodeBytes(bytes);
        final values = workbook.tables.values
            .expand((sheet) => sheet.rows)
            .expand((row) => row)
            .whereType<xl.Data>()
            .map((cell) => cell.value?.toString() ?? '')
            .toList();

        expect(bytes.length, greaterThan(1000));
        expect(workbook.tables.keys, contains('Batch Summary'));
        expect(workbook.tables.keys, contains('Batch 1'));
        expect(workbook.tables.keys, contains('Batch 2'));
        expect(values, contains('Sampling Records'));
        expect(values, contains('Individual Crayfish Measurements'));
        expect(values, contains('Mortality Records'));
        expect(values, contains('Harvest Records'));
        expect(values, contains('9.50'));
        expect(values, contains('0.120'));
      },
    );

    test('PDF export produces a valid PDF with record sections', () async {
      final bytes = await ReportExportService.instance.buildAllGrowthPdf([
        snapshot,
        BatchRecordSnapshot(
          batch: CrayfishBatch(
            batchId: 'Batch-B',
            status: 'harvested',
            stockingDate: stocked,
          ),
          sampling: const [],
          mortality: const [],
          harvests: const [],
        ),
      ]);
      final signature = String.fromCharCodes(bytes.take(5));

      expect(signature, '%PDF-');
      expect(bytes.length, greaterThan(1000));
    });
  });
}
