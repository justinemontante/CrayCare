import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class ProductionPickerSheet extends StatelessWidget {
  final void Function(String mode) onSelected;

  const ProductionPickerSheet({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.darkWith(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          Text('Select Production Type',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 4),
          Text('Choose what you want to manage',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500,
              color: AppColors.darkWith(0.5),
            ),
          ),
          const SizedBox(height: 24),
          _buildCard(
            context,
            icon: Icons.water_drop_rounded,
            title: 'Crayfish',
            subtitle: 'Monitor tanks, track growth stages, manage harvest',
            color: AppColors.primary,
            lightColor: AppColors.primaryWith(0.08),
            onTap: () {
              Navigator.pop(context);
              onSelected('crayfish');
            },
          ),
          const SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.eco_rounded,
            title: 'Lettuce',
            subtitle: 'Track planting cycles, growth metrics, and harvest',
            color: AppColors.success,
            lightColor: AppColors.successWith(0.08),
            onTap: () {
              Navigator.pop(context);
              onSelected('lettuce');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color lightColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: lightColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: lightColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
