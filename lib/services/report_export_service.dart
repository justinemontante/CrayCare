import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'water_quality_assessment_service.dart';
import 'tank_service.dart';

/// Builds CSV and PDF reports from the in-memory grow-out and water-quality
/// data, then hands the file to the Android share sheet so the owner can save
/// it to Files/Drive or send it anywhere.
class ReportExportService {
  static final ReportExportService instance = ReportExportService._();
  ReportExportService._();

  // Report palette:
  //   Table headers / accents = blue (#2563EB, darker #1D4ED8)
  //   Section titles / text    = deep navy (#0F172A)
  // Green is intentionally not used so the report matches the requested
  // blue-themed export instead of the in-app sensor-status colors.
  static const PdfColor _careColor = PdfColor.fromInt(0xFF2563EB);
  static const PdfColor _careColorDark = PdfColor.fromInt(0xFF1D4ED8);
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

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_'
        '${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
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
  String buildGrowthCsv() {
    final t = TankService.instance;
    final buf = StringBuffer();

    buf.writeln('CrayCare Grow-Out Report');
    buf.writeln('Generated,${_fmtDateTime(DateTime.now())}');
    buf.writeln();
    buf.writeln(_row(['Summary']));
    buf.writeln(_row(['Batch ID', t.selectedBatchId ?? '-']));
    buf.writeln(_row(['Stocking Date', _fmtDate(t.stockingDate)]));
    buf.writeln(_row(['Days in Culture', t.daysInCulture]));
    buf.writeln(_row(['Initial Population', t.initialCount]));
    buf.writeln(_row(['Initial ABW (g)', t.initialWeight.toStringAsFixed(2)]));
    buf.writeln(_row(['Initial ABL (cm)', t.initialLength.toStringAsFixed(2)]));
    buf.writeln(_row(['Live Count', t.liveCount]));
    buf.writeln(_row(['Total Mortality', t.totalMortalityFromHistory]));
    buf.writeln(_row(['Total Harvested', t.totalHarvested]));
    buf.writeln(_row(['Survival Rate (%)', t.survivalRate.toStringAsFixed(2)]));
    buf.writeln();

    final samples = t.samplingHistory;
    if (samples.isNotEmpty) {
      buf.writeln(
        _row([
          'Sampling Records',
          'Date',
          'ABW (g)',
          'ABL (cm)',
          'Sample Size',
          'Total Weight (g)',
          'Total Length (cm)',
          'Biomass (g)',
          'Live Count',
        ]),
      );
      for (final s in samples) {
        buf.writeln(
          _row([
            '',
            _fmtDate(s.date),
            s.abw.toStringAsFixed(2),
            s.avgLength.toStringAsFixed(2),
            s.sampleSize,
            s.totalWeight.toStringAsFixed(2),
            s.totalLength.toStringAsFixed(2),
            s.biomass.toStringAsFixed(2),
            s.liveCount,
          ]),
        );
      }
      buf.writeln();
    }

    final mortality = t.mortalityHistory;
    if (mortality.isNotEmpty) {
      buf.writeln(_row(['Mortality Records', 'Date', 'Count']));
      for (final m in mortality) {
        buf.writeln(_row(['', _fmtDate(m.date), m.count]));
      }
      buf.writeln();
    }

    final harvests = t.harvestRecords;
    if (harvests.isNotEmpty) {
      buf.writeln(
        _row([
          'Harvest Records',
          'Date',
          'Harvested Count',
          'Total Weight (kg)',
          'ABW (g)',
        ]),
      );
      for (final h in harvests) {
        buf.writeln(
          _row([
            '',
            _fmtDate(h.date),
            h.harvestedCount,
            h.totalWeightKg.toStringAsFixed(3),
            h.abwGrams.toStringAsFixed(2),
          ]),
        );
      }
      buf.writeln();
    }

    return buf.toString();
  }

  // ── Machine Learning-Based Water Quality Assessment CSV ────────────────
  String buildWaterQualityAssessmentCsv() {
    final assessmentService = WaterQualityAssessmentService.instance;
    final buf = StringBuffer();

    buf.writeln(
      'CrayCare Machine Learning-Based Water Quality Assessment Report',
    );
    buf.writeln('Generated,${_fmtDateTime(DateTime.now())}');
    buf.writeln();

    final history = assessmentService.history;
    if (history.isEmpty) {
      buf.writeln(
        'No Water Quality Assessment history yet. The first Water Quality Assessment appears '
        'after about one hour of sensor data.',
      );
      return buf.toString();
    }

    buf.writeln(
      _row([
        'Timestamp',
        'Level',
        'Assessment Basis',
        'Confidence (%)',
        'Driver',
        'Driver Value',
        'Unit',
        'Problem',
        'Action',
      ]),
    );
    for (final h in history) {
      buf.writeln(
        _row([
          _fmtDateTime(h.timestamp.toLocal()),
          h.level,
          h.assessmentBasis,
          h.safetyOverride ? '' : h.confidence,
          h.driverLabel,
          h.driverValue?.toStringAsFixed(2) ?? '',
          h.driverUnit,
          h.problem,
          h.action,
        ]),
      );
    }
    buf.writeln();

    final latest = history.first;
    buf.writeln(_row(['Latest Water Quality Assessment Detail']));
    buf.writeln(_row(['Level', latest.level]));
    buf.writeln(_row(['Assessment Basis', latest.assessmentBasis]));
    if (!latest.safetyOverride) {
      buf.writeln(_row(['Confidence (%)', latest.confidence]));
    }
    buf.writeln(_row(['Primary Driver', latest.driverLabel]));
    buf.writeln(_row(['Insight', latest.insight]));
    buf.writeln(_row(['Recommended Action', latest.action]));

    return buf.toString();
  }

