import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'tank_service.dart';

/// Selects the detailed grow-out record sections included in an export.
class GrowOutReportSections {
  final bool includeSampling;
  final bool includeMortality;
  final bool includeHarvest;

  const GrowOutReportSections({
    this.includeSampling = true,
    this.includeMortality = true,
    this.includeHarvest = true,
  });

  bool get hasSelectedSection =>
      includeSampling || includeMortality || includeHarvest;

  String get selectedSectionsLabel =>
      [
        if (includeSampling) 'Sampling Records',
        if (includeMortality) 'Mortality Records',
        if (includeHarvest) 'Harvest Records',
      ].join(', ').isEmpty
      ? 'Batch Summary only'
      : [
          if (includeSampling) 'Sampling Records',
          if (includeMortality) 'Mortality Records',
          if (includeHarvest) 'Harvest Records',
        ].join(', ');
}

/// Builds grow-out CSV and PDF reports, then hands the file to the Android
/// share sheet so the owner can save it to Files/Drive or send it anywhere.
class ReportExportService {
  static final ReportExportService instance = ReportExportService._();
  ReportExportService._();

  // Report palette follows the CrayCare logo and in-app brand colors.
  // Table headers use the exact teal from the “Care” wordmark (#1FA5A5).
  static const PdfColor _careColor = PdfColor.fromInt(0xFF1FA5A5);
  static const PdfColor _crayColor = PdfColor.fromInt(0xFF0F172A);

  // ── CSV helpers ────────────────────────────────────────────────────────
  static String _cell(Object? value) {
    if (value == null) return '';
    final s = value.toString();
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    if (!needsQuote) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _row(List<Object?> cells) => '${cells.map(_cell).join(',')}\n';

  static String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static String _dateRange(DateTime start, DateTime end) {
    final startText = _fmtDate(start);
    final endText = _fmtDate(end);
    return startText == endText ? startText : '$startText to $endText';
  }

  static DateTime _culturePeriodEnd(TankService tank) =>
      tank.selectedBatch?.harvestDate ??
      tank.selectedBatch?.endedAt ??
      DateTime.now();

  static String _samplingPeriod(List<SamplingEntry> samples) {
    if (samples.isEmpty) return '-';
    final ordered = List<SamplingEntry>.of(samples)
      ..sort((a, b) => a.date.compareTo(b.date));
    return _dateRange(ordered.first.date, ordered.last.date);
  }

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_'
        '${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
  }

  static String _safeFileStem(String value) {
    final withoutExtension = value.trim().replaceFirst(
      RegExp(r'\.(csv|pdf|xlsx)$', caseSensitive: false),
      '',
    );
    final safe = withoutExtension
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    return safe.isEmpty ? 'craycare_all_batches' : safe;
  }

  /// Copies [text] to the system clipboard and returns whether it succeeded.
  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Replaces characters that the PDF's built-in font cannot render.
  static String _pdfSafe(String s) => s
      .replaceAll('\u2265', '>=') // ≥
      .replaceAll('\u2264', '<=') // ≤
      .replaceAll('\u2014', '-') // em dash
      .replaceAll('\u2013', '-') // en dash
      .replaceAll('\u2018', "'") // ‘
      .replaceAll('\u2019', "'") // ’
      .replaceAll('\u201C', '"') // “
      .replaceAll('\u201D', '"') // ”
      .replaceAll('\u2026', '...') // …
      .replaceAll('\u00B7', '-') // middle dot
      .replaceAll('\u00A0', ' '); // nbsp

  // ── Grow-out (production) CSV ──────────────────────────────────────────
  static const growthColumns = <String>[
    'Week',
    'Date',
    'Sample Size',
    'Sample Total Length (cm)',
    'Sample Total Weight (g)',
    'Avg Length (cm)',
    'Avg Weight (g)',
    'Est. Biomass (g)',
    'In-Tank Count',
  ];

  /// One shared table for both export formats. Weeks reflect elapsed calendar
  /// days since stocking, so a missed sampling week does not renumber history.
  static List<List<String>> growthRows(
    List<SamplingEntry> samples,
    DateTime stockingDate,
  ) {
    final ordered = List<SamplingEntry>.of(samples)
      ..sort((a, b) => a.date.compareTo(b.date));
    final start = DateTime.utc(
      stockingDate.year,
      stockingDate.month,
      stockingDate.day,
    );
    return ordered.map((s) {
      final day = DateTime.utc(s.date.year, s.date.month, s.date.day);
      final days = day.difference(start).inDays;
      final week = (days < 0 ? 0 : days) ~/ 7;
      return <String>[
        s.isBaseline ? 'Baseline' : 'Week $week',
        _fmtDate(s.date),
        '${s.sampleSize}',
        s.totalLength.toStringAsFixed(2),
        s.totalWeight.toStringAsFixed(2),
        s.avgLength.toStringAsFixed(2),
        s.abw.toStringAsFixed(2),
        s.biomass.toStringAsFixed(2),
        '${s.liveCount}',
      ];
    }).toList();
  }

