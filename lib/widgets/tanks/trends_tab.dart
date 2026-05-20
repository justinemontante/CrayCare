import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class TrendsTab extends StatelessWidget {
  const TrendsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Growth Trends',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Visualize growth and biomass trends over time.',
            style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.5)),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryWith(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryWith(0.15)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 40,
                    color: AppColors.primaryWith(0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Trends module coming soon',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
