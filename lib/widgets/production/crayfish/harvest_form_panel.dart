import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../models/crayfish_batch.dart';
import '../../../utils/snackbar_helper.dart';

class CrayfishHarvestFormPanel extends StatefulWidget {
  final VoidCallback? onSaved;
  const CrayfishHarvestFormPanel({super.key, this.onSaved});

  @override
  State<CrayfishHarvestFormPanel> createState() => _CrayfishHarvestFormPanelState();
}

class _CrayfishHarvestFormPanelState extends State<CrayfishHarvestFormPanel> {
  DateTime _selectedDate = DateTime.now();
  final _countCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  @override
  void dispose() {
    _countCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _handleSave() {
    final service = TankService.instance;
    final count = int.tryParse(_countCtrl.text);
    final weight = double.tryParse(_weightCtrl.text);
    if (count == null || count <= 0) {
      showBeautifulSnackbar(context, 'Enter a valid harvest count.', false);
      return;
    }
    if (weight == null || weight <= 0) {
      showBeautifulSnackbar(context, 'Enter total harvest weight.', false);
      return;
    }
    if (count > service.inTankCount) {
      showBeautifulSnackbar(context, 'Harvest count exceeds in-tank population (${service.inTankCount}).', false);
      return;
    }
    service.addHarvestRecord(harvestedCount: count, totalWeightKg: weight);
    widget.onSaved?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final abwGrams = (double.tryParse(_weightCtrl.text) ?? 0) > 0 && (int.tryParse(_countCtrl.text) ?? 0) > 0
        ? ((double.tryParse(_weightCtrl.text)! * 1000) / int.tryParse(_countCtrl.text)!)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.archive_rounded, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              const Text('Record Harvest', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const Spacer(),
              GestureDetector(
                onTap: _showHistoryModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 12, color: AppColors.dark.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text('History', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.dark.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.dark.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Text(
                    'Harvest Date: ${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildInputField('Crayfish Harvested', 'Number of crayfish', _countCtrl),
          _buildHarvestWarning(),
          const SizedBox(height: 12),
          _buildInputField('Total Harvest Weight (kg)', 'e.g. 2.5', _weightCtrl),
          if (abwGrams > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.monitor_weight_outlined, size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'ABW: ${abwGrams.toStringAsFixed(1)} g',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Survival: ${service.survivalRate.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _handleSave,
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save Harvest', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarvestWarning() {
    final count = int.tryParse(_countCtrl.text) ?? 0;
    final inTank = TankService.instance.inTankCount;
    if (count <= 0 || count <= inTank) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 12, color: AppColors.critical),
          const SizedBox(width: 4),
          Text(
            'Only $inTank available in tank',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.critical),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, String hint, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.dark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.dark.withValues(alpha: 0.3), fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.dark.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.dark.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  void _showHistoryModal() {
    final service = TankService.instance;
    final records = service.harvestRecords;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.dark.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.archive_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Harvest Records', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  const Spacer(),
                  Text('${records.length} recorded', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.5))),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 40, color: AppColors.dark.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text('No harvest records yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: records.map((r) => _buildRecordCard(r)).toList(),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(CrayfishHarvestRecord r) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[r.date.month - 1]} ${r.date.day}, ${r.date.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkWith(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.archive_rounded, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  const SizedBox(height: 4),
                  Text('${r.harvestedCount} pcs | ${r.totalWeightKg.toStringAsFixed(2)}kg | ABW: ${r.abwGrams.toStringAsFixed(1)}g',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.dark.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
