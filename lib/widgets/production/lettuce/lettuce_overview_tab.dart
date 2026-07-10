import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../services/lettuce_service.dart';
import '../../../utils/snackbar_helper.dart';
import 'lettuce_harvest_form_panel.dart';

class LettuceOverviewTab extends StatefulWidget {
  final VoidCallback? onShowMortalityModal;
  final VoidCallback? onShowEditModal;
  final VoidCallback? onShowLogsModal;
  final DateTime lastEdited;
  final bool isOwner;

  const LettuceOverviewTab({
    super.key,
    this.onShowMortalityModal,
    this.onShowEditModal,
    this.onShowLogsModal,
    required this.lastEdited,
    this.isOwner = true,
  });

  @override
  State<LettuceOverviewTab> createState() => _LettuceOverviewTabState();
}

class _LettuceOverviewTabState extends State<LettuceOverviewTab> {

  @override
  void initState() {
    super.initState();
    LettuceService.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    LettuceService.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
              LettuceHarvestFormPanel(
                isOwner: widget.isOwner,
                onSaved: () => showBeautifulSnackbar(context, 'Harvest recorded!', true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = LettuceService.instance;

    if (!service.isInitialized) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: _buildEmptyState(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          _buildCropHealthCard(context, service),
          const SizedBox(height: 8),
          _buildActionButtons(context),
          const SizedBox(height: 10),
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
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 32,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Lettuce Batch Active',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Initialize your lettuce batch to start tracking growth in your aquaponics system.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.dark.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildCropHealthCard(BuildContext context, LettuceService service) {
    final batch = service.selectedBatch!;
    final survivalPct = batch.initialQuantity > 0
        ? (batch.currentQuantity / batch.initialQuantity * 100)
        : 0.0;

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
                      'Crop Health',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.dark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Current monitoring status of your lettuce survival rates and growth parameters.',
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
              'Initial Lettuce Setup Data',
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
              _buildInfoChip(Icons.calendar_month_rounded, 'Planted', _formatDate(batch.plantingDate)),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.timelapse_rounded, 'Days', '${service.daysInCultivation}d'),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.eco_rounded, size: 18, color: AppColors.primary),
                    'Initial Planted', '${batch.initialQuantity}', 'Seedlings at start',
                    onTap: () => _showMetricDetail(context, 'Initial Planted', '${batch.initialQuantity}',
                        'Seedlings at start', Icons.eco_rounded,
                        'During batch initialization, ${batch.initialQuantity} lettuce seedlings were planted on ${_formatDate(batch.plantingDate)}. This serves as the baseline for all monitoring and survival rate calculations.'),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.straighten_rounded, size: 18, color: AppColors.primary),
                    'Initial Height', '${batch.initialTotalHeight.toStringAsFixed(1)} cm', 'Total height at start',
                    onTap: () => _showMetricDetail(context, 'Initial Height', '${batch.initialTotalHeight.toStringAsFixed(1)} cm',
                        'Total height at start', Icons.straighten_rounded,
                        'Total initial plant height of all seedlings measured during setup. This is the baseline for growth monitoring.'),
                  )),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.eco_rounded, size: 18, color: AppColors.primary),
                    'Initial Leaves', '${batch.initialTotalLeafCount}', 'Total leaves at start',
                    onTap: () => _showMetricDetail(context, 'Initial Leaves', '${batch.initialTotalLeafCount}',
                        'Total leaves at start', Icons.eco_rounded,
                        'Total initial leaf count of all seedlings measured during setup. This is the baseline for leaf development monitoring.'),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.eco_rounded, size: 18, color: AppColors.primary),
                    'In Tank', '${service.currentQuantity}', 'Plants in tank now',
                    onTap: () => _showMetricDetail(context, 'In Tank', '${service.currentQuantity}',
                        'Plants in tank now', Icons.favorite_rounded,
                        'Out of ${batch.initialQuantity} lettuce initially planted, ${service.currentQuantity} are still in the tank (${batch.totalMortality} lost, ${batch.harvestedQuantity} harvested). Survival rate: ${survivalPct.toStringAsFixed(1)}%.'),
                  )),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.critical),
                    'Plant Loss', '${batch.totalMortality}', 'Total lost plants',
                    onTap: () => _showMetricDetail(context, 'Plant Loss', '${batch.totalMortality}',
                        'Total lost plants', Icons.warning_rounded,
                        'Out of ${batch.initialQuantity} lettuce initially planted, ${batch.totalMortality} plants have been lost/died.'),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(
                    Icon(service.growthStage.icon, size: 18, color: service.growthStage.color),
                    'Growth Stage', service.growthStage.label, service.growthStage.range,
                    onTap: () => _showMetricDetail(context, 'Growth Stage', service.growthStage.label,
                        service.growthStage.range, service.growthStage.icon,
                        '${service.growthStage.description} Day ${service.daysInCultivation} of cultivation.'),
                  )),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.archive_outlined, size: 18, color: AppColors.primary),
                    'Harvested', '${batch.harvestedQuantity}', 'Total harvested plants',
                    onTap: () => _showMetricDetail(context, 'Harvested', '${batch.harvestedQuantity}',
                        'Total harvested plants', Icons.archive_outlined,
                        'Out of ${batch.initialQuantity} lettuce initially planted, ${batch.harvestedQuantity} have been harvested.'),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _buildMetricCard(
                    const Icon(Icons.monitor_weight_rounded, size: 18, color: AppColors.primary),
                    'Harvest Weight', batch.harvestWeightKg != null ? '${batch.harvestWeightKg!.toStringAsFixed(2)} kg' : '--',
                    'Total weight harvested',
                    onTap: () => _showMetricDetail(context, 'Harvest Weight', batch.harvestWeightKg != null ? '${batch.harvestWeightKg!.toStringAsFixed(2)} kg' : '--',
                        'Total weight harvested', Icons.monitor_weight_rounded,
                        batch.harvestWeightKg != null ? 'Total harvest weight: ${batch.harvestWeightKg!.toStringAsFixed(2)} kg.' : 'No harvest recorded yet.'),
                  )),
                ],
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
    IconData icon,
    String description,
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
                child: Icon(icon, size: 28, color: AppColors.primary),
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

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionBtn(
                'Log Plant Loss',
                widget.isOwner ? Icons.healing_rounded : Icons.lock_outline,
                widget.isOwner ? AppColors.critical : Colors.grey.shade400,
                widget.isOwner
                    ? (widget.onShowMortalityModal ?? () {})
                    : () {
                        showBeautifulSnackbar(context, 'Log Plant Loss is for owners only', false, title: 'Notice');
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                'Edit Setup',
                Icons.edit_rounded,
                AppColors.primary,
                widget.isOwner
                    ? (widget.onShowEditModal ?? () {})
                    : () {
                        showBeautifulSnackbar(context, 'Edit Setup is for owners only', false, title: 'Notice');
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionBtn(
                'View Logs',
                Icons.receipt_long_rounded,
                AppColors.warning,
                widget.onShowLogsModal ?? () {},
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
            widget.isOwner ? () => _showHarvestForm(context) : () {
              showBeautifulSnackbar(context, 'Record Harvest is for owners only', false, title: 'Notice');
            },
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
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
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
