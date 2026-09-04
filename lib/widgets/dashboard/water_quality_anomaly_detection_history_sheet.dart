import 'package:flutter/material.dart';

import '../../services/report_export_service.dart';
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[local.month - 1]} ${local.day}, $hour:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.95,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Water Quality Anomaly History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Export WQAD report',
                    icon: const Icon(Icons.ios_share, color: AppColors.primary),
                    onSelected: (value) async {
                      final service = ReportExportService.instance;
                      if (value == 'csv') {
                        await service.shareWaterQualityAnomalyDetectionCsv();
                      } else {
                        await service.shareWaterQualityAnomalyDetectionPdf();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                      PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    ],
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
                          'No anomaly-detection history yet.\nTwo hours of continuous readings are required for the first result.',
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
                      padding: const EdgeInsets.all(16),
                      itemCount: history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final item = history[index];
                        final color = item.color;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.lightColor.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: color.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  item.status,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatTimestamp(item.timestamp),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.darkText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.hasData
                                          ? '${item.anomalyScore.toStringAsFixed(1)}/100 · ${item.driverLabel}'
                                          : item.insight,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.subtitleText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
}
