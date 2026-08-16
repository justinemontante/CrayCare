import 'package:flutter/services.dart';

import 'health_risk_service.dart';
import 'tank_service.dart';

/// Builds CSV reports from the in-memory grow-out and water-quality data.
///
/// CSV was chosen over PDF so the report opens directly in Excel / Google
/// Sheets (common for thesis documentation) with zero extra dependencies.
/// The caller copies the returned string to the clipboard (see
/// copyToClipboard) so the user can paste it anywhere.
class ReportExportService {
  static final ReportExportService instance = ReportExportService._();
  ReportExportService._();

  // ── CSV helpers ────────────────────────────────────────────────────────
  static String _cell(Object? value) {
    if (value == null) return '';
    final s = value.toString();
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    if (!needsQuote) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _row(List<Object?> cells) =>
      cells.map(_cell).join(',') + '\n';

  static String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Copies [text] to the system clipboard and returns whether it succeeded.
  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Grow-out (production) report ───────────────────────────────────────
  String buildGrowthCsv() {
    final t = TankService.instance;
    final buf = StringBuffer();

    buf.writeln('CrayCare Grow-Out Report');
    buf.writeln('Generated,' + _fmtDateTime(DateTime.now()));
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
      buf.writeln(_row([
        'Sampling Records',
        'Date', 'ABW (g)', 'ABL (cm)', 'Sample Size',
        'Total Weight (g)', 'Total Length (cm)', 'Biomass (g)', 'Live Count',
      ]));
      for (final s in samples) {
        buf.writeln(_row([
          '', _fmtDate(s.date), s.abw.toStringAsFixed(2),
          s.avgLength.toStringAsFixed(2), s.sampleSize,
          s.totalWeight.toStringAsFixed(2), s.totalLength.toStringAsFixed(2),
          s.biomass.toStringAsFixed(2), s.liveCount,
        ]));
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
      buf.writeln(_row([
        'Harvest Records', 'Date', 'Harvested Count',
        'Total Weight (kg)', 'ABW (g)', 'Survival Rate (%)',
      ]));
      for (final h in harvests) {
        buf.writeln(_row([
          '', _fmtDate(h.date), h.harvestedCount,
          h.totalWeightKg.toStringAsFixed(3), h.abwGrams.toStringAsFixed(2),
          h.survivalRate.toStringAsFixed(2),
        ]));
      }
      buf.writeln();
    }

    return buf.toString();
  }

  // ── Water Quality Classification (WQC) report ──────────────────────────
  String buildWqcCsv() {
    final hr = HealthRiskService.instance;
    final buf = StringBuffer();

    buf.writeln('CrayCare Water Quality Classification Report');
    buf.writeln('Generated,' + _fmtDateTime(DateTime.now()));
    buf.writeln();

    final history = hr.history;
    if (history.isEmpty) {
      buf.writeln('No assessment history yet. The first assessment appears '
          'after about one hour of sensor data.');
      return buf.toString();
    }

    buf.writeln(_row([
      'Timestamp', 'Level', 'Confidence (%)', 'Driver', 'Driver Value',
      'Unit', 'Problem', 'Action', 'Samples Analyzed', 'Analysis Mode',
    ]));
    for (final h in history) {
      final ts = h.timestamp.toLocal();
      buf.writeln(_row([
        _fmtDateTime(ts),
        h.level,
        h.confidence,
        h.driverLabel,
        h.driverValue?.toStringAsFixed(2) ?? '',
        h.driverUnit,
        h.problem,
        h.action,
        h.samplesAnalyzed,
        h.analysisMode,
      ]));
    }
    buf.writeln();

    // Detailed insight block for the latest assessment.
    final latest = history.first;
    buf.writeln(_row(['Latest Assessment Detail']));
    buf.writeln(_row(['Level', latest.level]));
    buf.writeln(_row(['Confidence (%)', latest.confidence]));
    buf.writeln(_row(['Primary Driver', latest.driverLabel]));
    buf.writeln(_row(['Insight', latest.insight]));
    buf.writeln(_row(['Recommended Action', latest.action]));
    buf.writeln(_row(['Source', latest.source]));
    buf.writeln(_row(['Analysis Mode', latest.analysisMode]));

    return buf.toString();
  }
}
