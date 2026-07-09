import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';

class BatchSelector extends StatelessWidget {
  final String? selectedBatchId;
  final List<BatchSelectorItem> batches;
  final ValueChanged<String> onSelect;
  final String label;

  const BatchSelector({
    super.key,
    required this.selectedBatchId,
    required this.batches,
    required this.onSelect,
    this.label = 'Batch',
  });

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkWith(0.1), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.layers_rounded, size: 14, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => _showPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryWith(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        selectedBatchId ?? 'Select batch',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down_rounded, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.darkWith(0.15), borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                Text('Select Batch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                const SizedBox(height: 12),
                ...batches.map((b) {
                  final isSelected = b.id == selectedBatchId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: isSelected ? AppColors.primaryWith(0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          onSelect(b.id);
                          Navigator.pop(ctx);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: b.isActive ? AppColors.success : AppColors.darkWith(0.3),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(b.id, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
                              ),
                              if (b.subtitle != null)
                                Text(b.subtitle!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.darkWith(0.4))),
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BatchSelectorItem {
  final String id;
  final bool isActive;
  final String? subtitle;

  const BatchSelectorItem({required this.id, required this.isActive, this.subtitle});
}
