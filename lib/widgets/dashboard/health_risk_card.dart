import 'package:flutter/material.dart';

import '../../services/health_risk_service.dart';
import '../../theme/app_colors.dart';
import 'wqc_history_sheet.dart';

class HealthRiskCard extends StatelessWidget {
  const HealthRiskCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HealthRiskService.instance,
      builder: (context, _) {
        final hr = HealthRiskService.instance;
        final result = hr.result;
        final hasData = result?.hasData ?? false;
        final level = result?.level ?? 'Insufficient';
        final confidence = result?.confidence ?? 0;
        final driver = result?.driver ?? 'N/A';
        final driverLabel = result?.driverLabel ?? '';
        final problem = result?.problem ?? '';
        final insight = result?.insight ?? '';
        final action = result?.action ?? '';
        final riskColor = result?.color ?? AppColors.mutedText;
        final lightColor = result?.lightColor ?? const Color(0xFFF8FAFC);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: hasData
                    ? riskColor.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasData
                    ? [
                        lightColor,
                        lightColor.withValues(alpha: 0.5),
                        Colors.white,
                      ]
                    : const [
                        Color(0xFFF8FAFC),
                        Color(0xFFF1F5F9),
                        Colors.white,
                      ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: hasData
                            ? riskColor.withValues(alpha: 0.15)
                            : AppColors.darkWith(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hasData
                            ? _iconForLevel(level)
                            : Icons.health_and_safety_outlined,
                        size: 20,
                        color: hasData ? riskColor : AppColors.mutedText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Health Risk Assessment',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkText,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'ML-based overall water-quality assessment',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.subtitleText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasData)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: riskColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          level,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (hr.loading)
                  const SizedBox(
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (!hasData)
                  const Text(
                    'Insufficient data.\nThe assessment will appear once enough sensor history is available.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedText,
                      height: 1.4,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _summaryTile(
                          label: 'Risk Level',
                          value: level,
                          color: riskColor,
                          icon: _iconForLevel(level),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryTile(
                          label: 'Confidence',
                          value: '$confidence%',
                          color: AppColors.primary,
                          icon: Icons.analytics_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.darkWith(0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow(
                          icon: Icons.monitor_heart_outlined,
                          label: 'Primary concern',
                          text: driverLabel.isNotEmpty ? driverLabel : driver,
                          color: riskColor,
                        ),
                        if (problem.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _detailRow(
                            icon: Icons.warning_amber_rounded,
                            label: 'Problem',
                            text: problem,
                            color: AppColors.warning,
                          ),
                        ],
                        if (insight.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _detailRow(
                            icon: Icons.lightbulb_outline_rounded,
                            label: 'Insight',
                            text: insight,
                            color: AppColors.primary,
                          ),
                        ],
                        if (action.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _detailRow(
                            icon: Icons.task_alt_rounded,
                            label: 'Recommended action',
                            text: action,
                            color: AppColors.success,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => showWqcHistorySheet(context),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('View assessment history'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.subtitleText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String text,
    required Color color,
  }) {
    return Row(
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
                  color: AppColors.subtitleText,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconForLevel(String level) {
    switch (level) {
      case 'Low':
        return Icons.check_circle_outline;
      case 'Moderate':
        return Icons.info_outline;
      case 'High':
        return Icons.warning_amber_outlined;
      case 'Critical':
        return Icons.gpp_bad_outlined;
      default:
        return Icons.help_outline;
    }
  }
}
