import 'package:flutter/material.dart';

import '../../services/water_quality_anomaly_detection_service.dart';
import '../../theme/app_colors.dart';
import 'water_quality_anomaly_detection_history_sheet.dart';

class WaterQualityAnomalyDetectionCard extends StatefulWidget {
  const WaterQualityAnomalyDetectionCard({super.key});

  @override
  State<WaterQualityAnomalyDetectionCard> createState() =>
      _WaterQualityAnomalyDetectionCardState();
}

class _WaterQualityAnomalyDetectionCardState
    extends State<WaterQualityAnomalyDetectionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WaterQualityAnomalyDetectionService.instance,
      builder: (context, _) {
        final service = WaterQualityAnomalyDetectionService.instance;
        final result = service.result;
        final hasData = result?.isCurrent ?? false;
        // Keep anomaly status visible without letting saturated status colors
        // take over the whole dashboard card.
        final color = !hasData
            ? AppColors.mutedText
            : result!.isAnomaly
            ? AppColors.criticalDark
            : const Color(0xFF4A817C);
        const lightColor = Color(0xFFF1FAFA);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.darkText.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkText.withValues(alpha: 0.035),
                blurRadius: 9,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: lightColor,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Image.asset(
                      'assets/images/water_quality_analysis_icon.png',
                      width: 25,
                      height: 25,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Water Quality Analysis',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Anomaly Detection',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: AppColors.subtitleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        showWaterQualityAnomalyDetectionHistorySheet(context),
                    icon: const Icon(Icons.history_rounded, size: 14),
                    label: const Text('History'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (service.loading)
                const _LoadingState()
              else
                _ResultOverview(
                  isAnomaly: result?.isAnomaly ?? false,
                  score: hasData ? result!.anomalyScore : null,
                  waitingMessage: result?.hasData == true && !hasData
                      ? 'The latest ML analysis is over 90 minutes old. Check the connection and analysis service.'
                      : result?.status == 'Insufficient' &&
                            result?.insight.isNotEmpty == true
                      ? result!.insight
                      : 'Waiting for 12 readings, 10 minutes apart, to analyze the latest 2-hour pattern. Analysis runs every 30 minutes.',
                  color: color,
                  lightColor: lightColor,
                ),
              if (!service.loading && hasData) ...[
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (result!.contributors.isNotEmpty) ...[
                                _DirectionSummary(
                                  contributors: result.contributors,
                                ),
                                const SizedBox(height: 12),
                              ],
                              _ResultDetails(
                                driver: result.driverLabel,
                                driverValue: result.driverValue,
                                driverUnit: result.driverUnit,
                                insight: result.insight,
                                recommendation: result.recommendation,
                                color: color,
                                lightColor: lightColor,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 19,
                    ),
                    label: Text(_expanded ? 'Show less' : 'View details'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ResultOverview extends StatelessWidget {
  final bool isAnomaly;
  final double? score;
  final String waitingMessage;
  final Color color;
  final Color lightColor;

  const _ResultOverview({
    required this.isAnomaly,
    required this.score,
    required this.waitingMessage,
    required this.color,
    required this.lightColor,
  });

  @override
  Widget build(BuildContext context) {
    final safeScore = score?.clamp(0.0, 100.0).toDouble();
    if (safeScore == null) {
      return SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  waitingMessage,
                  style: const TextStyle(
                    color: AppColors.subtitleText,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: lightColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkText.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAnomaly
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAnomaly
                      ? 'Unusual pattern detected'
                      : 'Pattern looks normal',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                safeScore.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: safeScore / 100,
              minHeight: 4,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultDetails extends StatelessWidget {
  final String driver;
  final double? driverValue;
  final String driverUnit;
  final String insight;
  final String recommendation;
  final Color color;
  final Color lightColor;

  const _ResultDetails({
    required this.driver,
    required this.driverValue,
    required this.driverUnit,
    required this.insight,
    required this.recommendation,
    required this.color,
    required this.lightColor,
  });

  @override
  Widget build(BuildContext context) {
    final value = driverValue == null
        ? null
        : '${driverValue!.toStringAsFixed(1)}${driverUnit.isEmpty ? '' : ' $driverUnit'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.darkText.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: lightColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.multiline_chart_rounded,
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Main pattern contributor',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.subtitleText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value == null ? driver : '$driver · $value',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFEAF0F2)),
          ),
          _DetailRow(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Insight',
            text: insight,
            color: AppColors.primary,
          ),
          const SizedBox(height: 11),
          _DetailRow(
            icon: Icons.fact_check_outlined,
            label: 'Suggested checks',
            text: recommendation,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _DirectionSummary extends StatelessWidget {
  final List<Map<String, dynamic>> contributors;

  const _DirectionSummary({required this.contributors});

  @override
  Widget build(BuildContext context) {
    final visible = contributors
        .where((item) => item['direction']?.toString().isNotEmpty == true)
        .take(3)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key sensor directions',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: visible
              .map((item) {
                final label = WaterQualityAnomalyDetectionResult.sensorLabelFor(
                  item['sensor'],
                );
                final direction = item['direction']?.toString() ?? 'stable';
                final isIncreasing = direction == 'increasing';
                final isDecreasing = direction == 'decreasing';
                const color = Color(0xFF718987);
                final icon = isIncreasing
                    ? Icons.arrow_upward_rounded
                    : isDecreasing
                    ? Icons.arrow_downward_rounded
                    : Icons.remove_rounded;
                final directionLabel =
                    direction[0].toUpperCase() + direction.substring(1);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7F7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5ECEB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        '$label: $directionLabel',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(
        minHeight: 3,
        color: AppColors.primary,
        backgroundColor: Color(0xFFE2EEEE),
      ),
      SizedBox(height: 9),
      Text(
        'Analyzing the latest sensor pattern…',
        style: TextStyle(fontSize: 11, color: AppColors.mutedText),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final Color color;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              text,
              style: const TextStyle(
                fontSize: 10,
                height: 1.4,
                color: AppColors.subtitleText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
