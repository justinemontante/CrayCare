import 'package:flutter/material.dart';

import '../../services/water_quality_anomaly_detection_service.dart';
import '../../theme/app_colors.dart';
import 'water_quality_anomaly_detection_history_sheet.dart';

class WaterQualityAnomalyDetectionCard extends StatelessWidget {
  const WaterQualityAnomalyDetectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WaterQualityAnomalyDetectionService.instance,
      builder: (context, _) {
        final service = WaterQualityAnomalyDetectionService.instance;
        final result = service.result;
        final hasData = result?.hasData ?? false;
        final color = result?.color ?? AppColors.mutedText;
        final lightColor = result?.lightColor ?? const Color(0xFFF8FAFC);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
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
                    child: Icon(
                      result?.isAnomaly == true
                          ? Icons.travel_explore_rounded
                          : Icons.hub_outlined,
                      size: 20,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Water Quality Anomaly Detection',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cray AI · Unsupervised machine learning',
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
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        result!.status,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (service.loading)
                const _LoadingState()
              else if (!hasData)
                Text(
                  result?.insight ??
                      'Collecting two hours of continuous sensor history before anomaly detection begins.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: AppColors.mutedText,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        label: 'Pattern status',
                        value: result!.status,
                        icon: result.isAnomaly
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricTile(
                        label: 'Anomaly score',
                        value: '${result.anomalyScore.toStringAsFixed(1)}/100',
                        icon: Icons.analytics_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: lightColor.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow(
                        icon: Icons.multiline_chart_rounded,
                        label: 'Main pattern contributor',
                        text: result.driverLabel,
                        color: color,
                      ),
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.lightbulb_outline_rounded,
                        label: 'Insight',
                        text: result.insight,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.fact_check_outlined,
                        label: 'Suggested action',
                        text: result.recommendation,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ),
                if (result.usesPrototypeData) ...[
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.science_outlined, size: 14, color: AppColors.warning),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Prototype model · Retrain with real Cherax RAS history before field validation.',
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.35,
                            color: AppColors.subtitleText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      showWaterQualityAnomalyDetectionHistorySheet(context),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('View anomaly history'),
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
        );
      },
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

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.13)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
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
