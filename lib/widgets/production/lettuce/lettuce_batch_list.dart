import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../services/lettuce_service.dart';
import '../../../models/lettuce_batch.dart';
import 'past_lettuce_batch_details_modal.dart';

class LettuceBatchList extends StatelessWidget {
  final VoidCallback onNewBatch;
  final bool isOwner;

  const LettuceBatchList({super.key, required this.onNewBatch, this.isOwner = true});

  @override
  Widget build(BuildContext context) {
    final service = LettuceService.instance;
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
          if (activeBatches.isNotEmpty) ...activeBatches.map((b) => _buildBatchCard(context, service, b, true)),
          if (pastBatches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
              child: Column(children: [
                Container(height: 1, color: AppColors.darkWith(0.06)),
                const SizedBox(height: 8),
                Text('Archived Batches', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.darkWith(0.4))),
              ]),
            ),
            ...pastBatches.map((b) => _buildBatchCard(context, service, b, false)),
          ],
          if (activeBatches.isEmpty && pastBatches.isEmpty) _buildEmptyState(context),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<LettuceBatch> active, List<LettuceBatch> past) {
    final total = active.length + past.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.eco_rounded, size: 16, color: AppColors.success),
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

  Widget _buildBatchCard(BuildContext context, LettuceService service, LettuceBatch batch, bool isActive) {
    final isLatestActive = isActive && service.activeBatches.isNotEmpty &&
        batch.batchId == service.activeBatches.first.batchId;
    final bid = batch.batchId;
    final isSelected = service.selectedBatchId == batch.batchId;
    final duration = isActive
        ? DateTime.now().difference(batch.plantingDate).inDays
        : (batch.harvestDate != null ? batch.harvestDate!.difference(batch.plantingDate).inDays : 0);
    final iconColor = isLatestActive ? AppColors.success : AppColors.darkWith(0.35);

    final logs = service.getGrowthLogsForBatch(batch.batchId);
    final avgHeight = logs.isNotEmpty
        ? logs.map((l) => l.plantHeightCm ?? l.avgLeafSize ?? 0.0).reduce((a, b) => a + b) / logs.length
        : 0.0;
    final survivalPct = batch.initialQuantity > 0
        ? (isActive ? batch.currentQuantity : batch.harvestedQuantity) / batch.initialQuantity * 100
        : 0.0;
    Color statusColor = isLatestActive ? AppColors.success : AppColors.darkWith(0.6);
    if (survivalPct < 70) {
      statusColor = AppColors.critical;
    } else if (survivalPct < 85 && isLatestActive) {
      statusColor = AppColors.warning;
    }

    return GestureDetector(
      onTap: () => isActive ? service.selectBatch(batch.batchId) : showPastLettuceBatchDetailsModal(context, batch),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [AppColors.success.withValues(alpha: 0.1), AppColors.success.withValues(alpha: 0.02)]
                : isLatestActive
                    ? [AppColors.success.withValues(alpha: 0.05), AppColors.success.withValues(alpha: 0.02)]
                    : [AppColors.darkWith(0.03), AppColors.darkWith(0.01)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1.5)
              : (isLatestActive ? null : Border.all(color: AppColors.darkWith(0.1), width: 1)),
        ),
        child: Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
              child: Icon(isLatestActive ? Icons.play_arrow_rounded : Icons.archive_rounded, size: 10, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bid, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark)),
              if (isLatestActive)
                Text(_formatShortDate(batch.plantingDate), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4)))
              else
                Text(
                  '${_formatShortDate(batch.plantingDate)} \u2192 ${batch.harvestDate != null ? _formatShortDate(batch.harvestDate!) : 'N/A'} \u2022 ${duration}d',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4)),
                ),
            ])),
            Text('${duration}d', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isSelected ? AppColors.success : (isLatestActive ? AppColors.dark : AppColors.darkWith(0.5)))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _miniStat('Initial', '${batch.initialQuantity}', isLatestActive ? AppColors.success : AppColors.darkWith(0.6)),
            if (isLatestActive) ...[
              _miniStat('Avg Height', '${avgHeight.toStringAsFixed(1)} cm', AppColors.primary),
              _miniStat('Survival', '${survivalPct.toStringAsFixed(0)}%', statusColor),
            ] else ...[
              _miniStat('Harvested', '${batch.harvestedQuantity}', statusColor),
              _miniStat('Survival', '${survivalPct.toStringAsFixed(0)}%', statusColor),
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

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 1),
        Text(label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.45))),
      ]),
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
          Text('Initialize lettuce seeds to start', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.25))),
          if (isOwner) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onNewBatch,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Initialize Seedlings', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success, foregroundColor: Colors.white, elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _formatShortDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
