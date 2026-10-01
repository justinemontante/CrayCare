import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../utils/snackbar_helper.dart';

class _SamplingMeasurementsTable extends StatelessWidget {
  const _SamplingMeasurementsTable(this.measurements);

  final List<CrayfishMeasurement> measurements;

  Widget _summaryRow(
    String label,
    double weight,
    double length, {
    required Color backgroundColor,
    required Color labelColor,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: AppColors.dark.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: labelColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              weight.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              length.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = measurements.length.clamp(1, 5);
    final totalWeight = measurements.fold<double>(
      0,
      (total, item) => total + item.weightGrams,
    );
    final totalLength = measurements.fold<double>(
      0,
      (total, item) => total + item.lengthCm,
    );
    final averageWeight = measurements.isEmpty
        ? 0.0
        : totalWeight / measurements.length;
    final averageLength = measurements.isEmpty
        ? 0.0
        : totalLength / measurements.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: AppColors.primary.withValues(alpha: 0.06),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Crayfish',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Weight (g)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Length (cm)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: visibleRows * 36.0,
              child: ListView.builder(
                key: const PageStorageKey('sampling_measurements_scroll'),
                primary: false,
                itemCount: measurements.length,
                itemExtent: 36,
                itemBuilder: (context, index) {
                  final item = measurements[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    color: index.isOdd
                        ? AppColors.dark.withValues(alpha: 0.02)
                        : Colors.white,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.weightGrams.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            item.lengthCm.toStringAsFixed(2),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.dark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _summaryRow(
              'Total',
              totalWeight,
              totalLength,
              backgroundColor: AppColors.dark.withValues(alpha: 0.02),
              labelColor: AppColors.primary,
            ),
            _summaryRow(
              'Average',
              averageWeight,
              averageLength,
              backgroundColor: Colors.white,
              labelColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class SamplingTab extends StatelessWidget {
  final DateTime lastEdited;

  const SamplingTab({super.key, required this.lastEdited});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!TankService.instance.isInitialized)
            _buildEmptyState()
          else ...[
            const Align(
              alignment: Alignment.centerRight,
              child: SamplingHistoryShortcut(),
            ),
            const SizedBox(height: 6),
            NextSamplingPanel(action: SamplingEntryLauncher()),
            const SizedBox(height: 12),
            GrowthOverviewPanel(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.speed_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sampling Restricted',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You must initialize your tank inventory first before you can record sampling data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.dark.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class SamplingHistoryShortcut extends StatelessWidget {
  const SamplingHistoryShortcut({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showSamplingHistory(context),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryWith(0.08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.primaryWith(0.22)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 13, color: AppColors.primary),
            SizedBox(width: 5),
            Text(
              'Sampling History',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSamplingHistory(
  BuildContext context, {
  bool expandBaseline = false,
}) {
  var baselineExpansionReady = false;
  var expansionScheduled = false;
  final history = TankService.instance.samplingHistory.toList()
    ..sort((a, b) {
      if (expandBaseline && a.isBaseline != b.isBaseline) {
        return a.isBaseline ? -1 : 1;
      }
      return b.date.compareTo(a.date);
    });
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        if (expandBaseline && !expansionScheduled) {
          expansionScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future<void>.delayed(const Duration(milliseconds: 380), () {
              if (sheetContext.mounted) {
                setSheetState(() => baselineExpansionReady = true);
              }
            });
          });
        }
        return Container(
      height: MediaQuery.of(sheetContext).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dark.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sampling History',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                ),
                Text(
                  '${history.length} recorded',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.dark.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Text(
                      'No sampling records yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.dark.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final entry = history[index];
                      final totalWeekly = history
                          .where((item) => !item.isBaseline)
                          .length;
                      final newerWeekly = history
                          .take(index)
                          .where((item) => !item.isBaseline)
                          .length;
                      final weeklyNumber = totalWeekly - newerWeekly;
                      final title = entry.isBaseline
                          ? 'Initial Baseline'
                          : 'Week $weeklyNumber';
                      final date = _samplingDateLabel(entry.date);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: ExpansionTile(
                          key: ValueKey(
                            'top_sampling_history_${entry.id}_${entry.isBaseline && baselineExpansionReady}',
                          ),
                          initiallyExpanded:
                              expandBaseline &&
                              baselineExpansionReady &&
                              entry.isBaseline,
                          backgroundColor: Colors.transparent,
                          collapsedBackgroundColor: Colors.transparent,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            12,
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          subtitle: Text(
                            '$date  •  ${entry.sampleSize} sampled\nABW ${entry.abw.toStringAsFixed(2)} g  •  ABL ${entry.avgLength.toStringAsFixed(2)} cm',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: AppColors.dark.withValues(alpha: 0.6),
                            ),
                          ),
                          children: [
                            if (entry.measurements.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Individual measurements are unavailable for this record.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.dark,
                                  ),
                                ),
                              )
                            else
                              _SamplingMeasurementsTable(entry.measurements),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
        );
      },
    ),
  );
}

String _samplingDateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class NextSamplingPanel extends StatelessWidget {
  final Widget? action;

  const NextSamplingPanel({super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final daysSince = service.daysSinceLastSampling;
    final daysRemaining = daysSince >= 7 ? 0 : 7 - daysSince;
    // Session number is based on completed weekly records. Calling this a
    // session avoids showing an incorrect culture week when one was missed.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header and session subtitle ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.calendar_today_rounded,
                  color: AppColors.primary,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sampling Schedule',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Session ${service.samplingHistory.where((entry) => !entry.isBaseline).length + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark.withValues(alpha: 0.48),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            daysRemaining == 0
                ? 'Your next sampling is due today.'
                : 'Your next sampling is on ${_formatDate(DateTime.now().add(Duration(days: daysRemaining)))}.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppColors.dark.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.dark.withValues(alpha: 0.05),
          ),
          const SizedBox(height: 12),

          // ── Details Row (Clean, Non-Redundant) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    daysRemaining == 0
                        ? 'Ready to record'
                        : '$daysRemaining days left',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStepTracker(daysSince >= 7 ? 7 : daysSince, 7),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Widget _buildStepTracker(int currentDay, int totalDays) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(totalDays, (index) {
            final day = index + 1;
            final isPast = day < currentDay;
            final isCurrent = day == currentDay;

            return Expanded(
              child: Row(
                children: [
                  _buildStepDot(day, isPast, isCurrent),
                  if (index < totalDays - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isPast ? AppColors.primary : AppColors.lightBg,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Day $currentDay',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDot(int day, bool isPast, bool isCurrent) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: isPast
            ? AppColors.primary
            : (isCurrent ? AppColors.warning : AppColors.white),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPast
              ? AppColors.primary
              : (isCurrent ? AppColors.warning : AppColors.faintBorder),
          width: 2,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.warningWith(0.2),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isPast || isCurrent ? Colors.white : AppColors.darkWith(0.5),
          ),
        ),
      ),
    );
  }
}

class GrowthOverviewPanel extends StatelessWidget {
  const GrowthOverviewPanel({super.key});

  void _showModal(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color iconColor,
    Color iconBgColor,
    String description,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory;
    final hasWeeklySampling = history.any((e) => !e.isBaseline);
    final latest = hasWeeklySampling
        ? history.lastWhere((e) => !e.isBaseline)
        : null;
    final initialW = service.initialWeight;
    final initialL = service.initialLength;

    final latestW = latest?.abw ?? initialW;
    final latestL = latest?.avgLength ?? initialL;

    final diffW = latestW - initialW;
    final diffL = latestL - initialL;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Growth Overview',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMiniCard(
                  'Initial Baseline',
                  _formatDate(service.stockingDate),
                  initialW,
                  initialL,
                  false,
                  () => _showModal(
                    context,
                    'Initial Baseline',
                    'ABW: ${initialW.toStringAsFixed(2)} g  |  ABL: ${initialL.toStringAsFixed(2)} cm',
                    'Stocked on ${_formatDate(service.stockingDate)}',
                    Icons.calendar_today_outlined,
                    const Color(0xFF0891B2),
                    const Color(0xFFECFEFF),
                    'These are the initial size measurements of the crayfish recorded at grow-out initialization. They serve as the starting baseline for growth rates and population development.',
                  ),
                ),
                const SizedBox(width: 12),
                hasWeeklySampling
                    ? _buildMiniCard(
                        'Latest Sampling',
                        _formatDate(latest!.date),
                        latestW,
                        latestL,
                        true,
                        () => _showModal(
                          context,
                          'Latest Sampling',
                          'ABW: ${latestW.toStringAsFixed(2)} g  |  ABL: ${latestL.toStringAsFixed(2)} cm',
                          'Recorded on ${_formatDate(latest.date)}',
                          Icons.science_outlined,
                          const Color(0xFF0F766E),
                          const Color(0xFFF0FDFA),
                          'This represents the most recent growth measurements. Regular updates help track weekly changes in Average Body Weight and Average Body Length.',
                        ),
                      )
                    : _buildAwaitingCard(
                        () => _showModal(
                          context,
                          'Latest Sampling',
                          'Awaiting Week 1',
                          'Pending session',
                          Icons.hourglass_empty_rounded,
                          AppColors.darkWith(0.35),
                          AppColors.darkWith(0.06),
                          'No weekly growth data has been recorded yet. The app is waiting for your Week 1 sampling session to begin compiling growth rates.',
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildGrowthFullCard(
            diffW,
            diffL,
            () => _showModal(
              context,
              'Growth Change',
              'Weight: ${diffW >= 0 ? "+" : ""}${diffW.toStringAsFixed(2)} g  |  Length: ${diffL >= 0 ? "+" : ""}${diffL.toStringAsFixed(2)} cm',
              'Total Gain since Stocking',
              Icons.trending_up_rounded,
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.1),
              'This illustrates the overall change in average crayfish weight and length since grow-out stocking initialization.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard(
    String title,
    String subTitle,
    double weight,
    double length,
    bool isLatest,
    VoidCallback onTap,
  ) {
    final iconColor = isLatest
        ? const Color(0xFF0F766E)
        : const Color(0xFF0891B2);
    final iconBgColor = isLatest
        ? const Color(0xFFF0FDFA)
        : const Color(0xFFECFEFF);
    final iconData = isLatest
        ? Icons.science_outlined
        : Icons.calendar_today_outlined;
    final titleColor = isLatest
        ? const Color(0xFF0F766E)
        : const Color(0xFF0891B2);

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon centered at top ──
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, size: 16, color: iconColor),
                  ),
                  const SizedBox(height: 6),
                  // ── Title & subtitle centered ──
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Full-width divider ──
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: AppColors.dark.withValues(alpha: 0.06),
                  ),
                  const SizedBox(height: 8),
                  // ── ABW and ABL inline ──
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'ABW',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkWith(0.45),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${weight.toStringAsFixed(2)} g',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // vertical separator
                        Container(
                          width: 1,
                          color: AppColors.dark.withValues(alpha: 0.08),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'ABL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkWith(0.45),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${length.toStringAsFixed(2)} cm',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAwaitingCard(VoidCallback onTap) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon centered at top ──
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FDFA),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── Title & subtitle centered ──
                  const Text(
                    'Latest Sampling',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pending',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Full-width divider ──
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: AppColors.dark.withValues(alpha: 0.06),
                  ),
                  const SizedBox(height: 8),
                  // ── Centered awaiting placeholder ──
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_empty_rounded,
                            size: 20,
                            color: AppColors.darkWith(0.2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Awaiting Week 1',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkWith(0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrowthFullCard(
    double weight,
    double length,
    VoidCallback onTap,
  ) {
    final isPosW = weight >= 0;
    final isPosL = length >= 0;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Growth Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                IntrinsicHeight(
                  child: Row(
                    children: [
                      _buildGrowthMetric(
                        'Weight Gain',
                        '${isPosW ? '+' : ''}${weight.toStringAsFixed(1)}g',
                        isPosW,
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, color: AppColors.darkWith(0.25)),
                      const SizedBox(width: 10),
                      _buildGrowthMetric(
                        'Length Gain',
                        '${isPosL ? '+' : ''}${length.toStringAsFixed(1)}cm',
                        isPosL,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrowthMetric(String label, String value, bool isPos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.5)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isPos ? AppColors.success : AppColors.critical,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class SamplingEntryLauncher extends StatefulWidget {
  const SamplingEntryLauncher({super.key});

  @override
  State<SamplingEntryLauncher> createState() => _SamplingEntryLauncherState();
}

class _SamplingEntryLauncherState extends State<SamplingEntryLauncher> {
  Future<void> _openSamplingForm() async {
    final saveResult = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final sheetHeight = (media.size.height * 0.88 - media.viewInsets.bottom)
            .clamp(320.0, media.size.height)
            .toDouble();
        return Container(
          height: sheetHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.dark.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      left: 14,
                      right: 14,
                      bottom: media.viewInsets.bottom + 20,
                    ),
                    child: SamplingFormPanel(
                      onSaved: (wasEditing) => Navigator.of(
                        sheetContext,
                      ).pop(wasEditing ? 'updated' : 'recorded'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (saveResult != null && mounted) {
      showBeautifulSnackbar(
        context,
        saveResult == 'updated'
            ? 'Sampling successfully updated!'
            : 'Sampling successfully recorded!',
        true,
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSamplingForm,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.primary, Color(0xFF52C8C3)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.science_outlined, size: 17, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Sample Now',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SamplingFormPanel extends StatefulWidget {
  final ValueChanged<bool>? onSaved;

  const SamplingFormPanel({super.key, this.onSaved});

  @override
  State<SamplingFormPanel> createState() => _SamplingFormPanelState();
}

class _SamplingFormPanelState extends State<SamplingFormPanel> {
  final _countController = TextEditingController();
  final _weightControllers = <TextEditingController>[];
  final _lengthControllers = <TextEditingController>[];
  bool _isRecorded = false;
  bool _isEditing = false;
  bool _showValidationErrors = false;
  String? _countError;
  String? _measurementError;
  late final VoidCallback _serviceListener;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _checkLastSampling();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _serviceListener = () {
      if (mounted) setState(() => _checkLastSampling());
    };
    TankService.instance.addListener(_serviceListener);
  }

  void _checkLastSampling() {
    _isEditing = false;
    final history = TankService.instance.samplingHistory
        .where((entry) => !entry.isBaseline)
        .toList();
    var sampleSize = TankService.instance.sampleCount;
    if (history.isNotEmpty) {
      final last = history.last;
      final today = DateTime.now();
      if (last.date.day == today.day &&
          last.date.month == today.month &&
          last.date.year == today.year) {
        _isRecorded = true;
        sampleSize = last.sampleSize;
        if (last.hasIndividualMeasurements) {
          _loadMeasurements(last.measurements);
        } else {
          _clearMeasurements();
        }
      } else {
        _isRecorded = false;
        _clearMeasurements();
      }
    } else {
      _isRecorded = false;
      _clearMeasurements();
    }
    _countController.text = sampleSize > 0 ? sampleSize.toString() : '';
    if (!_isRecorded ||
        history.isEmpty ||
        history.last.hasIndividualMeasurements) {
      _resizeMeasurementControllers(sampleSize);
    }
    _revalidateCount();
  }

  void _resizeMeasurementControllers(int requested) {
    if (requested < 0 || requested > maxCrayfishMeasurementsPerSample) return;
    while (_weightControllers.length < requested) {
      _weightControllers.add(TextEditingController());
      _lengthControllers.add(TextEditingController());
    }
    while (_weightControllers.length > requested) {
      _weightControllers.removeLast().dispose();
      _lengthControllers.removeLast().dispose();
    }
  }

  void _clearMeasurements() {
    for (final controller in _weightControllers) {
      controller.clear();
    }
    for (final controller in _lengthControllers) {
      controller.clear();
    }
  }

  void _loadMeasurements(List<CrayfishMeasurement> measurements) {
    _resizeMeasurementControllers(measurements.length);
    for (var i = 0; i < measurements.length; i++) {
      _weightControllers[i].text = measurements[i].weightGrams.toString();
      _lengthControllers[i].text = measurements[i].lengthCm.toString();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    TankService.instance.removeListener(_serviceListener);
    _countController.dispose();
    for (final controller in _weightControllers) {
      controller.dispose();
    }
    for (final controller in _lengthControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _revalidateCount() {
    final countText = _countController.text.trim();
    final count = int.tryParse(countText);
    final inTankCount = TankService.instance.inTankCount;
    if (countText.isEmpty) {
      _countError = _showValidationErrors
          ? 'Enter a sample size greater than zero.'
          : null;
    } else if (count == null || count <= 0) {
      _countError = 'Sample size must be a positive whole number.';
    } else if (count > maxCrayfishMeasurementsPerSample) {
      _countError =
          'A sample can contain up to $maxCrayfishMeasurementsPerSample individual entries.';
    } else if (inTankCount < count) {
      _countError = 'Needs $count crayfish, but only $inTankCount remain.';
    } else {
      _countError = null;
    }
    final invalidEnteredValue = [..._weightControllers, ..._lengthControllers]
        .any((controller) {
          final text = controller.text.trim();
          if (text.isEmpty) return false;
          final value = double.tryParse(text);
          return value == null || !value.isFinite || value <= 0;
        });
    final incompleteMeasurements =
        _weightControllers.length != (count ?? 0) ||
        _weightControllers.any((controller) {
          return controller.text.trim().isEmpty;
        }) ||
        _lengthControllers.any((controller) {
          return controller.text.trim().isEmpty;
        });
    _measurementError =
        invalidEnteredValue || (_showValidationErrors && incompleteMeasurements)
        ? 'Enter a positive weight and length for every crayfish.'
        : null;
  }

  String? _measurementFieldError(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) {
      return _showValidationErrors ? 'Required' : null;
    }
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) {
      return 'Must be > 0.';
    }
    return null;
  }

  Widget _measurementInput({
    required TextEditingController controller,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$')),
      ],
      onChanged: (_) => setState(_revalidateCount),
      decoration: InputDecoration(
        hintText: '0.0',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        border: const OutlineInputBorder(),
        errorMaxLines: 1,
        errorStyle: const TextStyle(fontSize: 8, height: 1),
        errorText: _measurementFieldError(controller),
      ),
    );
  }

  Future<void> _handleCompute() async {
    if (!TankService.instance.canSample && !_isEditing) {
      showBeautifulSnackbar(
        context,
        '7-day cooldown not yet over. Please wait.',
        false,
      );
      return;
    }
    setState(() {
      _showValidationErrors = true;
      _revalidateCount();
    });
    if (_countError != null) return;
    if (_measurementError != null) {
      showBeautifulSnackbar(context, _measurementError!, false);
      return;
    }
    {
      final wasEditing = _isEditing;
      final service = TankService.instance;
      final count = int.tryParse(_countController.text) ?? 0;
      if (count <= 0) {
        showBeautifulSnackbar(
          context,
          'No sample size was set for this batch.',
          false,
        );
        return;
      }
      if (service.inTankCount < count) {
        showBeautifulSnackbar(
          context,
          'Sampling needs $count crayfish, but only ${service.inTankCount} remain in the tank.',
          false,
        );
        return;
      }

      try {
        final measurements = List.generate(
          count,
          (index) => CrayfishMeasurement(
            sampleNumber: index + 1,
            weightGrams: double.parse(_weightControllers[index].text),
            lengthCm: double.parse(_lengthControllers[index].text),
          ),
        );
        if (wasEditing) {
          await TankService.instance.updateLastSamplingEntry(measurements);
        } else {
          await TankService.instance.addSamplingEntry(measurements);
        }
      } catch (e) {
        if (!mounted) return;
        showBeautifulSnackbar(
          context,
          'Failed to save sampling: ${e.toString().replaceFirst('Exception: ', '')}',
          false,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _isRecorded = true;
        _isEditing = false;
      });
      widget.onSaved?.call(wasEditing);
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  void _handleEdit() {
    final weekly = TankService.instance.samplingHistory
        .where((entry) => !entry.isBaseline)
        .toList();
    if (weekly.isEmpty) return;
    final lastEntry = weekly.last.date;
    if (!_isToday(lastEntry)) {
      showBeautifulSnackbar(
        context,
        'Sampling data can only be edited on the same day it was recorded.',
        false,
      );
      return;
    }
    final entry = weekly.last;
    if (!entry.hasIndividualMeasurements) {
      showBeautifulSnackbar(
        context,
        'This older record has totals only, so it cannot be edited as individual crayfish.',
        false,
      );
      return;
    }
    setState(() {
      _countController.text = entry.sampleSize.toString();
      _loadMeasurements(entry.measurements);
      _showValidationErrors = false;
      _isRecorded = false;
      _isEditing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSample = TankService.instance.canSample;
    final service = TankService.instance;
    final weeklySampling = service.samplingHistory
        .where((entry) => !entry.isBaseline)
        .toList();
    final lastEntryIsToday = weeklySampling.isNotEmpty
        ? _isToday(weeklySampling.last.date)
        : false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Record Sampling',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              if (_isRecorded && lastEntryIsToday)
                TextButton(
                  onPressed: _handleEdit,
                  child: const Text(
                    'Edit',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInputCard(
            Image.asset('assets/images/SampleCount.png', width: 20, height: 20),
            'Sample Size',
            'Enter the number of crayfish to measure this session',
            '${service.sampleCount}',
            _countController,
            enabled: (!_isRecorded && canSample) || _isEditing,
            hasError: _countError != null,
            onChanged: () {
              setState(() {
                final count = int.tryParse(_countController.text) ?? 0;
                _resizeMeasurementControllers(count);
                _revalidateCount();
              });
            },
            subtitleBottomSpacing: 8,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  (!_isRecorded && (canSample || _isEditing)) &&
                      _weightControllers.length <
                          maxCrayfishMeasurementsPerSample &&
                      _weightControllers.length < service.inTankCount
                  ? () {
                      final next = _weightControllers.length + 1;
                      setState(() {
                        _countController.text = '$next';
                        _resizeMeasurementControllers(next);
                        _revalidateCount();
                      });
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Add next crayfish'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Individual measurements (${_weightControllers.length})',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: AppColors.dark.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    color: AppColors.primary.withValues(alpha: 0.06),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(
                            'Crayfish',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Weight (g)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Length (cm)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(_weightControllers.length, (index) {
                    final enabled = (!_isRecorded && canSample) || _isEditing;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: index.isOdd
                            ? AppColors.dark.withValues(alpha: 0.02)
                            : Colors.white,
                        border: Border(
                          top: BorderSide(
                            color: AppColors.dark.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 76,
                            height: 42,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Crayfish ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _measurementInput(
                              controller: _weightControllers[index],
                              enabled: enabled,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _measurementInput(
                              controller: _lengthControllers[index],
                              enabled: enabled,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          if (_measurementError != null && !_isRecorded) ...[
            const SizedBox(height: 4),
            Text(
              _measurementError!,
              style: TextStyle(fontSize: 10, color: AppColors.critical),
            ),
          ],
          if (_countError != null && !_isRecorded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.critical.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: AppColors.critical,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _countError!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.critical.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!_isRecorded && (canSample || _isEditing))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _countError == null && _measurementError == null
                    ? _handleCompute
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _countError == null
                      ? AppColors.primary
                      : AppColors.dark.withValues(alpha: 0.2),
                  foregroundColor: _countError == null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  disabledBackgroundColor: AppColors.dark.withValues(
                    alpha: 0.2,
                  ),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Compute Results',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          if (!_isRecorded && !canSample && !_isEditing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: Text(
                  'Sampling available in ${(7 - TankService.instance.daysSinceLastSampling).clamp(0, 7)} days',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark.withValues(alpha: 0.15),
                  foregroundColor: AppColors.dark.withValues(alpha: 0.5),
                  disabledBackgroundColor: AppColors.dark.withValues(
                    alpha: 0.15,
                  ),
                  disabledForegroundColor: AppColors.dark.withValues(
                    alpha: 0.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_isRecorded)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text(
                  'Recorded',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.success,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputCard(
    Widget iconWidget,
    String label,
    String subtitle,
    String hint,
    TextEditingController controller, {
    bool enabled = true,
    bool hasError = false,
    VoidCallback? onChanged,
    double subtitleBottomSpacing = 8,
  }) {
    final borderColor = hasError && enabled
        ? AppColors.critical.withValues(alpha: 0.6)
        : AppColors.dark.withValues(alpha: 0.15);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primaryWith(0.03)
            : AppColors.primaryWith(0.01),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError && enabled
              ? AppColors.critical.withValues(alpha: 0.35)
              : (enabled ? AppColors.darkWith(0.08) : AppColors.darkWith(0.04)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: iconWidget,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: hasError && enabled
                  ? AppColors.critical
                  : (enabled ? AppColors.dark : AppColors.darkWith(0.4)),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: hasError && enabled
                  ? AppColors.critical.withValues(alpha: 0.6)
                  : (enabled
                        ? AppColors.darkWith(0.5)
                        : AppColors.darkWith(0.3)),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: subtitleBottomSpacing),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged?.call(),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$')),
            ],
            textAlign: TextAlign.center,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: enabled ? Colors.white : AppColors.darkWith(0.04),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError && enabled
                      ? AppColors.critical
                      : AppColors.primary,
                ),
              ),
              hintStyle: TextStyle(
                fontSize: 12,
                color: AppColors.darkWith(0.3),
              ),
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: hasError && enabled
                  ? AppColors.critical
                  : (enabled ? AppColors.dark : AppColors.darkWith(0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class GrowthStagePanel extends StatelessWidget {
  final VoidCallback onInfoTap;

  const GrowthStagePanel({super.key, required this.onInfoTap});

  static const List<_StageRange> _stages = [
    _StageRange(abwMin: 1, abwMax: 5, ablMin: 2, ablMax: 4),
    _StageRange(abwMin: 5, abwMax: 15, ablMin: 4, ablMax: 6),
    _StageRange(abwMin: 15, abwMax: 50, ablMin: 6, ablMax: 10),
    _StageRange(abwMin: 50, abwMax: 120, ablMin: 10, ablMax: 14),
  ];

  static const List<String> _labels = [
    'Early Juvenile',
    'Advanced Juvenile',
    'Pre-Adult',
    'Market Size',
  ];

  int _indexOf(GrowthStage stage) {
    switch (stage) {
      case GrowthStage.earlyJuvenile:
        return 0;
      case GrowthStage.advancedJuvenile:
        return 1;
      case GrowthStage.preAdult:
        return 2;
      case GrowthStage.marketSize:
        return 3;
    }
  }

  double _calcProgress(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (value - min) / (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory;

    final currentAbw = history.isNotEmpty
        ? history.last.abw
        : service.initialWeight;

    final currentAbl = history.isNotEmpty
        ? history.last.avgLength
        : service.initialLength;

    final currentStage = service.currentGrowthStage;
    final activeIndex = _indexOf(currentStage);
    final range = _stages[activeIndex];

    final abwProgress = _calcProgress(currentAbw, range.abwMin, range.abwMax);
    final ablProgress = currentAbl > 0
        ? _calcProgress(currentAbl, range.ablMin, range.ablMax)
        : 1.0;
    final stageProgress =
        (abwProgress < ablProgress ? abwProgress : ablProgress).clamp(0.0, 1.0);

    // Scale progress across the entire bar (4 stages, each represents 25% or 0.25)
    final progress = ((activeIndex * 0.25) + (stageProgress * 0.25)).clamp(
      0.0,
      1.0,
    );

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Growth Stage',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                    Text(
                      'Current: ${_labels[activeIndex]}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: onInfoTap,
                  child: const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.darkWith(0.06),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_labels.length, (i) {
                final isThisActive = i == activeIndex;
                final isReached = i <= activeIndex;

                return Expanded(
                  child: Text(
                    _labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: isThisActive
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isThisActive
                          ? AppColors.primary
                          : isReached
                          ? AppColors.darkWith(0.7)
                          : AppColors.darkWith(0.3),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ABW: ${currentAbw.toStringAsFixed(1)}g',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 1,
                      height: 14,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    Text(
                      'ABL: ${currentAbl.toStringAsFixed(1)}cm',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Stage is based on both ABW and ABL.',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRange {
  final double abwMin;
  final double abwMax;
  final double ablMin;
  final double ablMax;

  const _StageRange({
    required this.abwMin,
    required this.abwMax,
    required this.ablMin,
    required this.ablMax,
  });
}

class _HistoryEntry {
  final String title;
  final String dateLabel;
  final double abw;
  final double abl;
  final int sampleSize;
  final double? gainW;
  final double? gainL;
  final Widget? icon;
  final List<CrayfishMeasurement> measurements;
  _HistoryEntry({
    this.title = '',
    this.dateLabel = '',
    this.abw = 0,
    this.abl = 0,
    this.sampleSize = 0,
    this.gainW,
    this.gainL,
    this.icon,
    this.measurements = const [],
  });
}

class SamplingHistoryPanel extends StatelessWidget {
  const SamplingHistoryPanel({super.key});

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showAllHistory(BuildContext context) {
    final service = TankService.instance;
    final allHistory = service.samplingHistory
        .where((e) => !e.isBaseline)
        .toList();

    List<_HistoryEntry> entries = [];
    final baseline = service.samplingHistory
        .where((entry) => entry.isBaseline)
        .firstOrNull;
    entries.add(
      _HistoryEntry(
        title: 'Week 0 (Baseline)',
        dateLabel: _formatDate(service.stockingDate),
        abw: service.initialWeight,
        abl: service.initialLength,
        sampleSize: service.sampleCount,
        measurements: baseline?.measurements ?? const [],
        icon: Image.asset(
          'assets/images/InitialPopulation.png',
          width: 20,
          height: 20,
        ),
      ),
    );
    for (int i = 0; i < allHistory.length; i++) {
      final entry = allHistory[i];
      final prevAbw = i == 0 ? service.initialWeight : allHistory[i - 1].abw;
      final prevAbl = i == 0
          ? service.initialLength
          : allHistory[i - 1].avgLength;
      entries.add(
        _HistoryEntry(
          title: 'Week ${i + 1}',
          dateLabel: _formatDate(entry.date),
          abw: entry.abw,
          abl: entry.avgLength,
          sampleSize: entry.sampleSize,
          measurements: entry.measurements,
          gainW: entry.abw - prevAbw,
          gainL: entry.avgLength - prevAbl,
          icon: const Icon(
            Icons.biotech_rounded,
            size: 18,
            color: AppColors.primary,
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.55,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'All Sampling History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.dark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entries.length} entries',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.reversed.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final entry = entries.reversed.toList()[i];
                    final isLatest =
                        i == 0 && !entry.title.contains('Baseline');
                    return _buildHistoryCard(
                      title: entry.title,
                      dateLabel: entry.dateLabel,
                      abw: entry.abw,
                      abl: entry.abl,
                      sampleSize: entry.sampleSize,
                      measurements: entry.measurements,
                      isLatest: isLatest,
                      icon: entry.icon!,
                      gainW: entry.gainW,
                      gainL: entry.gainL,
                      alternateTint: i.isOdd,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryCard({
    required String title,
    required String dateLabel,
    required double abw,
    required double abl,
    required int sampleSize,
    required bool isLatest,
    required Widget icon,
    double? gainW,
    double? gainL,
    bool alternateTint = false,
    List<CrayfishMeasurement> measurements = const [],
  }) {
    const cardColor = Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: ExpansionTile(
        key: PageStorageKey('sampling_history_${title}_$dateLabel'),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: icon,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkWith(0.45),
                    ),
                  ),
                ],
              ),
            ),
            if (isLatest)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Latest',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildDetailBadge(
                  'Sample Size',
                  '$sampleSize',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDetailBadge(
                  'ABW',
                  '${abw.toStringAsFixed(2)} g',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDetailBadge(
                  'ABL',
                  '${abl.toStringAsFixed(2)} cm',
                  AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        children: [
          if (measurements.isEmpty)
            const Text(
              'Individual measurements are unavailable for this older record.',
              style: TextStyle(fontSize: 10, color: AppColors.dark),
            )
          else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Individual measurements',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _SamplingMeasurementsTable(measurements),
          ],
          if (gainW != null && gainL != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Weight gain: ${gainW >= 0 ? "+" : ""}${gainW.toStringAsFixed(2)} g',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: gainW >= 0
                          ? AppColors.success
                          : AppColors.critical,
                    ),
                  ),
                  Text(
                    'Length gain: ${gainL >= 0 ? "+" : ""}${gainL.toStringAsFixed(2)} cm',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: gainL >= 0
                          ? AppColors.success
                          : AppColors.critical,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMainViewCards() {
    final service = TankService.instance;
    final weeklyHistory = service.samplingHistory
        .where((e) => !e.isBaseline)
        .toList();
    final baseline = service.samplingHistory
        .where((entry) => entry.isBaseline)
        .firstOrNull;

    final baselineCard = _buildHistoryCard(
      title: 'Initial Baseline',
      dateLabel: _formatDate(baseline?.date ?? service.stockingDate),
      abw: baseline?.abw ?? service.initialWeight,
      abl: baseline?.avgLength ?? service.initialLength,
      sampleSize: baseline?.sampleSize ?? service.sampleCount,
      measurements: baseline?.measurements ?? const [],
      isLatest: false,
      alternateTint: weeklyHistory.length.isOdd,
      icon: Image.asset(
        'assets/images/InitialPopulation.png',
        width: 20,
        height: 20,
      ),
    );

    if (weeklyHistory.isEmpty) {
      return [baselineCard];
    }

    final totalWeekly = weeklyHistory.length;
    final showCount = totalWeekly >= 2 ? 2 : 1;
    final recent = weeklyHistory.reversed.take(showCount).toList();

    return [
      ...recent.asMap().entries.map((e) {
        final idxInRecent = e.key;
        final idxInHistory = totalWeekly - 1 - idxInRecent;
        final entry = e.value;

        final prevIdx = idxInHistory - 1;
        final prevAbw = prevIdx < 0
            ? service.initialWeight
            : weeklyHistory[prevIdx].abw;
        final prevAbl = prevIdx < 0
            ? service.initialLength
            : weeklyHistory[prevIdx].avgLength;

        return _buildHistoryCard(
          title: 'Week ${idxInHistory + 1}',
          dateLabel: _formatDate(entry.date),
          abw: entry.abw,
          abl: entry.avgLength,
          sampleSize: entry.sampleSize,
          measurements: entry.measurements,
          isLatest: idxInRecent == 0,
          icon: const Icon(
            Icons.biotech_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          gainW: entry.abw - prevAbw,
          gainL: entry.avgLength - prevAbl,
          alternateTint: idxInRecent.isOdd,
        );
      }),
      baselineCard,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sampling History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              TextButton(
                onPressed: () => _showAllHistory(context),
                child: const Text(
                  'View All',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!TankService.instance.isInitialized)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No sampling history yet.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.4),
                  ),
                ),
              ),
            )
          else ...[
            ..._buildMainViewCards(),
          ],
        ],
      ),
    );
  }
}
