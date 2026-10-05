import 'package:flutter/material.dart';

import '../../../services/report_export_service.dart';
import '../../../services/tank_service.dart';
import '../../../theme/app_colors.dart';

class _ReportExportSelection {
  final Set<String> batchIds;
  final GrowOutReportSections sections;
  final bool includeSummary;
  final bool includeIndividualMeasurements;
  final String fileName;

  const _ReportExportSelection({
    required this.batchIds,
    required this.sections,
    required this.includeSummary,
    required this.includeIndividualMeasurements,
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
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 260), reverseDuration: Duration(milliseconds: 220)),
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
    BuildContext context, {
    required bool canIncludeIndividualMeasurements,
  }) async {
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
    var includeIndividualMeasurements = true;
    var fileName = 'craycare_all_batches';

    final result = await showModalBottomSheet<_ReportExportSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 260), reverseDuration: Duration(milliseconds: 220)),
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
                          onChanged: (value) => setSheetState(() {
                            includeSampling = value ?? false;
                            if (!includeSampling) {
                              includeIndividualMeasurements = false;
                            }
                          }),
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
                        if (canIncludeIndividualMeasurements)
                          CheckboxListTile(
                            value: includeIndividualMeasurements,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Include individual crayfish measurements',
                            ),
                            subtitle: const Text(
                              'Groups measurements by sampling week and date, then lists each crayfish’s weight and length. Turn off for totals and averages only.',
                            ),
                            onChanged: includeSampling
                                ? (value) => setSheetState(
                                    () => includeIndividualMeasurements =
                                        value ?? false,
                                  )
                                : null,
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
                                      includeIndividualMeasurements:
                                          includeIndividualMeasurements,
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
                            child: const Text('Preview Report'),
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

  Future<bool> _previewReport(
    BuildContext context,
    _ReportExportSelection selection,
    List<BatchRecordSnapshot> snapshots,
    String format,
  ) async {
    final isExcel = format == 'xlsx';
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 260), reverseDuration: Duration(milliseconds: 220)),
          builder: (sheetContext) => SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview ${isExcel ? 'Excel' : 'PDF'} Report',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${snapshots.length} batch${snapshots.length == 1 ? '' : 'es'} selected · Review the included data before saving.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.darkWith(0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                      children: [
                        for (final snapshot in snapshots)
                          _buildBatchPreview(snapshot, selection),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.darkWith(0.08)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(isExcel ? 'Save Excel' : 'Save PDF'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Widget _buildBatchPreview(
    BatchRecordSnapshot snapshot,
    _ReportExportSelection selection,
  ) {
    final batch = snapshot.batch;
    final mortality = snapshot.mortality.fold<int>(
      0,
      (sum, row) => sum + row.count,
    );
    final harvested = snapshot.harvests.fold<int>(
      0,
      (sum, row) => sum + row.harvestedCount,
    );
    final rows = ReportExportService.growthRows(
      snapshot.sampling,
      batch.stockingDate,
    );
    final individualEntries = List.of(snapshot.sampling)
      ..sort((a, b) => a.date.compareTo(b.date));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppColors.primaryWith(0.045),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primaryWith(0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Batch ${batch.batchId}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.dark,
              ),
            ),
            if (selection.includeSummary) ...[
              const SizedBox(height: 8),
              Text(
                'Initial population: ${batch.initialCount} · Mortality: $mortality · Harvested: $harvested',
                style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.68)),
              ),
            ],
            if (selection.sections.includeSampling) ...[
              const SizedBox(height: 12),
              const Text(
                'Sampling Records',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'No sampling records.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.darkWith(0.58),
                    ),
                  ),
                ),
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    '${rows[i][0]} · ${rows[i][1]} · Sample size: ${rows[i][2]}\nTotal length: ${rows[i][3]} cm · Total weight: ${rows[i][4]} g\nAverage length: ${rows[i][5]} cm · Average weight: ${rows[i][6]} g',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AppColors.darkWith(0.72),
                    ),
                  ),
                ),
              if (selection.sections.includeSampling &&
                  selection.includeIndividualMeasurements)
                for (final entry in individualEntries)
                  if (entry.measurements.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        ReportExportService.samplingGroupTitle(
                          entry,
                          batch.stockingDate,
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    for (final measurement in entry.measurements)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, top: 3),
                        child: Text(
                          'Crayfish ${measurement.sampleNumber}: ${measurement.weightGrams.toStringAsFixed(2)} g · ${measurement.lengthCm.toStringAsFixed(2)} cm',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.darkWith(0.62),
                          ),
                        ),
                      ),
                  ],
              if (selection.sections.includeSampling &&
                  selection.includeIndividualMeasurements &&
                  snapshot.sampling.every(
                    (entry) => entry.measurements.isEmpty,
                  ))
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    'No individual measurements are saved for these samples.',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.darkWith(0.58),
                    ),
                  ),
                ),
            ],
            if (selection.sections.includeMortality) ...[
              const SizedBox(height: 10),
              Text(
                'Mortality records: ${snapshot.mortality.length} · $mortality total',
                style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.68)),
              ),
            ],
            if (selection.sections.includeHarvest) ...[
              const SizedBox(height: 5),
              Text(
                'Harvest records: ${snapshot.harvests.length} · $harvested crayfish',
                style: TextStyle(fontSize: 11, color: AppColors.darkWith(0.68)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, String format) async {
    final selection = await _chooseReportContent(
      context,
      canIncludeIndividualMeasurements: true,
    );
    if (selection == null || !context.mounted) return;

    try {
      final reportService = ReportExportService.instance;
      final snapshots = await TankService.instance.loadBatchRecordSnapshots(
        selection.batchIds,
      );
      if (snapshots.isEmpty) {
        throw StateError('No batch records are available to preview.');
      }
      if (!context.mounted) return;
      final confirmed = await _previewReport(
        context,
        selection,
        snapshots,
        format,
      );
      if (!confirmed || !context.mounted) return;
      if (format == 'xlsx') {
        await reportService.shareAllGrowthExcel(
          batchIds: selection.batchIds,
          sections: selection.sections,
          includeSummary: selection.includeSummary,
          includeIndividualMeasurements:
              selection.includeIndividualMeasurements,
          fileName: selection.fileName,
        );
      } else {
        await reportService.shareAllGrowthPdf(
          batchIds: selection.batchIds,
          sections: selection.sections,
          includeSummary: selection.includeSummary,
          includeIndividualMeasurements:
              selection.includeIndividualMeasurements,
          fileName: selection.fileName,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            format == 'xlsx'
                ? 'Excel is ready — choose Save/Files to download it.'
                : 'PDF is ready — choose where to save or share it.',
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
