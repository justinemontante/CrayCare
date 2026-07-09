import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../../../services/lettuce_service.dart';
import '../../../models/lettuce_batch.dart';
import '../../../utils/snackbar_helper.dart';

class LettuceSamplingTab extends StatefulWidget {
  final DateTime lastEdited;
  final bool isOwner;

  const LettuceSamplingTab({
    super.key,
    required this.lastEdited,
    this.isOwner = true,
  });

  @override
  State<LettuceSamplingTab> createState() => _LettuceSamplingTabState();
}

class _LettuceSamplingTabState extends State<LettuceSamplingTab> {
  final _sampleCountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final service = LettuceService.instance;
    final canSample = service.canSampleLettuce;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!service.isInitialized)
            _buildEmptyState()
          else ...[
            _buildSectionHeader('Lettuce Sampling'),
            const SizedBox(height: 8),
            _buildStatusBanner(service, canSample),
            const SizedBox(height: 10),
            const _LettuceNextSamplingPanel(),
            const SizedBox(height: 12),
            _buildSamplingForm(service, canSample),
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
          BoxShadow(color: AppColors.darkWith(0.12), blurRadius: 16, offset: const Offset(0, 4)),
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
            child: const Icon(Icons.biotech_rounded, size: 32, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          const Text('No Sampling Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.dark)),
          const SizedBox(height: 8),
          Text(
            'Initialize a lettuce batch first to start tracking growth through sampling.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.dark.withValues(alpha: 0.5), height: 1.4),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark));
  }

  Widget _buildStatusBanner(LettuceService service, bool canSample) {
    final daysSince = service.daysSinceLastLettuceSampling;
    final hasSampling = service.samplingHistory.isNotEmpty;

    Color bgColor;
    String msg;
    if (!hasSampling) {
      bgColor = AppColors.success.withValues(alpha: 0.08);
      msg = 'No sampling yet. Record your first sample below!';
    } else if (canSample) {
      bgColor = AppColors.warning.withValues(alpha: 0.08);
      msg = 'Ready for sampling ($daysSince days since last).';
    } else {
      bgColor = AppColors.darkWith(0.04);
      msg = 'Next sampling available in ${service.daysUntilNextLettuceSampling} day(s).';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkWith(0.08)),
      ),
      child: Row(
        children: [
          Icon(
            canSample || !hasSampling ? Icons.info_outline_rounded : Icons.schedule_rounded,
            size: 16,
            color: AppColors.darkWith(0.6),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.7))),
          ),
        ],
      ),
    );
  }

  Widget _buildSamplingForm(LettuceService service, bool canSample) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.darkWith(0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.analytics_rounded, size: 16, color: AppColors.success),
              ),
              const SizedBox(width: 8),
              const Text('Record Sampling', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const Spacer(),
              GestureDetector(
                onTap: _showSamplingHistoryModal,
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
          _buildInputField('Sample Size', 'e.g. 10', _sampleCountCtrl, TextInputType.number),
          const SizedBox(height: 16),
          const Text('Total Measurements', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSampleInputCard('Height', Icons.straighten_rounded, 'totalHeight', TextInputType.number, AppColors.primary),
              const SizedBox(width: 8),
              _buildSampleInputCard('Leaf Count', Icons.eco_rounded, 'totalLeafCount', TextInputType.number, AppColors.success),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final sampleSize = int.tryParse(_sampleCountCtrl.text);
                    if (sampleSize == null || sampleSize <= 0) {
                      showBeautifulSnackbar(context, 'Enter a valid sample size.', false);
                      return;
                    }
                    if (sampleSize > service.currentQuantity) {
                      showBeautifulSnackbar(context, 'Sample size exceeds available plants.', false);
                      return;
                    }
                    final totalHeight = double.tryParse(_totalHeightCtrl.text);
                    final totalLeafCount = int.tryParse(_totalLeafCountCtrl.text);
                    if (totalHeight == null || totalLeafCount == null || totalHeight <= 0 || totalLeafCount <= 0) {
                      showBeautifulSnackbar(context, 'Enter valid total height and leaf count.', false);
                      return;
                    }
                    if (!widget.isOwner) {
                      showBeautifulSnackbar(context, 'Only the owner can record sampling.', false);
                      return;
                    }
                    await LettuceService.instance.addLettuceSampling(
                      sampleSize: sampleSize,
                      totalHeight: totalHeight,
                      totalLeafCount: totalLeafCount,
                    );
                    _sampleCountCtrl.clear();
                    _totalHeightCtrl.clear();
                    _totalLeafCountCtrl.clear();
                    if (mounted) {
                      showBeautifulSnackbar(context, 'Sampling recorded!', true);
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Sampling', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isOwner && (canSample || !service.samplingHistory.isNotEmpty) ? AppColors.success : Colors.grey.shade300,
                    foregroundColor: widget.isOwner && (canSample || !service.samplingHistory.isNotEmpty) ? Colors.white : Colors.grey.shade500,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSamplingHistoryModal() {
    final service = LettuceService.instance;
    final history = service.samplingHistory;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Color(0xFFFCFCFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.darkWith(0.2), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  const Text('Sampling History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  const Spacer(),
                  Text('${history.length} recorded', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_rounded, size: 40, color: AppColors.darkWith(0.15)),
                        const SizedBox(height: 12),
                        Text('No sampling records yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.4))),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: history.reversed.map((e) => _buildSamplingEntryCard(e)).toList(),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  final _totalHeightCtrl = TextEditingController();
  final _totalLeafCountCtrl = TextEditingController();

  @override
  void dispose() {
    _sampleCountCtrl.dispose();
    _totalHeightCtrl.dispose();
    _totalLeafCountCtrl.dispose();
    super.dispose();
  }

  Widget _buildInputField(String label, String hint, TextEditingController ctrl, TextInputType type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
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
        ),
      ],
    );
  }

  Widget _buildSampleInputCard(String label, IconData icon, String metric, TextInputType type, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: metric == 'totalHeight' ? _totalHeightCtrl : _totalLeafCountCtrl,
              keyboardType: type,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark),
              decoration: InputDecoration(
                hintText: metric == 'totalHeight' ? 'Total cm' : 'Total leaves',
                hintStyle: TextStyle(color: AppColors.dark.withValues(alpha: 0.25), fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color.withValues(alpha: 0.4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSamplingEntryCard(LettuceSamplingEntry entry) {
    final dateStr = '${_months[entry.date.month - 1]} ${entry.date.day}, ${entry.date.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkWith(0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkWith(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.dark)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${entry.sampleSize} plants', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.success)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMetricMini('Avg Height', '${entry.avgHeight.toStringAsFixed(1)} cm', AppColors.primary),
                const SizedBox(width: 12),
                _buildMetricMini('Avg Leaves', entry.avgLeafCount.toStringAsFixed(0), AppColors.success),
                const SizedBox(width: 12),
                _buildMetricMini('Total Height', '${entry.totalHeight.toStringAsFixed(1)} cm', AppColors.dark),
                const SizedBox(width: 12),
                _buildMetricMini('Total Leaves', '${entry.totalLeafCount}', AppColors.dark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricMini(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
        ],
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
}

class _LettuceNextSamplingPanel extends StatelessWidget {
  const _LettuceNextSamplingPanel();

  @override
  Widget build(BuildContext context) {
    final service = LettuceService.instance;
    final daysSince = service.daysSinceLastLettuceSampling;
    final daysRemaining = daysSince >= 7 ? 0 : 7 - daysSince;
    final nextWeekNum = service.samplingHistory.length + 1;
    final hasSampling = service.samplingHistory.isNotEmpty;

    String nextDateStr;
    if (hasSampling) {
      final nextDate = service.samplingHistory.last.date.add(const Duration(days: 7));
      nextDateStr = _formatDate(nextDate);
    } else {
      final nextDate = service.plantingDate.add(const Duration(days: 7));
      nextDateStr = _formatDate(nextDate);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.darkWith(0.12), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, color: AppColors.success, size: 13),
              const SizedBox(width: 6),
              Text('Sampling Schedule', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text('Week $nextWeekNum', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.success)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: AppColors.dark.withValues(alpha: 0.05)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next Session', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.45))),
                  const SizedBox(height: 3),
                  Text(
                    daysRemaining == 0 ? 'Today (Due)' : nextDateStr,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Time Remaining', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.45))),
                  const SizedBox(height: 3),
                  Text(
                    daysRemaining == 0 ? 'Ready to record' : '$daysRemaining days left',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.success),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStepTracker(daysSince >= 7 ? 7 : daysSince, 7),
        ],
      ),
    );
  }

  Widget _buildStepTracker(int currentDay, int totalDays) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(totalDays, (index) {
            final day = index + 1;
            final isPast = day < currentDay;
            final isCurrent = day == currentDay;
            return Expanded(
              child: Row(
                children: [
                  _buildStepDot(day, isPast, isCurrent),
                  if (index < totalDays - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isPast ? AppColors.success : AppColors.darkWith(0.08),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text('Day $currentDay', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.darkWith(0.5))),
      ],
    );
  }

  Widget _buildStepDot(int day, bool isPast, bool isCurrent) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: isPast ? AppColors.success : (isCurrent ? AppColors.warning : Colors.white),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPast ? AppColors.success : (isCurrent ? AppColors.warning : AppColors.darkWith(0.15)),
          width: 2,
        ),
        boxShadow: isCurrent ? [BoxShadow(color: AppColors.warning.withValues(alpha: 0.2), blurRadius: 6, spreadRadius: 1)] : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isPast || isCurrent ? Colors.white : AppColors.darkWith(0.5),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}