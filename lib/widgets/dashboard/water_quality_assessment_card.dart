import 'package:flutter/material.dart';

import '../../services/water_quality_assessment_service.dart';
import '../../theme/app_colors.dart';
import 'water_quality_assessment_history_sheet.dart';

class WaterQualityAssessmentCard extends StatelessWidget {
  const WaterQualityAssessmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WaterQualityAssessmentService.instance,
      builder: (context, _) {
        final assessmentService = WaterQualityAssessmentService.instance;
        final result = assessmentService.result;
        final hasData = result?.hasData ?? false;
        final level = result?.level ?? 'Insufficient';
        final confidence = result?.confidence ?? 0;
        final driver = result?.driver ?? 'N/A';
        final driverLabel = result?.driverLabel ?? '';
        final problem = result?.problem ?? '';
        final insight = result?.insight ?? '';
        final action = result?.action ?? '';
        final conditionColor = result?.color ?? AppColors.mutedText;
        final lightColor = result?.lightColor ?? const Color(0xFFF8FAFC);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: hasData
                    ? conditionColor.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
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
                            ? conditionColor.withValues(alpha: 0.15)
                            : AppColors.darkWith(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hasData
                            ? _iconForLevel(level)
                            : Icons.health_and_safety_outlined,
                        size: 20,
                        color: hasData ? conditionColor : AppColors.mutedText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Water Quality Assessment',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkText,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Machine Learning-Based Water Quality Assessment',
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
                          color: conditionColor,
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
                if (assessmentService.loading)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: const LinearProgressIndicator(
                          minHeight: 4,
                          color: AppColors.primary,
                          backgroundColor: Color(0xFFE2EEEE),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Preparing the latest assessment...',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  )
                else if (!hasData)
                  const Text(
                    'Insufficient data.\nThe Water Quality Assessment will appear once enough sensor history is available.',
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
                          label: 'Condition',
                          value: level,
                          color: conditionColor,
                          icon: _iconForLevel(level),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryTile(
                          label: result!.safetyOverride
                              ? 'Assessment Basis'
                              : 'Confidence',
                          value: result.safetyOverride
                              ? result.assessmentBasis
                              : '$confidence%',
                          color: AppColors.primary,
                          icon: result.safetyOverride
                              ? Icons.health_and_safety_outlined
                              : Icons.analytics_outlined,
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
                          color: conditionColor,
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
                    onPressed: () =>
                        showWaterQualityAssessmentHistorySheet(context),
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('View Water Quality Assessment history'),
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
      case 'Good':
        return Icons.check_circle_outline;
      case 'Moderate':
        return Icons.info_outline;
      case 'Poor':
        return Icons.warning_amber_outlined;
      case 'Critical':
        return Icons.gpp_bad_outlined;
      default:
        return Icons.help_outline;
    }
  }
}
