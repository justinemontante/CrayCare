import 'package:flutter/material.dart';

import '../../../services/report_export_service.dart';
import '../../../services/tank_service.dart';
import '../../../theme/app_colors.dart';

class _ReportExportSelection {
  final Set<String> batchIds;
  final GrowOutReportSections sections;
  final bool includeSummary;
  final String fileName;

  const _ReportExportSelection({
    required this.batchIds,
    required this.sections,
    required this.includeSummary,
    required this.fileName,
  });
}

/// Opens the export flow from screens that use a simple tap action, such as
/// the Dashboard Quick Actions list.
Future<void> showGrowOutReportExport(BuildContext context) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.darkWith(0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Export Reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose the file format, then select the batches and records to include.',
              style: TextStyle(fontSize: 12, color: AppColors.darkWith(0.55)),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.grid_on_rounded,
                color: AppColors.primary,
              ),
              title: const Text('Export Excel'),
              subtitle: const Text('Organized into separate report sheets.'),
              onTap: () => Navigator.pop(sheetContext, 'xlsx'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.picture_as_pdf_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Export PDF'),
              subtitle: const Text('Best for viewing or printing reports.'),
              onTap: () => Navigator.pop(sheetContext, 'pdf'),
            ),
          ],
        ),
      ),
    ),
  );
  if (format == null || !context.mounted) return;
  await const GrowOutReportExportButton()._export(context, format);
}

/// Opens the all-batch export flow from the Batch List.
class GrowOutReportExportButton extends StatelessWidget {
  final bool expand;
  final String label;

  const GrowOutReportExportButton({
    super.key,
    this.expand = false,
    this.label = 'Export Reports',
  });

  Future<_ReportExportSelection?> _chooseReportContent(
    BuildContext context,
  ) async {
    final batches = List.of(TankService.instance.batches)
      ..sort((a, b) {
        final dateOrder = a.stockingDate.compareTo(b.stockingDate);
        return dateOrder != 0 ? dateOrder : a.batchId.compareTo(b.batchId);
      });
    final selectedBatchIds = batches.map((batch) => batch.batchId).toSet();
    var includeSampling = true;
    var includeMortality = true;
    var includeHarvest = true;
    var includeSummary = true;
    var fileName = 'craycare_all_batches';

    final result = await showModalBottomSheet<_ReportExportSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final hasSelectedBatch = selectedBatchIds.isNotEmpty;
          final hasReportContent =
              includeSummary ||
              includeSampling ||
              includeMortality ||
              includeHarvest;
          final allSelected = selectedBatchIds.length == batches.length;
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.84,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10),
                      height: 5,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppColors.darkWith(0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primaryWith(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.ios_share_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose Report Content',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.dark,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Select batches and detailed records to include.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0x80505A68),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.darkWith(0.5),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                      children: [
                        Text(
                          'Select the batches and records to include in your report.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppColors.darkWith(0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: fileName,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (value) => fileName = value,
                          decoration: InputDecoration(
                            labelText: 'Report File Name (Editable)',
                            hintText: 'Example: September Grow-Out Report',
                            helperText:
                                'Tap to rename. A date-time stamp and the .xlsx or .pdf extension are added automatically.',
                            prefixIcon: const Icon(Icons.edit_document),
                            suffixIcon: const Icon(Icons.edit_outlined),
                            filled: true,
                            fillColor: AppColors.primaryWith(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: includeSummary,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Include Batch Summary',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Recommended for a complete report.',
                          ),
                          onChanged: (value) => setSheetState(
                            () => includeSummary = value ?? false,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Batches',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),
                        CheckboxListTile(
                          value: allSelected,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'All Batches',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onChanged: (value) => setSheetState(() {
                            if (value ?? false) {
                              selectedBatchIds
                                ..clear()
                                ..addAll(batches.map((batch) => batch.batchId));
                            } else {
                              selectedBatchIds.clear();
                            }
                          }),
                        ),
                        ...batches.map(
                          (batch) => CheckboxListTile(
                            value: selectedBatchIds.contains(batch.batchId),
                            contentPadding: const EdgeInsets.only(left: 16),
                            dense: true,
                            title: Text(batch.batchId),
                            subtitle: Text(
                              '${batch.stockingDate.year}-${batch.stockingDate.month.toString().padLeft(2, '0')}-${batch.stockingDate.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onChanged: (value) => setSheetState(() {
                              if (value ?? false) {
                                selectedBatchIds.add(batch.batchId);
                              } else {
                                selectedBatchIds.remove(batch.batchId);
                              }
                            }),
                          ),
                        ),
                        const Divider(height: 28),
                        const Text(
                          'Detailed Records',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                          ),
                        ),
                        Text(
                          'Leave all unchecked for a summary-only report.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.darkWith(0.52),
                          ),
                        ),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          value: includeSampling,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sampling Records'),
                          onChanged: (value) => setSheetState(
                            () => includeSampling = value ?? false,
                          ),
                        ),
                        CheckboxListTile(
                          value: includeMortality,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mortality Records'),
                          onChanged: (value) => setSheetState(
                            () => includeMortality = value ?? false,
                          ),
                        ),
                        CheckboxListTile(
                          value: includeHarvest,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Harvest Records'),
                          onChanged: (value) => setSheetState(
                            () => includeHarvest = value ?? false,
                          ),
                        ),
                        if (!hasSelectedBatch)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Select at least one batch.',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        if (!hasReportContent)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Select the batch summary or at least one detailed record type.',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.darkWith(0.08)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.darkWith(0.7),
                              side: BorderSide(color: AppColors.darkWith(0.18)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: hasSelectedBatch && hasReportContent
                                ? () => Navigator.pop(
                                    sheetContext,
                                    _ReportExportSelection(
                                      batchIds: Set.of(selectedBatchIds),
                                      includeSummary: includeSummary,
                                      fileName: fileName,
                                      sections: GrowOutReportSections(
                                        includeSampling: includeSampling,
                                        includeMortality: includeMortality,
                                        includeHarvest: includeHarvest,
                                      ),
                                    ),
                                  )
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result;
  }

  Future<void> _export(BuildContext context, String format) async {
    final selection = await _chooseReportContent(context);
    if (selection == null || !context.mounted) return;

    try {
      final reportService = ReportExportService.instance;
      if (format == 'xlsx') {
        await reportService.shareAllGrowthExcel(
          batchIds: selection.batchIds,
          sections: selection.sections,
          includeSummary: selection.includeSummary,
          fileName: selection.fileName,
        );
      } else {
        await reportService.shareAllGrowthPdf(
          batchIds: selection.batchIds,
          sections: selection.sections,
          includeSummary: selection.includeSummary,
          fileName: selection.fileName,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            format == 'xlsx'
                ? 'Excel report ready — choose where to save or share it.'
                : 'PDF report ready — choose where to save or share it.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Export selected batch reports',
      onSelected: (format) => _export(context, format),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'xlsx',
          child: Row(
            children: [
              Icon(Icons.grid_on_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Export Excel'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 10),
              Text('Export PDF'),
            ],
          ),
        ),
      ],
      child: Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryWith(0.08),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.primaryWith(0.22)),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: expand
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            const Icon(
              Icons.ios_share_outlined,
              size: 13,
              color: AppColors.primary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
