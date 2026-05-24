import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';
import '../../models/crayfish_stage.dart';

// Copying helper to use within sampling UI
void showBeautifulSnackbar(
  BuildContext context,
  String message,
  bool isSuccess,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isSuccess ? AppColors.success : AppColors.critical,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 10,
      duration: const Duration(seconds: 3),
    ),
  );
}

class SamplingTab extends StatelessWidget {
  final TextEditingController sampleCountController;
  final TextEditingController sampleWeightController;
  final TextEditingController sampleLengthController;

  const SamplingTab({
    super.key,
    required this.sampleCountController,
    required this.sampleWeightController,
    required this.sampleLengthController,
  });

  @override
  Widget build(BuildContext context) {
    if (!TankService.instance.isInitialized) return _buildEmptyState();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NextSamplingPanel(),
          const SizedBox(height: 12),
          const GrowthOverviewPanel(),
          const SizedBox(height: 12),
          const SamplingFormPanel(),
          const SizedBox(height: 12),
          const SamplingHistoryPanel(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.speed_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sampling Restricted',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You must initialize your tank inventory first before you can record sampling data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.dark.withValues(alpha: 0.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NextSamplingPanel extends StatelessWidget {
  const NextSamplingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final daysInCycle = 7;
    final currentDay = (service.daysInCulture % daysInCycle) + 1;
    final daysRemaining = daysInCycle - currentDay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryWith(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      daysRemaining == 0
                          ? 'Sampling Day!'
                          : '$daysRemaining days remaining',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: daysRemaining == 0
                            ? AppColors.critical
                            : AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due on ${_formatDate(DateTime.now().add(Duration(days: daysRemaining)))}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkWith(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lightBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Week ${((currentDay - 1) / 7).floor() + 1}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkWith(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 12),
          _buildStepTracker(currentDay, daysInCycle),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
                        color: isPast ? AppColors.primary : AppColors.lightBg,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Day $currentDay',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.darkWith(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDot(int day, bool isPast, bool isCurrent) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: isPast
            ? AppColors.primary
            : (isCurrent ? AppColors.warning : AppColors.white),
        shape: BoxShape.circle,
        border: Border.all(
          color: isPast
              ? AppColors.primary
              : (isCurrent ? AppColors.warning : AppColors.faintBorder),
          width: 2,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.warningWith(0.2),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isPast || isCurrent ? Colors.white : AppColors.darkWith(0.5),
          ),
        ),
      ),
    );
  }
}

class GrowthOverviewPanel extends StatelessWidget {
  const GrowthOverviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory;
    final latest = history.isNotEmpty ? history.last : null;
    final initialW = service.initialWeight;
    final initialL = service.initialLength;

    final latestW = latest?.abw ?? initialW;
    final latestL = latest?.avgLength ?? initialL;

