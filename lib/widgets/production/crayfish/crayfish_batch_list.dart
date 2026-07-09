import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../models/crayfish_batch.dart';

class CrayfishBatchList extends StatelessWidget {
  final VoidCallback onNewBatch;

  const CrayfishBatchList({super.key, required this.onNewBatch});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final activeBatches = service.activeBatches;
    final pastBatches = service.harvestHistory;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.darkWith(0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader(context, activeBatches, pastBatches),
          if (activeBatches.isNotEmpty) ...activeBatches.map((b) => _buildActiveBatchCard(context, service, b)),
          if (pastBatches.isNotEmpty) _buildPastBatchesList(context, pastBatches),
          if (activeBatches.isEmpty && pastBatches.isEmpty) _buildEmptyState(context),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<CrayfishBatch> active, List<CrayfishBatch> past) {
    final total = active.length + past.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: AppColors.primaryWith(0.12), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.layers_rounded, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('All Batches', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark)),
            Text(
              active.isNotEmpty ? '${active.length} active, $total total' : '$total archived',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4)),
            ),
          ]),
        ),
        GestureDetector(
          onTap: onNewBatch,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_circle_outline_rounded, size: 12, color: AppColors.success),
              SizedBox(width: 4),
              Text('New Batch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildActiveBatchCard(BuildContext context, TankService service, CrayfishBatch batch) {
    final isActive = true;
    return _buildBatchCard(context, batch, isActive);
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.45))),
      ]),
    );
  }

  Widget _buildPastBatchesList(BuildContext context, List<CrayfishBatch> batches) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 1, color: AppColors.darkWith(0.06)),
        const SizedBox(height: 8),
        Text('Archived Batches', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.4))),
        const SizedBox(height: 4),
        ...batches.map((b) => _buildBatchCard(context, b, false)),
      ]),
    );
  }

  Widget _buildBatchCard(BuildContext context, CrayfishBatch batch, bool isActive) {
    final service = TankService.instance;
    final isSelected = service.selectedBatchId == batch.batchId;
    final survivalPct = batch.initialCount > 0
        ? ((batch.initialCount - batch.totalMortality) / batch.initialCount * 100)
        : 0.0;
    final duration = isActive
        ? DateTime.now().difference(batch.stockingDate).inDays
        : batch.daysInCulture;
    final iconColor = isActive ? AppColors.success : AppColors.darkWith(0.35);
    Color statusColor = isActive ? AppColors.success : AppColors.darkWith(0.6);
    if (survivalPct < 70) statusColor = AppColors.critical;
    else if (survivalPct < 85 && isActive) statusColor = AppColors.warning;

    return GestureDetector(
      onTap: () => service.selectBatch(batch.batchId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [AppColors.primary.withValues(alpha: 0.08), AppColors.primary.withValues(alpha: 0.02)]
                : isActive
                    ? [AppColors.success.withValues(alpha: 0.05), AppColors.success.withValues(alpha: 0.02)]
                    : [AppColors.darkWith(0.03), AppColors.darkWith(0.01)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5)
              : (isActive ? null : Border.all(color: AppColors.darkWith(0.1), width: 1)),
        ),
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
              child: Icon(isActive ? Icons.play_arrow_rounded : Icons.archive_rounded, size: 10, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(batch.batchId, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark)),
              if (isActive)
                Text(_formatShortDate(batch.stockingDate), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4)))
              else
                Text(
                  '${_formatShortDate(batch.stockingDate)} \u2192 ${batch.harvestDate != null ? _formatShortDate(batch.harvestDate!) : 'N/A'} \u2022 ${batch.daysInCulture}d',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4)),
                ),
            ])),
            Text('${duration}d', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? AppColors.primary : (isActive ? AppColors.dark : AppColors.darkWith(0.5)))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _miniStat('Initial', '${batch.initialCount}', statusColor),
            if (isActive) ...[
              _miniStat('Survival', '${survivalPct.toStringAsFixed(0)}%', statusColor),
              _miniStat('ABW', '${batch.initialAbw.toStringAsFixed(1)}g', AppColors.primary),
              _miniStat('ABL', '${batch.initialAbl.toStringAsFixed(1)}cm', AppColors.primary),
            ] else ...[
              _miniStat('Harvested', '${batch.harvestCount}', statusColor),
              _miniStat('Survival', '${survivalPct.toStringAsFixed(0)}%', statusColor),
              _miniStat('Final ABW', '${batch.finalAbw.toStringAsFixed(1)}g', statusColor),
            ],
          ]),
          if (!isSelected) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Tap to view', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.3))),
                Icon(Icons.chevron_right_rounded, size: 10, color: AppColors.darkWith(0.3)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      child: Center(
        child: Column(children: [
          Icon(Icons.inbox_rounded, size: 28, color: AppColors.darkWith(0.15)),
          const SizedBox(height: 6),
          Text('No batches yet', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.35))),
          const SizedBox(height: 2),
          Text('Initialize a grow-out to start', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.25))),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onNewBatch,
            icon: const Icon(Icons.add_rounded, size: 14),
            label: const Text('Initialize Grow-Out', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary, foregroundColor: Colors.white, elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
      ),
    );
  }

  String _formatShortDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