  String buildGrowthCsv({
    GrowOutReportSections sections = const GrowOutReportSections(),
  }) {
    final t = TankService.instance;
    final buf = StringBuffer();

    buf.writeln('CrayCare Grow-Out Report');
    buf.writeln('Generated,${_fmtDateTime(DateTime.now())}');
    buf.writeln();
    buf.writeln(_row(['Summary']));
    buf.writeln(_row(['Batch ID', t.selectedBatchId ?? '-']));
    buf.writeln(_row(['Stocking Date', _fmtDate(t.stockingDate)]));
    buf.writeln(
      _row([
        'Culture Period',
        _dateRange(t.stockingDate, _culturePeriodEnd(t)),
      ]),
    );
    buf.writeln(_row(['Days in Culture', t.daysInCulture]));
    buf.writeln(_row(['Initial Population', t.initialCount]));
    buf.writeln(_row(['Initial ABW (g)', t.initialWeight.toStringAsFixed(2)]));
    buf.writeln(_row(['Initial ABL (cm)', t.initialLength.toStringAsFixed(2)]));
    buf.writeln(_row(['Surviving Count (including harvested)', t.liveCount]));
    buf.writeln(_row(['Current In-Tank Count', t.inTankCount]));
    buf.writeln(_row(['Total Mortality', t.totalMortalityFromHistory]));
    buf.writeln(_row(['Total Harvested', t.totalHarvested]));
    buf.writeln(_row(['Survival Rate (%)', t.survivalRate.toStringAsFixed(2)]));
    buf.writeln();

    final samples = t.samplingHistory;
    buf.writeln(_row(['Sampling Period', _samplingPeriod(samples)]));
    buf.writeln(_row(['Sampling Events', samples.length]));
    buf.writeln();
    if (sections.includeSampling && samples.isNotEmpty) {
      buf.writeln(_row(['Sampling Records']));
      buf.write(_row(growthColumns));
      for (final row in growthRows(samples, t.stockingDate)) {
        buf.write(_row(row));
      }
      buf.writeln();
    }

    final mortality = t.mortalityHistory;
    if (sections.includeMortality && mortality.isNotEmpty) {
      buf.writeln(_row(['Mortality Records']));
      buf.writeln(_row(['Date', 'Count']));
      for (final m in mortality) {
        buf.writeln(_row([_fmtDate(m.date), m.count]));
      }
      buf.writeln();
    }

    final harvests = t.harvestRecords;
    if (sections.includeHarvest && harvests.isNotEmpty) {
      buf.writeln(_row(['Harvest Records']));
      buf.writeln(
        _row(['Date', 'Harvested Count', 'Total Weight (kg)', 'ABW (g)']),
      );
      for (final h in harvests) {
        buf.writeln(
          _row([
            _fmtDate(h.date),
            h.harvestedCount,
            h.totalWeightKg.toStringAsFixed(3),
            h.abwGrams.toStringAsFixed(2),
          ]),
        );
      }
      buf.writeln();
    }

    buf.write(
      _row(['Included Detailed Sections', sections.selectedSectionsLabel]),
    );
    buf.write(
      _row([
        'Notes',
        'Weeks are elapsed 7-day calendar intervals from stocking. Length and weight totals refer to the sample. '
            'Average body weight = sample total weight / sample size; average body length = sample total length / sample size. '
            'Estimated biomass = sample average body weight x in-tank count at sampling. '
            'Survival rate = (initial population - recorded mortality) / initial population x 100; harvested crayfish are included among survivors. '
            'This report contains the selected batch records only.',
      ]),
    );
    return buf.toString();
  }

  static int _snapshotMortality(BatchRecordSnapshot snapshot) =>
      snapshot.mortality.fold(0, (total, entry) => total + entry.count);

  static int _snapshotHarvested(BatchRecordSnapshot snapshot) {
    final recordsTotal = snapshot.harvests.fold(
      0,
      (total, record) => total + record.harvestedCount,
    );
    return snapshot.harvests.isEmpty
        ? snapshot.batch.harvestCount
        : recordsTotal;
  }

