import 'package:flutter/material.dart';

import '../../services/health_risk_service.dart';
import '../../services/report_export_service.dart';
import '../../theme/app_colors.dart';

/// Bottom sheet listing the hourly Water Quality Classification history and
/// offering a CSV export of the assessment log.
Future<void> showWqcHistorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _WqcHistorySheet(),
  );
}

class _WqcHistorySheet extends StatelessWidget {
  const _WqcHistorySheet();

  Color _levelColor(String level) {
    switch (level) {
      case 'Low':
        return AppColors.success;
      case 'Moderate':
        return AppColors.warning;
      case 'High':
        return AppColors.critical;
      case 'Critical':
        return const Color(0xFF991b1b);
      default:
        return AppColors.mutedText;
    }
  }

  String _fmtTs(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour > 12 ? l.hour - 12 : (l.hour == 0 ? 12 : l.hour);
    final ampm = l.hour >= 12 ? 'PM' : 'AM';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[l.month - 1]} ${l.day}, $h:${l.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final hr = HealthRiskService.instance;
        final history = hr.history;

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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Water Quality History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: history.isEmpty
                        ? null
                        : () async {
                            final ok = await ReportExportService.instance
                                .copyToClipboard(
                                    ReportExportService.instance.buildWqcCsv());
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? 'WQC report copied — paste it into Excel or Google Sheets.'
                                  : 'Could not copy to clipboard.'),
                            ));
                          },
                    icon: const Icon(Icons.content_copy, size: 18),
                    label: const Text('Copy CSV'),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: 'Export WQC report',
                    icon: const Icon(Icons.ios_share,
                        size: 20, color: AppColors.primary),
                    onSelected: (value) async {
                      final svc = ReportExportService.instance;
                      try {
                        if (value == 'csv') {
                          await svc.shareWqcCsv();
                        } else {
                          await svc.shareWqcPdf();
                        }
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(value == 'csv'
                              ? 'CSV report ready — choose where to save or share it.'
                              : 'PDF report ready — choose where to save or share it.'),
                        ));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Export failed: $e'),
                        ));
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'csv',
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text('Export CSV (Excel)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined,
                                size: 18, color: AppColors.primary),
                            SizedBox(width: 10),
                            Text('Export PDF'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No assessment history yet.\nThe first WQC assessment appears after about one hour of sensor data.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.mutedText,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = history[index];
                        final color = _levelColor(item.level);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  item.level,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _fmtTs(item.timestamp),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.darkText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.level == 'Insufficient'
                                          ? item.problem
                                          : '${item.confidence}% confidence · Driver: ${item.driverLabel}',
                                      style: TextStyle(
                                        fontSize: 11,
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
