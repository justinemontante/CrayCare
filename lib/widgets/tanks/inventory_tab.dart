import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';

class InventoryTab extends StatelessWidget {
  final VoidCallback onShowInitModal;
  final VoidCallback onShowMortalityModal;
  final VoidCallback onShowEditModal;
  final VoidCallback onShowLogsModal;
  final bool hasSetup;
  final DateTime lastEdited;

  const InventoryTab({
    super.key,
    required this.onShowInitModal,
    required this.onShowMortalityModal,
    required this.onShowEditModal,
    required this.onShowLogsModal,
    required this.hasSetup,
    required this.lastEdited,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasSetup) return _buildEmptyState();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildSurvivalCard(),
          const SizedBox(height: 10),
          _buildWarningBanner(),
          const SizedBox(height: 10),
          _buildActionButtons(),
          const SizedBox(height: 10),
          _buildInfoCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.darkWith(0.15),
            ),
            const SizedBox(height: 16),
            Text(
              'No Grow-Out Setup Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.darkWith(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize your grow-out to start tracking crayfish growth and survival.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.4)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onShowInitModal,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Initialize Grow-Out Setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurvivalCard() {
    final service = TankService.instance;
    final survivalPct = service.survivalRate;

    Color statusColor = AppColors.success;
    if (survivalPct < 70) {
      statusColor = AppColors.critical;
    } else if (survivalPct < 85) {
      statusColor = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkWith(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SURVIVAL RATE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Stocking Health',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Overall survival performance based on initial stocking data.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildDonutChart(survivalPct / 100, statusColor),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildStatItem(Icons.numbers, '${service.liveCount}', 'LIVE'),
              _buildStatDivider(),
              _buildStatItem(
                Icons.pie_chart_outline,
                '${service.initialCount}',
                'INITIAL',
              ),
              _buildStatDivider(),
              _buildStatItem(
                Icons.favorite_border,
                '${service.mortality}',
                'MORTALITY',
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatItem(
                Icons.monitor_weight_outlined,
                '${service.initialWeight.toStringAsFixed(1)} g',
                'AVG WEIGHT',
              ),
              _buildStatDivider(),
              _buildStatItem(
                Icons.straighten_outlined,
                '${service.initialLength.toStringAsFixed(1)} cm',
                'AVG LENGTH',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChart(double fraction, Color color) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _DonutPainter(
          fraction: fraction,
          color: color,
          bgColor: color.withValues(alpha: 0.12),
        ),
        child: Center(
          child: Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: AppColors.darkWith(0.5),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 36, color: AppColors.darkWith(0.08));
  }

  Widget _buildWarningBanner() {
    final survivalPct = TankService.instance.survivalRate;
    if (survivalPct >= 85) return const SizedBox.shrink();
    final isCritical = survivalPct < 70;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical
            ? AppColors.criticalWith(0.1)
            : AppColors.warningWith(0.1),
        border: Border.all(
          color: isCritical
              ? AppColors.criticalWith(0.25)
              : AppColors.warningWith(0.25),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.warning : Icons.info_outline,
            size: 16,
            color: isCritical ? AppColors.critical : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isCritical
                  ? 'Critical: Survival dropped below 70%. Immediate action required.'
                  : 'Warning: Survival below 85%. Consider reviewing water quality and feeding.',
              style: TextStyle(
                fontSize: 11,
                color: isCritical ? AppColors.critical : AppColors.warningDark,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionBtn(
            'Log Mortality',
            Icons.warning_rounded,
            AppColors.critical,
            onShowMortalityModal,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionBtn(
            'Edit Setup',
            Icons.edit_outlined,
            AppColors.primary,
            onShowEditModal,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionBtn(
            'View Logs',
            Icons.menu_book,
            AppColors.warning,
            onShowLogsModal,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final service = TankService.instance;
    final stockingDate = service.stockingDate;
    final days = service.daysInCulture;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.08)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.calendar_today,
            'Stocking Date',
            '${stockingDate.month}/${stockingDate.day}/${stockingDate.year}',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.hourglass_bottom,
            'Days in Culture',
            '$days days',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            Icons.history,
            'Last Edited',
            '${lastEdited.month}/${lastEdited.day}/${lastEdited.year}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.7)),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.dark,
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color bgColor;

  _DonutPainter({
    required this.fraction,
    required this.color,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);
    const strokeWidth = 8.0;

    final bgPaint = Paint()
      ..color = bgColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      -pi / 2,
      2 * pi * fraction,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}