  static DateTime _snapshotPeriodEnd(BatchRecordSnapshot snapshot) =>
      snapshot.batch.harvestDate ?? snapshot.batch.endedAt ?? DateTime.now();

  static double _snapshotSurvivalRate(BatchRecordSnapshot snapshot) {
    final initial = snapshot.batch.initialCount;
    if (initial <= 0) return 0;
    final survivors = (initial - _snapshotMortality(snapshot))
        .clamp(0, initial)
        .toInt();
    return survivors / initial * 100;
  }

  static SamplingEntry? _latestSampling(BatchRecordSnapshot snapshot) {
    if (snapshot.sampling.isEmpty) return null;
    final ordered = List<SamplingEntry>.of(snapshot.sampling)
      ..sort((a, b) => a.date.compareTo(b.date));
    return ordered.last;
  }

  /// Builds one report containing every batch in the Batch List, including
  /// the detailed sections selected by the owner.
  String buildAllGrowthCsv(
    List<BatchRecordSnapshot> snapshots, {
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
  }) {
    final buf = StringBuffer();
    final ordered = List<BatchRecordSnapshot>.of(snapshots)
      ..sort((a, b) {
        final dateOrder = a.batch.stockingDate.compareTo(b.batch.stockingDate);
        return dateOrder != 0
            ? dateOrder
            : a.batch.batchId.compareTo(b.batch.batchId);
      });
    final showAllBatchesSummary = includeSummary && ordered.length > 1;

    buf.writeln('CrayCare All Batches Grow-Out Report');
    buf.writeln('Generated,${_fmtDateTime(DateTime.now())}');
    buf.writeln(
      _row(['Included Detailed Sections', sections.selectedSectionsLabel]),
    );
    buf.writeln();
    if (showAllBatchesSummary) {
      buf.writeln(_row(['Selected Batches Summary']));
      buf.write(
        _row([
          'Batch ID',
          'Status',
          'Stocking Date',
          'End Date',
          'Days in Culture',
          'Initial Population',
          'Total Mortality',
          'Total Harvested',
          'Survival Rate (%)',
          'Final ABW (g)',
          'Final ABL (cm)',
        ]),
      );
      for (final snapshot in ordered) {
        final latest = _latestSampling(snapshot);
        buf.write(
          _row([
            snapshot.batch.batchId,
            snapshot.batch.status,
            _fmtDate(snapshot.batch.stockingDate),
            _fmtDate(_snapshotPeriodEnd(snapshot)),
            snapshot.batch.daysInCulture,
            snapshot.batch.initialCount,
            _snapshotMortality(snapshot),
            _snapshotHarvested(snapshot),
            _snapshotSurvivalRate(snapshot).toStringAsFixed(2),
            (latest?.abw ?? snapshot.batch.finalAbw).toStringAsFixed(2),
            (latest?.avgLength ?? snapshot.batch.finalAbl).toStringAsFixed(2),
          ]),
        );
      }
      buf.writeln();
    }

    for (final snapshot in ordered) {
      final batch = snapshot.batch;
      if (includeSummary) {
        buf.writeln(_row(['Batch', batch.batchId]));
        buf.writeln(_row(['Status', batch.status]));
        buf.writeln(
          _row([
            'Culture Period',
            _dateRange(batch.stockingDate, _snapshotPeriodEnd(snapshot)),
          ]),
        );
        buf.writeln(_row(['Days in Culture', batch.daysInCulture]));
        buf.writeln(_row(['Initial Population', batch.initialCount]));
        buf.writeln(_row(['Total Mortality', _snapshotMortality(snapshot)]));
        buf.writeln(_row(['Total Harvested', _snapshotHarvested(snapshot)]));
        buf.writeln(
          _row([
            'Survival Rate (%)',
            _snapshotSurvivalRate(snapshot).toStringAsFixed(2),
          ]),
        );
      }

      if (sections.includeSampling) {
        buf.writeln(_row(['Sampling Records']));
        buf.write(_row(growthColumns));
        for (final row in growthRows(snapshot.sampling, batch.stockingDate)) {
          buf.write(_row(row));
        }
      }
      if (sections.includeMortality) {
        buf.writeln(_row(['Mortality Records']));
        buf.write(_row(['Date', 'Count']));
        for (final entry in snapshot.mortality) {
          buf.write(_row([_fmtDate(entry.date), entry.count]));
        }
      }
      if (sections.includeHarvest) {
        buf.writeln(_row(['Harvest Records']));
        buf.write(
          _row(['Date', 'Harvested Count', 'Total Weight (kg)', 'ABW (g)']),
        );
        for (final entry in snapshot.harvests) {
          buf.write(
            _row([
              _fmtDate(entry.date),
              entry.harvestedCount,
              entry.totalWeightKg.toStringAsFixed(3),
              entry.abwGrams.toStringAsFixed(2),
            ]),
          );
        }
      }
      buf.writeln();
    }

    buf.write(
      _row([
        'Notes',
        'This report contains all batches currently available in the tank. '
            'Computed values are generated for the report and are not saved as new database fields.',
      ]),
    );
    return buf.toString();
  }

