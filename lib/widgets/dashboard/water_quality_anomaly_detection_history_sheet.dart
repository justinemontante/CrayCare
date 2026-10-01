import 'package:flutter/material.dart';

import '../../services/water_quality_anomaly_detection_service.dart';
import '../../theme/app_colors.dart';

Future<void> showWaterQualityAnomalyDetectionHistorySheet(
  BuildContext context,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _WaterQualityAnomalyDetectionHistorySheet(),
  );
}

class _WaterQualityAnomalyDetectionHistorySheet extends StatelessWidget {
  const _WaterQualityAnomalyDetectionHistorySheet();

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
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
    return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.88,
      expand: false,
      builder: (context, controller) {
        final history = WaterQualityAnomalyDetectionService.instance.history;
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkWith(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Water Quality Analysis History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No analysis history yet.\nTwelve continuous readings are needed for the first result.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final color = item.color;
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showDetails(
                              context,
                              item,
                              _formatTimestamp(item.timestamp),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppColors.darkText.withValues(
                                    alpha: 0.09,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _formatTimestamp(item.timestamp),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.darkText,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.mutedText,
                                        size: 21,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 9),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 7,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _StatusBadge(
                                        status: item.status,
                                        color: color,
                                      ),
                                      if (item.hasData)
                                        Text(
                                          'Score ${item.anomalyScore.toStringAsFixed(1)} / 100',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.hasData
                                        ? '${item.driverLabel}${item.driverValue == null ? '' : ' · ${item.driverValue!.toStringAsFixed(1)}${item.driverUnit.isEmpty ? '' : ' ${item.driverUnit}'}'}'
                                        : item.insight,
                                    softWrap: true,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color: AppColors.subtitleText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showDetails(
    BuildContext context,
    WaterQualityAnomalyDetectionResult item,
    String timestamp,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    color: AppColors.primary,
                    size: 21,
                  ),
                  SizedBox(width: 9),
                  Text(
                    'Analysis Details',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: AppColors.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.subtitleText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusBadge(status: item.status, color: item.color),
                  if (item.hasData)
                    Text(
                      'Anomaly score: ${item.anomalyScore.toStringAsFixed(1)} / 100',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: item.color,
                      ),
                    ),
                ],
              ),
              if (item.hasData && item.primaryContributor != null) ...[
                const SizedBox(height: 18),
                _DetailSection(
                  icon: Icons.insights_rounded,
                  label: 'Main pattern contributor',
                  text:
                      '${item.driverLabel}${item.driverValue == null ? '' : ' · ${item.driverValue!.toStringAsFixed(1)}${item.driverUnit.isEmpty ? '' : ' ${item.driverUnit}'}'}',
                ),
              ],
              if (item.contributors.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DetailSection(
                  icon: Icons.multiline_chart_rounded,
                  label: 'Sensor directions',
                  text: item.contributors
                      .map((entry) {
                        final sensor =
                            WaterQualityAnomalyDetectionResult.sensorLabelFor(
                              entry['sensor'],
                            );
                        final direction = entry['direction']?.toString();
                        return direction == null || direction.isEmpty
                            ? sensor
                            : '$sensor: $direction';
                      })
                      .join('\n'),
                ),
              ],
              const SizedBox(height: 16),
              _DetailSection(
                icon: Icons.lightbulb_outline_rounded,
                label: 'Insight',
                text: item.insight,
              ),
              const SizedBox(height: 16),
              _DetailSection(
                icon: Icons.fact_check_outlined,
                label: 'Suggested checks',
                text: item.recommendation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      status,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;

  const _DetailSection({
    required this.icon,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.darkText,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        text.isEmpty ? 'No details available.' : text,
        softWrap: true,
        style: const TextStyle(
          fontSize: 11,
          height: 1.45,
          color: AppColors.subtitleText,
        ),
      ),
    ],
  );
}
