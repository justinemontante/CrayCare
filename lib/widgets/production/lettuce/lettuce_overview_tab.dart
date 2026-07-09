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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
            children: [
              Expanded(
                flex: 4,
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 85,
                        height: 85,
                        child: CircularProgressIndicator(
                          value: survivalPct / 100,
                          strokeWidth: 8,
                          backgroundColor: AppColors.darkWith(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${survivalPct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: statusColor,
                            ),
                          ),
                          Text(
                            'Survival',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkWith(0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    _buildOverviewStatRow(Icons.pin_outlined, 'Initial', '${batch.initialQuantity} pcs'),
                    const SizedBox(height: 8),
                    _buildOverviewStatRow(Icons.timelapse_rounded, 'Days Growing', '${service.daysInCultivation}d'),
                    const SizedBox(height: 8),
                    _buildOverviewStatRow(Icons.eco_rounded, 'In Tank', '${service.currentQuantity}'),
                    const SizedBox(height: 8),
                    _buildOverviewStatRow(Icons.warning_amber_rounded, 'Plant Loss', '${batch.totalMortality}', valueColor: AppColors.critical),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStatRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.darkWith(0.5)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.dark,
          ),
        ),
      ],
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

}