    final diffW = latestW - initialW;
    final diffL = latestL - initialL;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Growth Overview',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMiniCard(
                'Initial Baseline',
                _formatDate(service.stockingDate),
                initialW,
                initialL,
                AppColors.primaryWith(0.08),
                AppColors.primary,
                'Avg Weight',
                'Avg Length',
              ),
              const SizedBox(width: 12),
              _buildMiniCard(
                'Latest Sampling',
                latest != null
                    ? _formatDate(latest.date)
                    : _formatDate(service.stockingDate),
                latestW,
                latestL,
                AppColors.successWith(0.08),
                AppColors.success,
                'Avg Weight',
                'Avg Length',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildGrowthFullCard(diffW, diffL),
        ],
      ),
    );
  }

  Widget _buildMiniCard(
    String title,
    String subTitle,
    double weight,
    double length,
    Color bgColor,
    Color accentColor,
    String weightLabel,
    String lengthLabel,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subTitle,
              style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.5)),
            ),
            const SizedBox(height: 12),
            _buildDataRow(weightLabel, '${weight.toStringAsFixed(1)} g'),
            _buildDataRow(lengthLabel, '${length.toStringAsFixed(1)} cm'),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthFullCard(double weight, double length) {
    final isPosW = weight >= 0;
    final isPosL = length >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.warningWith(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warningWith(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Net Growth',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.warningDark,
            ),
          ),
          Row(
            children: [
              _buildGrowthMetric(
                'Avg Weight',
                '${isPosW ? '+' : ''}${weight.toStringAsFixed(1)} g',
                isPosW,
              ),
              const SizedBox(width: 16),
              _buildGrowthMetric(
                'Avg Length',
                '${isPosL ? '+' : ''}${length.toStringAsFixed(1)} cm',
                isPosL,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthMetric(String label, String value, bool isPos) {
    return Column(
      children: [
        Text(
          '$label:',
          style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isPos ? AppColors.success : AppColors.critical,
          ),
        ),
      ],
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.6)),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class SamplingFormPanel extends StatefulWidget {
  const SamplingFormPanel({super.key});

  @override
  State<SamplingFormPanel> createState() => _SamplingFormPanelState();
}

class _SamplingFormPanelState extends State<SamplingFormPanel> {
  final _countController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  bool _isRecorded = false;
  String? _countError;

  @override
  void initState() {
    super.initState();
    _checkLastSampling();
  }

  void _checkLastSampling() {
    final history = TankService.instance.samplingHistory;
    if (history.isNotEmpty) {
      final last = history.last;
      final today = DateTime.now();
      if (last.date.day == today.day &&
          last.date.month == today.month &&
          last.date.year == today.year) {
        _isRecorded = true;
        _countController.text = last.sampleSize.toString();
        _weightController.text = last.totalWeight.toStringAsFixed(1);
        _lengthController.text = last.totalLength.toStringAsFixed(1);
      }
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  void _revalidateCount() {
    final count = int.tryParse(_countController.text) ?? 0;
    final maxSample = TankService.instance.liveCount;
    if (count > 0 && maxSample > 0 && count > maxSample) {
      setState(() => _countError = 'Exceeds live count ($maxSample)');
    } else {
      setState(() => _countError = null);
    }
  }

  void _handleCompute() {
    _revalidateCount();
    if (_countError != null) return;

    final count = int.tryParse(_countController.text);
    final weight = double.tryParse(_weightController.text);
    final length = double.tryParse(_lengthController.text);

    if (count != null &&
        weight != null &&
        length != null &&
        count > 0 &&
        weight > 0 &&
        length > 0) {
      TankService.instance.addSamplingEntry(count, weight, length);
      setState(() => _isRecorded = true);
      showBeautifulSnackbar(
        context,
        'Sampling successfully recorded & computed!',
        true,
      );
    }
  }

  void _handleEdit() {
    setState(() => _isRecorded = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Weekly Sampling',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              if (_isRecorded)
                TextButton(
                  onPressed: _handleEdit,
                  child: const Text(
                    'Edit',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInputCard(
                  Image.asset('assets/images/SampleCount.png', width: 20, height: 20),
                  'Sample Count',
                  'Crayfish sampled',
                  '10',
                  _countController,
                  enabled: !_isRecorded,
                  hasError: _countError != null,
                  onChanged: _revalidateCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInputCard(
                  Image.asset('assets/images/TotalWeight.png', width: 20, height: 20),
                  'Total Weight',
                  'Weight of samples',
                  '150',
                  _weightController,
                  enabled: !_isRecorded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInputCard(
                  Image.asset('assets/images/TotalLength.png', width: 20, height: 20),
                  'Total Length',
                  'Length of samples',
                  '60',
                  _lengthController,
                  enabled: !_isRecorded,
                ),
              ),
            ],
          ),
          if (_countError != null && !_isRecorded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.critical.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: AppColors.critical,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _countError!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.critical.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (!_isRecorded)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleCompute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _countError != null
                      ? AppColors.dark.withValues(alpha: 0.2)
                      : AppColors.primary,
                  foregroundColor: _countError != null
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.white,
                  disabledBackgroundColor: AppColors.dark.withValues(alpha: 0.2),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Compute Results',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          if (_isRecorded)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text(
                  'Recorded',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.success,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputCard(
    Widget iconWidget,
    String label,
    String subtitle,
    String hint,
    TextEditingController controller, {
    bool enabled = true,
    bool hasError = false,
    VoidCallback? onChanged,
  }) {
    final borderColor = hasError && enabled
        ? AppColors.critical.withValues(alpha: 0.6)
        : AppColors.dark.withValues(alpha: 0.15);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled ? AppColors.primaryWith(0.03) : AppColors.primaryWith(0.01),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError && enabled
              ? AppColors.critical.withValues(alpha: 0.35)
              : (enabled
                  ? AppColors.darkWith(0.08)
                  : AppColors.darkWith(0.04)),
        ),
      ),
      child: Column(
        children: [
          Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: iconWidget,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: hasError && enabled
                  ? AppColors.critical
                  : (enabled ? AppColors.dark : AppColors.darkWith(0.4)),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: hasError && enabled
                  ? AppColors.critical.withValues(alpha: 0.6)
                  : (enabled ? AppColors.darkWith(0.5) : AppColors.darkWith(0.3)),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged?.call(),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            enabled: enabled,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: enabled ? Colors.white : AppColors.darkWith(0.04),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError && enabled
                      ? AppColors.critical
                      : AppColors.primary,
                ),
              ),
              hintStyle: TextStyle(fontSize: 12, color: AppColors.darkWith(0.3)),
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: hasError && enabled
                  ? AppColors.critical
                  : (enabled ? AppColors.dark : AppColors.darkWith(0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class GrowthStagePanel extends StatelessWidget {
  final VoidCallback onInfoTap;
  const GrowthStagePanel({super.key, required this.onInfoTap});

  @override
  Widget build(BuildContext context) {
    final stages = CrayfishStage.all;
    final history = TankService.instance.samplingHistory;
    final currentAbw = history.isNotEmpty
        ? history.last.abw
        : TankService.instance.initialWeight;

    int activeIndex = 0;
    for (int i = 0; i < stages.length; i++) {
      if (currentAbw >= stages[i].threshold) activeIndex = i;
    }

    final double progress = (activeIndex + 1) / stages.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Growth Stage',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  Text(
                    'Current: ${stages[activeIndex].label}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onInfoTap,
                child: const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.darkWith(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF52c283), AppColors.primary],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryWith(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(stages.length, (i) {
                    final isActive = i <= activeIndex;
                    return Container(
                      width: 2,
                      height: 8,
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.transparent,
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(stages.length, (i) {
              final isActive = i == activeIndex;
              final isReached = i <= activeIndex;
              return Expanded(
                child: Text(
                  stages[i].label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive
                        ? AppColors.primary
                        : (isReached
                              ? AppColors.darkWith(0.7)
                              : AppColors.darkWith(0.3)),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class SamplingHistoryPanel extends StatelessWidget {
  const SamplingHistoryPanel({super.key});

  void _showAllHistory(BuildContext context) {
    final service = TankService.instance;
    final allHistory = service.samplingHistory.toList();
    final totalItems = allHistory.length + 1; // +1 for baseline

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.55,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.dark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'All Sampling History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.dark,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$totalItems entries',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dark.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: totalItems,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    // Latest to first: sampling entries first, then baseline
                    if (i < allHistory.length) {
                      final entry = allHistory.reversed.toList()[i];
                      final isLatest = i == 0;
                      return _buildHistoryCard(
                        title: '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                        dateLabel: 'Sampling entry',
                        abw: entry.abw,
                        abl: entry.avgLength,
                        sampleSize: entry.sampleSize,
                        isLatest: isLatest,
                        icon: const Icon(
                          Icons.biotech_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      );
                    }
                    // Last item = Initial Baseline
                    return _buildHistoryCard(
                      title: 'Initial Baseline',
                      dateLabel: '${service.stockingDate.month}/${service.stockingDate.day}/${service.stockingDate.year}',
                      abw: service.initialWeight,
                      abl: service.initialLength,
                      sampleSize: service.sampleCount,
                      isLatest: false,
                      icon: Image.asset(
                        'assets/images/InitialPopulation.png',
                        width: 20,
                        height: 20,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
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
        );
      },
    );
  }

  Widget _buildHistoryCard({
    required String title,
    required String dateLabel,
    required double abw,
    required double abl,
    required int sampleSize,
    required bool isLatest,
    required Widget icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLatest
            ? AppColors.primaryWith(0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest
              ? AppColors.primaryWith(0.2)
              : AppColors.darkWith(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: icon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ABW: ${abw.toStringAsFixed(2)}g',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ABL: ${abl.toStringAsFixed(2)}cm',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$sampleSize samples',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory.toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.faintBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sampling History',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              TextButton(
                onPressed: () => _showAllHistory(context),
                child: const Text(
                  'View All',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (history.isEmpty && !TankService.instance.isInitialized)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No sampling history yet.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.4),
                  ),
                ),
              ),
            )
          else ...[
            // History entries — latest first
            ...List.generate(
              history.length > 3 ? 3 : history.length,
              (i) {
                final entry = history.reversed.toList()[i];
                final isLatest = i == 0;
                return Padding(
                  padding: EdgeInsets.only(bottom: i < 2 ? 8 : 0),
                  child: _buildHistoryCard(
                    title: '${entry.date.month}/${entry.date.day}/${entry.date.year}',
                    dateLabel: 'Sampling entry',
                    abw: entry.abw,
                    abl: entry.avgLength,
                    sampleSize: entry.sampleSize,
                    isLatest: isLatest,
                    icon: const Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
            // Initial baseline card at the bottom — same design as history cards
            if (TankService.instance.isInitialized)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildHistoryCard(
                  title: 'Initial Baseline',
                  dateLabel: '${service.stockingDate.month}/${service.stockingDate.day}/${service.stockingDate.year}',
                  abw: service.initialWeight,
                  abl: service.initialLength,
                  sampleSize: service.sampleCount,
                  isLatest: false,
                  icon: Image.asset(
                    'assets/images/InitialPopulation.png',
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
