import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/dashboard/health_risk_card.dart';

class AiInsightsScreen extends StatelessWidget {
  const AiInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 24,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Insights',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'CrayCare CSI Health Risk Assessment',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SectionLabelInline(
                label: 'Cumulative Stress Index',
                icon: Icons.health_and_safety_outlined,
              ),
            ),
            const SizedBox(height: 8),
            const HealthRiskCard(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SectionLabelInline(
                label: 'About CSI',
                icon: Icons.info_outline,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.darkWith(0.06),
                  ),
                ),
                child: const Text(
                  'The Cumulative Stress Index (CSI) is an XGBoost ML-driven health risk score (0\u2013100) that evaluates real-time water quality parameters including temperature, pH, dissolved oxygen, and turbidity to predict stress levels in your crayfish population.\n\n'
                  'Recommendations are grounded in peer-reviewed aquaculture research and tailored to each risk level.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.subtitleText,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionLabelInline extends StatelessWidget {
  final String label;
  final IconData icon;

  const SectionLabelInline({
    super.key,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.dark,
            ),
          ),
        ],
      ),
    );
  }
}