  static void _appendExcelRow(xl.Sheet sheet, Iterable<Object?> values) {
    sheet.appendRow(
      values.map((value) => xl.TextCellValue(value?.toString() ?? '')).toList(),
    );
  }

  static final xl.CellStyle _excelTitleStyle = xl.CellStyle(
    backgroundColorHex: xl.ExcelColor.fromHexString('FF1FA5A5'),
    fontColorHex: xl.ExcelColor.white,
    bold: true,
    fontSize: 14,
  );

  static final xl.CellStyle _excelSectionStyle = xl.CellStyle(
    backgroundColorHex: xl.ExcelColor.fromHexString('FFE4F4F4'),
    fontColorHex: xl.ExcelColor.fromHexString('FF0B3C49'),
    bold: true,
    fontSize: 11,
  );

  static final xl.CellStyle _excelHeaderStyle = xl.CellStyle(
    backgroundColorHex: xl.ExcelColor.fromHexString('FF1FA5A5'),
    fontColorHex: xl.ExcelColor.white,
    bold: true,
  );

  static void _appendExcelLabelRow(
    xl.Sheet sheet,
    String text,
    xl.CellStyle style,
  ) {
    final rowIndex = sheet.maxRows;
    _appendExcelRow(sheet, [text]);
    sheet
            .cell(
              xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
            )
            .cellStyle =
        style;
  }

  static void _setExcelColumnWidths(xl.Sheet sheet) {
    for (var column = 0; column < 12; column++) {
      sheet.setColumnWidth(column, column == 0 ? 25 : 18);
    }
  }

