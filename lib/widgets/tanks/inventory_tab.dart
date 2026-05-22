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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          _buildSurvivalCard(),
          const SizedBox(height: 12),
          _buildWarningBanner(),
          const SizedBox(height: 12),
          _buildActionButtons(),
          const SizedBox(height: 12),
          _buildInfoCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Grow-Out Setup',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Initialize your grow-out to start tracking crayfish growth and survival.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onShowInitModal,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Initialize Setup',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
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
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Stocking Health',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Overall survival performance based on initial stocking data.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark.withValues(alpha: 0.5),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildDonutChart(survivalPct / 100, statusColor),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.dark.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _buildStatItem(
                  Icons.water_drop_rounded,
                  '${service.liveCount}',
                  'LIVE',
                ),
                _buildStatDivider(),
                _buildStatItem(
                  Icons.apps_rounded,
                  '${service.initialCount}',
                  'INITIAL',
                ),
                _buildStatDivider(),
                _buildStatItem(
                  Icons.warning_rounded,
                  '${service.mortality}',
                  'DEAD',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem(
                Icons.monitor_weight_rounded,
                '${service.initialWeight.toStringAsFixed(1)} g',
                'AVG WEIGHT',
              ),
              _buildStatDivider(),
              _buildStatItem(
                Icons.straighten_rounded,
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
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _DonutPainter(
          fraction: fraction,
          color: color,
          bgColor: color.withValues(alpha: 0.1),
        ),
        child: Center(
          child: Text(
            '${(fraction * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.5,
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
          Icon(icon, size: 16, color: AppColors.dark.withValues(alpha: 0.4)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: AppColors.dark.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.dark.withValues(alpha: 0.08),
    );
  }

  Widget _buildWarningBanner() {
    final survivalPct = TankService.instance.survivalRate;
    if (survivalPct >= 85) return const SizedBox.shrink();
    final isCritical = survivalPct < 70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isCritical
            ? AppColors.critical.withValues(alpha: 0.05)
            : AppColors.warning.withValues(alpha: 0.05),
        border: Border.all(
          color: isCritical
              ? AppColors.critical.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCritical ? Icons.error_rounded : Icons.warning_rounded,
            size: 18,
            color: isCritical ? AppColors.critical : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCritical
                      ? 'Critical Survival Level'
                      : 'Low Survival Warning',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isCritical
                        ? AppColors.critical
                        : AppColors.warningDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCritical
                      ? 'Survival dropped below 70%. Immediate water testing and action required.'
                      : 'Survival below 85%. Consider reviewing water quality parameters and feeding rates.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isCritical
                        ? AppColors.critical.withValues(alpha: 0.8)
                        : AppColors.warningDark.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
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
            Icons.healing_rounded,
            AppColors.critical,
            onShowMortalityModal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionBtn(
            'Edit Setup',
            Icons.edit_rounded,
            AppColors.primary,
            onShowEditModal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionBtn(
            'View Logs',
            Icons.receipt_long_rounded,
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: -0.2,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.calendar_month_rounded,
            'Stocking Date',
            '${stockingDate.month}/${stockingDate.day}/${stockingDate.year}',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _buildInfoRow(
            Icons.timelapse_rounded,
            'Days in Culture',
            '$days days',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _buildInfoRow(
            Icons.history_rounded,
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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.dark.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 14,
                color: AppColors.dark.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.dark.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
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
    const strokeWidth = 10.0; // Pinalaki ng konti ang stroke

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
