import 'package:flutter/material.dart';
import '../../services/health_risk_service.dart';
import '../../theme/app_colors.dart';

class HealthRiskCard extends StatelessWidget {
  const HealthRiskCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HealthRiskService.instance,
      builder: (context, _) {
        final hr = HealthRiskService.instance;

        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: hr.hasData
                    ? hr.result!.color.withValues(alpha: 0.15)
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
                colors: hr.hasData
                    ? [
                        hr.result!.lightColor,
                        hr.result!.lightColor.withValues(alpha: 0.5),
                        Colors.white,
                      ]
                    : [
                        const Color(0xFFF8FAFC),
                        const Color(0xFFF1F5F9),
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
                        color: hr.hasData
                            ? hr.result!.color.withValues(alpha: 0.15)
                            : AppColors.darkWith(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hr.hasData
                            ? _iconForLevel(hr.result!.level)
                            : Icons.health_and_safety_outlined,
                        size: 20,
                        color: hr.hasData
                            ? hr.result!.color
                            : AppColors.mutedText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    if (hr.hasData)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: hr.result!.color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          hr.result!.level,
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
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (!hr.hasData)
                  const Text(
                    'Insufficient data.\nHealth Risk Score will appear once enough sensor readings are collected.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedText,
                      height: 1.4,
                    ),
                  )
                else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hr.result!.score.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: hr.result!.color,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '/ 100',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: hr.result!.color.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${hr.result!.confidence}% confidence',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: hr.result!.color.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Driver: ${hr.result!.driver}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.darkWith(0.06),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 16,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hr.result!.problem,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hr.result!.action,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.subtitleText,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Source: ${hr.result!.source}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.mutedText,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