  static void _appendExcelTable(
    xl.Sheet sheet, {
    required List<String> headers,
    required Iterable<List<Object?>> rows,
  }) {
    final headerRowIndex = sheet.maxRows;
    _appendExcelRow(sheet, headers);
    for (var column = 0; column < headers.length; column++) {
      sheet
              .cell(
                xl.CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: headerRowIndex,
                ),
              )
              .cellStyle =
          _excelHeaderStyle;
    }
    for (final row in rows) {
      _appendExcelRow(sheet, row);
    }
  }

  /// Builds an organized workbook with a summary sheet for multiple selected
  /// batches and one dedicated sheet per batch.
  Future<Uint8List> buildAllGrowthExcel(
    List<BatchRecordSnapshot> snapshots, {
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
  }) async {
    final ordered = List<BatchRecordSnapshot>.of(snapshots)
      ..sort((a, b) {
        final dateOrder = a.batch.stockingDate.compareTo(b.batch.stockingDate);
        return dateOrder != 0
            ? dateOrder
            : a.batch.batchId.compareTo(b.batch.batchId);
      });
    final showAllBatchesSummary = includeSummary && ordered.length > 1;
    final workbook = xl.Excel.createExcel();

    if (showAllBatchesSummary) {
      workbook.rename('Sheet1', 'Batch Summary');
      final sheet = workbook['Batch Summary'];
      _setExcelColumnWidths(sheet);
      _appendExcelLabelRow(
        sheet,
        'CrayCare All Batches Grow-Out Report',
        _excelTitleStyle,
      );
      _appendExcelRow(sheet, ['Generated', _fmtDateTime(DateTime.now())]);
      _appendExcelRow(sheet, [
        'Included Records',
        sections.selectedSectionsLabel,
      ]);
      _appendExcelRow(sheet, ['']);
      _appendExcelLabelRow(
        sheet,
        'Selected Batches Summary',
        _excelSectionStyle,
      );
      _appendExcelTable(
        sheet,
        headers: const [
          'Batch ID',
          'Status',
          'Stocking Date',
          'End Date',
          'Days in Culture',
          'Initial Population',
          'Total Mortality',
          'Total Harvested',
          'Survival Rate (%)',
          'Final ABW (g)',
          'Final ABL (cm)',
        ],
        rows: ordered.map((snapshot) {
          final latest = _latestSampling(snapshot);
          return <Object?>[
            snapshot.batch.batchId,
            snapshot.batch.status,
            _fmtDate(snapshot.batch.stockingDate),
            _fmtDate(_snapshotPeriodEnd(snapshot)),
            snapshot.batch.daysInCulture,
            snapshot.batch.initialCount,
            _snapshotMortality(snapshot),
            _snapshotHarvested(snapshot),
            _snapshotSurvivalRate(snapshot).toStringAsFixed(2),
            (latest?.abw ?? snapshot.batch.finalAbw).toStringAsFixed(2),
            (latest?.avgLength ?? snapshot.batch.finalAbl).toStringAsFixed(2),
          ];
        }),
      );
    }

    for (var index = 0; index < ordered.length; index++) {
      final snapshot = ordered[index];
      final batch = snapshot.batch;
      final sheetName = 'Batch ${index + 1}';
      if (!showAllBatchesSummary && index == 0) {
        workbook.rename('Sheet1', sheetName);
      }
      final sheet = workbook[sheetName];
      final latest = _latestSampling(snapshot);
      _setExcelColumnWidths(sheet);

      _appendExcelLabelRow(sheet, 'CrayCare Batch Report', _excelTitleStyle);
      _appendExcelRow(sheet, ['Batch ID', batch.batchId]);
      _appendExcelRow(sheet, ['']);

      if (includeSummary) {
        _appendExcelLabelRow(sheet, 'Batch Summary', _excelSectionStyle);
        _appendExcelTable(
          sheet,
          headers: const ['Metric', 'Value'],
          rows: [
            ['Status', batch.status],
            [
              'Culture Period',
              _dateRange(batch.stockingDate, _snapshotPeriodEnd(snapshot)),
            ],
            ['Days in Culture', batch.daysInCulture],
            ['Initial Population', batch.initialCount],
            ['Total Mortality', _snapshotMortality(snapshot)],
            ['Total Harvested', _snapshotHarvested(snapshot)],
            [
              'Survival Rate (%)',
              _snapshotSurvivalRate(snapshot).toStringAsFixed(2),
            ],
            [
              'Final ABW (g)',
              (latest?.abw ?? batch.finalAbw).toStringAsFixed(2),
            ],
            [
              'Final ABL (cm)',
              (latest?.avgLength ?? batch.finalAbl).toStringAsFixed(2),
            ],
          ],
        );
      }

      if (sections.includeSampling) {
        _appendExcelRow(sheet, ['']);
        _appendExcelLabelRow(sheet, 'Sampling Records', _excelSectionStyle);
        _appendExcelTable(
          sheet,
          headers: growthColumns,
          rows: growthRows(snapshot.sampling, batch.stockingDate),
        );
        if (snapshot.sampling.isEmpty) {
          _appendExcelRow(sheet, ['No sampling records.']);
        }
      }

      if (sections.includeMortality) {
        _appendExcelRow(sheet, ['']);
        _appendExcelLabelRow(sheet, 'Mortality Records', _excelSectionStyle);
        _appendExcelTable(
          sheet,
          headers: const ['Date', 'Count'],
          rows: snapshot.mortality.map(
            (entry) => <Object?>[_fmtDate(entry.date), entry.count],
          ),
        );
        if (snapshot.mortality.isEmpty) {
          _appendExcelRow(sheet, ['No mortality records.']);
        }
      }

      if (sections.includeHarvest) {
        _appendExcelRow(sheet, ['']);
        _appendExcelLabelRow(sheet, 'Harvest Records', _excelSectionStyle);
        _appendExcelTable(
          sheet,
          headers: const [
            'Date',
            'Harvested Count',
            'Total Weight (kg)',
            'ABW (g)',
          ],
          rows: snapshot.harvests.map(
            (entry) => <Object?>[
              _fmtDate(entry.date),
              entry.harvestedCount,
              entry.totalWeightKg.toStringAsFixed(3),
              entry.abwGrams.toStringAsFixed(2),
            ],
          ),
        );
        if (snapshot.harvests.isEmpty) {
          _appendExcelRow(sheet, ['No harvest records.']);
        }
      }
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('Unable to create the Excel report.');
    }
    return Uint8List.fromList(bytes);
  }

  // ── Grow-out (production) PDF ──────────────────────────────────────────
  Future<Uint8List> buildGrowthPdf({
    GrowOutReportSections sections = const GrowOutReportSections(),
  }) async {
    final t = TankService.instance;
    final doc = pw.Document();

    pw.Table kwTable(List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: ['Metric', 'Value'],
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _careColor),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      data: rows,
    );

    final samples = t.samplingHistory;
    final mortality = t.mortalityHistory;
    final harvests = t.harvestRecords;
    final culturePeriod = _dateRange(t.stockingDate, _culturePeriodEnd(t));
    final samplingPeriod = _samplingPeriod(samples);

    final samplingRows = growthRows(samples, t.stockingDate);

    final mortalityRows = mortality
        .map((m) => [_fmtDate(m.date), '${m.count}'])
        .toList();

    final harvestRows = harvests
        .map(
          (h) => [
            _fmtDate(h.date),
            '${h.harvestedCount}',
            h.totalWeightKg.toStringAsFixed(3),
            h.abwGrams.toStringAsFixed(2),
          ],
        )
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Text(
          'CrayCare Grow-Out Report',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: _crayColor,
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated ${_fmtDateTime(DateTime.now())}  ·  Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Text(
            _pdfSafe(
              'Tank grow-out and production records exported from CrayCare.',
            ),
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Tank Summary',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          pw.SizedBox(height: 8),
          kwTable([
            ['Batch ID', _pdfSafe(t.selectedBatchId ?? '-')],
            ['Stocking Date', _fmtDate(t.stockingDate)],
            ['Culture Period', culturePeriod],
            ['Days in Culture', '${t.daysInCulture}'],
            ['Initial Population', '${t.initialCount}'],
            ['Initial ABW (g)', t.initialWeight.toStringAsFixed(2)],
            ['Initial ABL (cm)', t.initialLength.toStringAsFixed(2)],
            ['Surviving Count (including harvested)', '${t.liveCount}'],
            ['Current In-Tank Count', '${t.inTankCount}'],
            ['Total Mortality', '${t.totalMortalityFromHistory}'],
            ['Total Harvested', '${t.totalHarvested}'],
            ['Survival Rate (%)', t.survivalRate.toStringAsFixed(2)],
            ['Sampling Period', samplingPeriod],
            ['Sampling Events', '${samples.length}'],
          ]),
          pw.Text(
            'Included Detailed Sections: ${sections.selectedSectionsLabel}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          if (sections.includeSampling) pw.SizedBox(height: 20),
          if (sections.includeSampling)
            pw.Text(
              'Sampling Records',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _crayColor,
              ),
            ),
          if (sections.includeSampling) pw.SizedBox(height: 8),
          if (sections.includeSampling && samplingRows.isEmpty)
            pw.Text(
              'No sampling records yet.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else if (sections.includeSampling)
            pw.TableHelper.fromTextArray(
              headers: growthColumns,
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: samplingRows,
            ),
          if (sections.includeSampling) pw.SizedBox(height: 6),
          if (sections.includeSampling)
            pw.Text(
              'Weeks are counted from the stocking date in 7-day calendar intervals. '
              'Length and weight totals refer to the sample. Average body weight = sample total weight / sample size; '
              'average body length = sample total length / sample size. '
              'Estimated biomass = sample average body weight x in-tank count at sampling. '
              'Survival rate = (initial population - recorded mortality) / initial population x 100; '
              'harvested crayfish are included among survivors. This report contains the selected batch records only.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          if (sections.includeMortality) pw.SizedBox(height: 20),
          if (sections.includeMortality)
            pw.Text(
              'Mortality Records',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _crayColor,
              ),
            ),
          if (sections.includeMortality) pw.SizedBox(height: 8),
          if (sections.includeMortality && mortalityRows.isEmpty)
            pw.Text(
              'No mortality records.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else if (sections.includeMortality)
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Count'],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: mortalityRows,
            ),
          if (sections.includeHarvest) pw.SizedBox(height: 20),
          if (sections.includeHarvest)
            pw.Text(
              'Harvest Records',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _crayColor,
              ),
            ),
          if (sections.includeHarvest) pw.SizedBox(height: 8),
          if (sections.includeHarvest && harvestRows.isEmpty)
            pw.Text(
              'No harvest records.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else if (sections.includeHarvest)
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Count', 'Total W (kg)', 'ABW (g)'],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: harvestRows,
            ),
        ],
      ),
    );

    return doc.save();
  }

  /// Builds a single PDF for the chosen batches. When enabled, the first page
  /// is an overall summary; each batch begins on its own page in stocking-date
  /// order.
  Future<Uint8List> buildAllGrowthPdf(
    List<BatchRecordSnapshot> snapshots, {
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
  }) async {
    final ordered = List<BatchRecordSnapshot>.of(snapshots)
      ..sort((a, b) {
        final dateOrder = a.batch.stockingDate.compareTo(b.batch.stockingDate);
        return dateOrder != 0
            ? dateOrder
            : a.batch.batchId.compareTo(b.batch.batchId);
      });
    final showAllBatchesSummary = includeSummary && ordered.length > 1;
    final doc = pw.Document();

    pw.Table table({
      required List<String> headers,
      required List<List<String>> rows,
      double fontSize = 8,
    }) => pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _careColor),
      cellStyle: pw.TextStyle(fontSize: fontSize),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );

    pw.Widget sectionTitle(String text) => pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: _crayColor,
      ),
    );

    if (showAllBatchesSummary) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(36),
          header: (context) => pw.Text(
            'CrayCare All Batches Grow-Out Report',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Generated ${_fmtDateTime(DateTime.now())}  ·  Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
          build: (context) => [
            pw.Text(
              '${ordered.length} selected batch${ordered.length == 1 ? '' : 'es'} · '
              'Detailed sections: ${sections.selectedSectionsLabel}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            sectionTitle('Selected Batches Summary'),
            pw.SizedBox(height: 8),
            table(
              headers: const [
                'Batch ID',
                'Status',
                'Stocking',
                'End',
                'Days',
                'Initial',
                'Mortality',
                'Harvested',
                'Survival',
                'Final ABW',
                'Final ABL',
              ],
              rows: ordered.map((snapshot) {
                final latest = _latestSampling(snapshot);
                return [
                  _pdfSafe(snapshot.batch.batchId),
                  _pdfSafe(snapshot.batch.status),
                  _fmtDate(snapshot.batch.stockingDate),
                  _fmtDate(_snapshotPeriodEnd(snapshot)),
                  '${snapshot.batch.daysInCulture}',
                  '${snapshot.batch.initialCount}',
                  '${_snapshotMortality(snapshot)}',
                  '${_snapshotHarvested(snapshot)}',
                  '${_snapshotSurvivalRate(snapshot).toStringAsFixed(2)}%',
                  (latest?.abw ?? snapshot.batch.finalAbw).toStringAsFixed(2),
                  (latest?.avgLength ?? snapshot.batch.finalAbl)
                      .toStringAsFixed(2),
                ];
              }).toList(),
              fontSize: 7,
            ),
          ],
        ),
      );
    }

    for (final snapshot in ordered) {
      final batch = snapshot.batch;
      final latest = _latestSampling(snapshot);
      final samplingRows = growthRows(snapshot.sampling, batch.stockingDate);
      final mortalityRows = snapshot.mortality
          .map((entry) => [_fmtDate(entry.date), '${entry.count}'])
          .toList();
      final harvestRows = snapshot.harvests
          .map(
            (entry) => [
              _fmtDate(entry.date),
              '${entry.harvestedCount}',
              entry.totalWeightKg.toStringAsFixed(3),
              entry.abwGrams.toStringAsFixed(2),
            ],
          )
          .toList();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(36),
          header: (context) => pw.Text(
            'CrayCare Batch Report · ${_pdfSafe(batch.batchId)}',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Generated ${_fmtDateTime(DateTime.now())}  ·  Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
          build: (context) => [
            if (includeSummary) ...[
              sectionTitle('Batch Summary'),
              pw.SizedBox(height: 8),
              table(
                headers: const ['Metric', 'Value'],
                rows: [
                  ['Batch ID', _pdfSafe(batch.batchId)],
                  ['Status', _pdfSafe(batch.status)],
                  [
                    'Culture Period',
                    _dateRange(
                      batch.stockingDate,
                      _snapshotPeriodEnd(snapshot),
                    ),
                  ],
                  ['Days in Culture', '${batch.daysInCulture}'],
                  ['Initial Population', '${batch.initialCount}'],
                  ['Total Mortality', '${_snapshotMortality(snapshot)}'],
                  ['Total Harvested', '${_snapshotHarvested(snapshot)}'],
                  [
                    'Survival Rate (%)',
                    _snapshotSurvivalRate(snapshot).toStringAsFixed(2),
                  ],
                  [
                    'Final ABW (g)',
                    (latest?.abw ?? batch.finalAbw).toStringAsFixed(2),
                  ],
                  [
                    'Final ABL (cm)',
                    (latest?.avgLength ?? batch.finalAbl).toStringAsFixed(2),
                  ],
                ],
                fontSize: 9,
              ),
            ],
            if (sections.includeSampling) pw.SizedBox(height: 20),
            if (sections.includeSampling) sectionTitle('Sampling Records'),
            if (sections.includeSampling) pw.SizedBox(height: 8),
            if (sections.includeSampling && samplingRows.isEmpty)
              pw.Text(
                'No sampling records.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              )
            else if (sections.includeSampling)
              table(headers: growthColumns, rows: samplingRows, fontSize: 7),
            if (sections.includeMortality) pw.SizedBox(height: 20),
            if (sections.includeMortality) sectionTitle('Mortality Records'),
            if (sections.includeMortality) pw.SizedBox(height: 8),
            if (sections.includeMortality && mortalityRows.isEmpty)
              pw.Text(
                'No mortality records.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              )
            else if (sections.includeMortality)
              table(
                headers: const ['Date', 'Count'],
                rows: mortalityRows,
                fontSize: 9,
              ),
            if (sections.includeHarvest) pw.SizedBox(height: 20),
            if (sections.includeHarvest) sectionTitle('Harvest Records'),
            if (sections.includeHarvest) pw.SizedBox(height: 8),
            if (sections.includeHarvest && harvestRows.isEmpty)
              pw.Text(
                'No harvest records.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              )
            else if (sections.includeHarvest)
              table(
                headers: const [
                  'Date',
                  'Harvested Count',
                  'Total Weight (kg)',
                  'ABW (g)',
                ],
                rows: harvestRows,
                fontSize: 9,
              ),
          ],
        ),
      );
    }

    return doc.save();
  }

  // ── File writing + sharing ─────────────────────────────────────────────
  Future<void> _writeAndShare(
    String filename,
    String mime,
    List<int> bytes,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([
      XFile(file.path, mimeType: mime),
    ], subject: filename);
  }

  Future<void> shareGrowthCsv({
    GrowOutReportSections sections = const GrowOutReportSections(),
  }) async {
    final name = 'craycare_growth_${_stamp()}.csv';
    await _writeAndShare(
      name,
      'text/csv',
      utf8.encode(buildGrowthCsv(sections: sections)),
    );
  }

  Future<void> shareGrowthPdf({
    GrowOutReportSections sections = const GrowOutReportSections(),
  }) async {
    final name = 'craycare_growth_${_stamp()}.pdf';
    await _writeAndShare(
      name,
      'application/pdf',
      await buildGrowthPdf(sections: sections),
    );
  }

  Future<void> shareAllGrowthCsv({
    required Iterable<String> batchIds,
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
    String fileName = 'craycare_all_batches',
  }) async {
    final snapshots = await TankService.instance.loadBatchRecordSnapshots(
      batchIds,
    );
    if (snapshots.isEmpty) {
      throw StateError('No batch records are available to export.');
    }
    final name = '${_safeFileStem(fileName)}_${_stamp()}.csv';
    await _writeAndShare(
      name,
      'text/csv',
      utf8.encode(
        buildAllGrowthCsv(
          snapshots,
          sections: sections,
          includeSummary: includeSummary,
        ),
      ),
    );
  }

  Future<void> shareAllGrowthExcel({
    required Iterable<String> batchIds,
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
    String fileName = 'craycare_all_batches',
  }) async {
    final snapshots = await TankService.instance.loadBatchRecordSnapshots(
      batchIds,
    );
    if (snapshots.isEmpty) {
      throw StateError('No batch records are available to export.');
    }
    final name = '${_safeFileStem(fileName)}_${_stamp()}.xlsx';
    await _writeAndShare(
      name,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      await buildAllGrowthExcel(
        snapshots,
        sections: sections,
        includeSummary: includeSummary,
      ),
    );
  }

  Future<void> shareAllGrowthPdf({
    required Iterable<String> batchIds,
    GrowOutReportSections sections = const GrowOutReportSections(),
    bool includeSummary = true,
    String fileName = 'craycare_all_batches',
  }) async {
    final snapshots = await TankService.instance.loadBatchRecordSnapshots(
      batchIds,
    );
    if (snapshots.isEmpty) {
      throw StateError('No batch records are available to export.');
    }
    final name = '${_safeFileStem(fileName)}_${_stamp()}.pdf';
    await _writeAndShare(
      name,
      'application/pdf',
      await buildAllGrowthPdf(
        snapshots,
        sections: sections,
        includeSummary: includeSummary,
      ),
    );
  }
}
