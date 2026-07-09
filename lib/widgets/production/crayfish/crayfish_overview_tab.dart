import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'harvest_form_panel.dart';

class OverviewTab extends StatelessWidget {
  final VoidCallback onShowInitModal;
  final VoidCallback onShowMortalityModal;
  final VoidCallback onShowEditModal;
  final VoidCallback onShowLogsModal;
  final VoidCallback onShowCompleteBatchModal;
  final bool hasSetup;
  final DateTime lastEdited;

  final bool isOwner;

  const OverviewTab({
    super.key,
    required this.onShowInitModal,
    required this.onShowMortalityModal,
    required this.onShowEditModal,
    required this.onShowLogsModal,
    required this.onShowCompleteBatchModal,
    required this.hasSetup,
    required this.lastEdited,
    this.isOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          if (!TankService.instance.isInitialized)
            _buildEmptyState()
          else ...[
            _buildSurvivalCard(context),
            const SizedBox(height: 8),
            _buildWarningBanner(),
            const SizedBox(height: 8),
            _buildActionButtons(context),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Records Found',
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
            onPressed: isOwner ? onShowInitModal : null,
            icon: Icon(isOwner ? Icons.add_rounded : Icons.lock_outline, size: 18),
            label: Text(
              isOwner ? 'Initialize Inventory' : 'Initialize Inventory (Owner Only)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOwner ? AppColors.primary : Colors.grey.shade300,
              foregroundColor: isOwner ? Colors.white : Colors.grey.shade500,
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSurvivalCard(BuildContext context) {
    final service = TankService.instance;
    final survivalPct = service.survivalRate;

    Color statusColor = AppColors.success;
    if (survivalPct < 70) {
      statusColor = AppColors.critical;
    } else if (survivalPct < 85) {
      statusColor = AppColors.warning;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    const Text(
                      'Stocking Health',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current monitoring status of your survival rates and growth parameters.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.dark.withValues(alpha: 0.6),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDonutChart(survivalPct / 100, statusColor),
                  const SizedBox(height: 6),
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
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Initial Tank Setup Data',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildInfoChip(Icons.calendar_month_rounded, 'Stocked', _formatDate(service.stockingDate)),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.timelapse_rounded, 'Days', '${service.daysInCulture}d'),
            ],
          ),
          const SizedBox(height: 12),
          // 3 rows x 2 columns
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/InitialPopulation.png', width: 20, height: 20), 'Initial Population', '${service.initialCount}', 'Total stock at start', onTap: () => _showMetricDetail(context, 'Initial Population', service.initialCount.toString(), 'Total stock at start', 'assets/images/InitialPopulation.png', 'During grow-out initialization, ${service.initialCount} crayfish were placed in the tank on ${_formatDate(service.stockingDate)}. This serves as the baseline for all monitoring and survival rate calculations.', Icons.people_alt_rounded))),

                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/SampleCount.png', width: 20, height: 20), 'Sample Size', '${service.sampleCount}', 'Crayfish in sample', onTap: () => _showMetricDetail(context, 'Sample Size', service.sampleCount.toString(), 'Crayfish in sample', 'assets/images/SampleCount.png', 'During initialization, ${service.sampleCount} crayfish were taken and measured to determine the average weight and length per crayfish. This sample represents the entire population.', Icons.analytics_rounded))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/TotalWeight.png', width: 20, height: 20), 'Initial Total Sample Weight', '${service.initialTotalWeight.toStringAsFixed(0)} g', 'ABW: ${service.initialWeight.toStringAsFixed(1)} g', onTap: () => _showMetricDetail(context, 'Initial Total Sample Weight', '${service.initialTotalWeight.toStringAsFixed(0)} g', 'Average Body Weight (ABW): ${service.initialWeight.toStringAsFixed(1)} g', 'assets/images/TotalWeight.png', 'Total weight of ${service.sampleCount} samples taken during initialization. Average Body Weight (ABW): ${service.initialWeight.toStringAsFixed(1)} g. This is the baseline for growth monitoring.', Icons.monitor_weight_rounded))),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/TotalLength.png', width: 20, height: 20), 'Initial Total Sample Length', '${service.initialTotalLength.toStringAsFixed(0)} cm', 'ABL: ${service.initialLength.toStringAsFixed(1)} cm', onTap: () => _showMetricDetail(context, 'Initial Total Sample Length', '${service.initialTotalLength.toStringAsFixed(0)} cm', 'Average Body Length (ABL): ${service.initialLength.toStringAsFixed(1)} cm', 'assets/images/TotalLength.png', 'Total length of ${service.sampleCount} samples taken during initialization. Average Body Length (ABL): ${service.initialLength.toStringAsFixed(1)} cm. This is the baseline for growth monitoring.', Icons.straighten_rounded))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/Alive.png', width: 20, height: 20), 'In Tank', '${service.inTankCount}', 'In tank now', onTap: () => _showMetricDetail(context, 'In Tank', service.inTankCount.toString(), 'In tank now', 'assets/images/Alive.png', 'Out of ${service.initialCount} crayfish initially stocked, ${service.inTankCount} are still in the tank (${service.mortality} died, ${service.totalHarvested} harvested). Survival rate (mortality only): ${service.survivalRate.toStringAsFixed(1)}%.', Icons.favorite_rounded))),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(Image.asset('assets/images/Mortality.png', width: 20, height: 20), 'Mortality', '${service.mortality}', 'Total deaths', onTap: () => _showMetricDetail(context, 'Mortality', service.mortality.toString(), 'Total deaths', 'assets/images/Mortality.png', 'Out of ${service.initialCount} crayfish initially stocked, ${service.mortality} have died. Survival rate: ${service.survivalRate.toStringAsFixed(1)}%.', Icons.warning_rounded))),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.45,
                  child: _buildMetricCard(const Icon(Icons.archive_outlined, size: 18, color: AppColors.primary), 'Harvested', '${service.totalHarvested}', 'Total harvested', onTap: () => _showMetricDetail(context, 'Harvested', service.totalHarvested.toString(), 'Total harvested', 'assets/images/Alive.png', 'Out of ${service.initialCount} crayfish initially stocked, ${service.totalHarvested} have been harvested.', Icons.archive_outlined)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMetricDetail(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    String iconPath,
    String description,
    IconData fallbackIcon,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(iconPath, width: 28, height: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    Widget iconWidget,
    String title,
    String value,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: iconWidget,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.45),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildDonutChart(double fraction, Color color) {
    return SizedBox(
      width: 80,
      height: 80,
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
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    final survivalPct = TankService.instance.survivalRate;
    if (survivalPct >= 85) return const SizedBox.shrink();
    final isCritical = survivalPct < 70;

    final warningTextColor = AppColors.warning;

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
                    color: isCritical ? AppColors.critical : warningTextColor,
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
                        : warningTextColor.withValues(alpha: 0.8),
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

  Widget _buildActionButtons(BuildContext context) {
    final canEditSetup = isOwner && TankService.instance.samplingHistory.isEmpty;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                'Log Mortality',
                isOwner ? Icons.healing_rounded : Icons.lock_outline,
                isOwner ? AppColors.critical : Colors.grey.shade400,
                isOwner ? onShowMortalityModal : () {
                  showBeautifulSnackbar(context, 'Log Mortality is for owners only', false, title: 'Notice');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                'Edit Setup',
                canEditSetup ? Icons.edit_rounded : Icons.lock_outline,
                canEditSetup ? AppColors.primary : Colors.grey.shade400,
                canEditSetup ? onShowEditModal : () {
                  if (!isOwner) {
                    showBeautifulSnackbar(context, 'Edit Setup is for owners only', false, title: 'Notice');
                  } else {
                    showBeautifulSnackbar(context, 'Cannot edit after first sampling', false, title: 'Notice');
                  }
                },
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
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _buildActionBtn(
            'Record Harvest',
            Icons.archive_outlined,
            AppColors.success,
            isOwner ? () => _showHarvestForm(context) : () {
              showBeautifulSnackbar(context, 'Record Harvest is for owners only', false, title: 'Notice');
            },
          ),
        ),
      ],
    );
  }

  void _showHarvestForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.darkWith(0.15), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 8),
              CrayfishHarvestFormPanel(
                isOwner: isOwner,
                onSaved: () => showBeautifulSnackbar(context, 'Harvest recorded!', true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryWith(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryWith(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.dark)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatShortDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
    const strokeWidth = 10.0;

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