  // ── Grow-out (production) PDF ──────────────────────────────────────────
  Future<Uint8List> buildGrowthPdf() async {
    final t = TankService.instance;
    final doc = pw.Document();

    pw.Table kwTable(List<List<String>> rows) => pw.TableHelper.fromTextArray(
      headers: ['Metric', 'Value'],
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: _careColorDark),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      data: rows,
    );

    final samples = t.samplingHistory;
    final mortality = t.mortalityHistory;
    final harvests = t.harvestRecords;

    final samplingRows = samples
        .map(
          (s) => [
            _fmtDate(s.date),
            s.abw.toStringAsFixed(2),
            s.avgLength.toStringAsFixed(2),
            '${s.sampleSize}',
            s.totalWeight.toStringAsFixed(2),
            s.biomass.toStringAsFixed(2),
          ],
        )
        .toList();

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
        pageFormat: PdfPageFormat.a4,
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
            ['Days in Culture', '${t.daysInCulture}'],
            ['Initial Population', '${t.initialCount}'],
            ['Initial ABW (g)', t.initialWeight.toStringAsFixed(2)],
            ['Initial ABL (cm)', t.initialLength.toStringAsFixed(2)],
            ['Live Count', '${t.liveCount}'],
            ['Total Mortality', '${t.totalMortalityFromHistory}'],
            ['Total Harvested', '${t.totalHarvested}'],
            ['Survival Rate (%)', t.survivalRate.toStringAsFixed(2)],
          ]),
          pw.SizedBox(height: 20),
          pw.Text(
            'Sampling Records',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          pw.SizedBox(height: 8),
          if (samplingRows.isEmpty)
            pw.Text(
              'No sampling records yet.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Date',
                'ABW (g)',
                'ABL (cm)',
                'Sample',
                'Total W (g)',
                'Biomass (g)',
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColor),
              cellStyle: const pw.TextStyle(fontSize: 9),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: samplingRows,
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Mortality Records',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          pw.SizedBox(height: 8),
          if (mortalityRows.isEmpty)
            pw.Text(
              'No mortality records.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else
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
          pw.SizedBox(height: 20),
          pw.Text(
            'Harvest Records',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _crayColor,
            ),
          ),
          pw.SizedBox(height: 8),
          if (harvestRows.isEmpty)
            pw.Text(
              'No harvest records.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            )
          else
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

  // ── Machine Learning-Based Water Quality Assessment PDF ────────────────
  Future<Uint8List> buildWaterQualityAssessmentPdf() async {
    final assessmentService = WaterQualityAssessmentService.instance;
    final history = assessmentService.history;
    final doc = pw.Document();

    final rows = history
        .map(
          (h) => [
            _fmtDateTime(h.timestamp.toLocal()),
            h.level,
            h.assessmentBasis,
            h.safetyOverride ? '' : '${h.confidence}',
            _pdfSafe(h.driverLabel),
            _pdfSafe(h.problem),
            _pdfSafe(h.action),
          ],
        )
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Text(
          'CrayCare Machine Learning-Based Water Quality Assessment Report',
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
          if (history.isEmpty)
            pw.Text(
              'No Water Quality Assessment history yet. The first Water Quality Assessment appears after about one hour of sensor data.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            )
          else ...[
            pw.Text(
              'Water Quality Assessment History',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _crayColor,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: [
                'Timestamp',
                'Level',
                'Basis',
                'Conf %',
                'Driver',
                'Problem',
                'Action',
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColor),
              cellStyle: const pw.TextStyle(fontSize: 8),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: rows,
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Latest Water Quality Assessment Detail',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _crayColor,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Field', 'Value'],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: _careColorDark),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              data: [
                ['Level', history.first.level],
                ['Assessment Basis', history.first.assessmentBasis],
                if (!history.first.safetyOverride)
                  ['Confidence (%)', '${history.first.confidence}'],
                ['Primary Driver', _pdfSafe(history.first.driverLabel)],
                ['Insight', _pdfSafe(history.first.insight)],
                ['Recommended Action', _pdfSafe(history.first.action)],
              ],
            ),
          ],
        ],
      ),
    );

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

  Future<void> shareGrowthCsv() async {
    final name = 'craycare_growth_${_stamp()}.csv';
    await _writeAndShare(name, 'text/csv', buildGrowthCsv().codeUnits);
  }

  Future<void> shareGrowthPdf() async {
    final name = 'craycare_growth_${_stamp()}.pdf';
    await _writeAndShare(name, 'application/pdf', await buildGrowthPdf());
  }

  Future<void> shareWaterQualityAssessmentCsv() async {
    final name = 'craycare_water_quality_assessment_${_stamp()}.csv';
    await _writeAndShare(
      name,
      'text/csv',
      buildWaterQualityAssessmentCsv().codeUnits,
    );
  }

  Future<void> shareWaterQualityAssessmentPdf() async {
    final name = 'craycare_water_quality_assessment_${_stamp()}.pdf';
    await _writeAndShare(
      name,
      'application/pdf',
      await buildWaterQualityAssessmentPdf(),
    );
  }
}
