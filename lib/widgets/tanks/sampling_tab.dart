import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/tank_service.dart';
import '../../utils/snackbar_helper.dart';

class SamplingTab extends StatelessWidget {
  final DateTime lastEdited;
  final bool isOwner;

  const SamplingTab({
    super.key,
    required this.lastEdited,
    this.isOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!TankService.instance.isInitialized) return _buildEmptyState();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(),
          const SizedBox(height: 8),
          NextSamplingPanel(),
          const SizedBox(height: 12),
          GrowthOverviewPanel(),
          const SizedBox(height: 12),
          SamplingFormPanel(isOwner: isOwner),
          const SizedBox(height: 12),
          SamplingHistoryPanel(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Growth Sampling',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Weigh & measure to compute ABW and ABL.',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.dark.withValues(alpha: 0.5),
            ),
          ),
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
    final daysSince = service.daysSinceLastSampling;
    final daysRemaining = daysSince >= 7 ? 0 : 7 - daysSince;

    return Container(
      padding: const EdgeInsets.all(16),
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
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: daysRemaining == 0
                              ? AppColors.critical
                              : AppColors.primary,
                          size: 12,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Next sampling:',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: AppColors.darkWith(0.45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      daysRemaining == 0
                          ? 'Sampling Day!'
                          : '$daysRemaining days remaining',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: daysRemaining == 0
                            ? AppColors.critical
                            : AppColors.dark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Sampling Week ${service.samplingHistory.where((e) => !e.isBaseline).length}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    'Scheduled: ${daysRemaining == 0 ? "Today" : _formatDate(DateTime.now().add(Duration(days: daysRemaining)))}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: daysRemaining == 0
                          ? AppColors.critical
                          : AppColors.darkWith(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: AppColors.faintBorder),
          const SizedBox(height: 14),
          _buildStepTracker(daysSince >= 7 ? 7 : daysSince, 7),
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
    final hasWeeklySampling = history.any((e) => !e.isBaseline);
    final latest = hasWeeklySampling
        ? history.lastWhere((e) => !e.isBaseline)
        : null;
    final initialW = service.initialWeight;
    final initialL = service.initialLength;

    final latestW = latest?.abw ?? initialW;
    final latestL = latest?.avgLength ?? initialL;

    final diffW = latestW - initialW;
    final diffL = latestL - initialL;

    return Container(
      padding: const EdgeInsets.all(18),
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
                false,
              ),
              const SizedBox(width: 12),
              hasWeeklySampling
                  ? _buildMiniCard(
                      'Latest Sampling',
                      _formatDate(latest!.date),
                      latestW,
                      latestL,
                      true,
                    )
                  : _buildAwaitingCard(),
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
    bool isLatest,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isLatest ? AppColors.primary : AppColors.darkWith(0.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subTitle,
              style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.5)),
            ),
            const SizedBox(height: 12),
            _buildDataRow(
              'ABW:',
              '${weight.toStringAsFixed(1)} g',
              center: true,
            ),
            _buildDataRow(
              'ABL:',
              '${length.toStringAsFixed(1)} cm',
              center: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAwaitingCard() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Latest Sampling',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Awaiting Week 1\nSampling',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.45),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            _buildDataRow('ABW:', '—', center: true),
            _buildDataRow('ABL:', '—', center: true),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dark.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Growth Change',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.dark,
            ),
          ),
          IntrinsicHeight(
            child: Row(
              children: [
                _buildGrowthMetric(
                  'Weight Gain',
                  '${isPosW ? '+' : ''}${weight.toStringAsFixed(1)}g',
                  isPosW,
                ),
                const SizedBox(width: 10),
                Container(width: 1, color: AppColors.darkWith(0.25)),
                const SizedBox(width: 10),
                _buildGrowthMetric(
                  'Length Gain',
                  '${isPosL ? '+' : ''}${length.toStringAsFixed(1)}cm',
                  isPosL,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthMetric(String label, String value, bool isPos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 8, color: AppColors.darkWith(0.5)),
        ),
        const SizedBox(height: 4),
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

  Widget _buildDataRow(String label, String value, {bool center = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: center
          ? Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label ',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.darkWith(0.6),
                      ),
                    ),
                    TextSpan(
                      text: value,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 9, color: AppColors.darkWith(0.6)),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
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
  final bool isOwner;
  const SamplingFormPanel({super.key, this.isOwner = true});

  @override
  State<SamplingFormPanel> createState() => _SamplingFormPanelState();
}

class _SamplingFormPanelState extends State<SamplingFormPanel> {
  final _countController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  bool _isRecorded = false;
  bool _isEditing = false;
  String? _countError;
  late final VoidCallback _serviceListener;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _checkLastSampling();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _serviceListener = () {
      if (mounted) setState(() => _checkLastSampling());
    };
    TankService.instance.addListener(_serviceListener);
  }

  void _checkLastSampling() {
    _isEditing = false;
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
      } else {
        _isRecorded = false;
      }
    } else {
      _isRecorded = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    TankService.instance.removeListener(_serviceListener);
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
      final wasEditing = _isEditing;
      if (wasEditing) {
        TankService.instance.updateLastSamplingEntry(count, weight, length);
      } else {
        TankService.instance.addSamplingEntry(count, weight, length);
      }
      setState(() {
        _isRecorded = true;
        _isEditing = false;
      });
      showBeautifulSnackbar(
        context,
        wasEditing ? 'Sampling successfully updated!' : 'Sampling successfully recorded & computed!',
        true,
      );
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  void _handleEdit() {
    final lastEntry = TankService.instance.samplingHistory.last.date;
    if (!_isToday(lastEntry)) {
      showBeautifulSnackbar(
        context,
        'Sampling data can only be edited on the same day it was recorded.',
        false,
      );
      return;
    }
    setState(() {
      _isRecorded = false;
      _isEditing = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSample = TankService.instance.canSample;
    final service = TankService.instance;
    final daysSince = service.daysSinceLastSampling;
    final daysRemaining = daysSince >= 7 ? 0 : 7 - daysSince;
    final lastEntryIsToday = service.samplingHistory.isNotEmpty
        ? _isToday(service.samplingHistory.last.date)
        : false;

    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dynamic Call-To-Action Banner inside the Card
          if (daysRemaining == 0 && !_isRecorded) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF7ED), Color(0xFFFFF1F2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.critical.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFECACA),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notification_important_rounded,
                      size: 16,
                      color: AppColors.critical,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Weekly Sampling Due!',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '7 days passed since your last log. Update metrics now.',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF991B1B).withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Weekly Sampling',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  if (daysRemaining == 0 && !_isRecorded)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.critical.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'DUE',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: AppColors.critical,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              if (_isRecorded && widget.isOwner && lastEntryIsToday)
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
                  Image.asset(
                    'assets/images/SampleCount.png',
                    width: 20,
                    height: 20,
                  ),
                  'Sample Size',
                  'Crayfish sampled',
                  '10',
                  _countController,
                  enabled: (!_isRecorded && canSample) || _isEditing,
                  hasError: _countError != null,
                  onChanged: _revalidateCount,
                  subtitleBottomSpacing: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInputCard(
                  Image.asset(
                    'assets/images/TotalWeight.png',
                    width: 20,
                    height: 20,
                  ),
                  'Sample Weight',
                  'Weight of samples',
                  '150',
                  _weightController,
                  enabled: (!_isRecorded && canSample) || _isEditing,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInputCard(
                  Image.asset(
                    'assets/images/TotalLength.png',
                    width: 20,
                    height: 20,
                  ),
                  'Sample Length',
                  'Length of samples',
                  '60',
                  _lengthController,
                  enabled: (!_isRecorded && canSample) || _isEditing,
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
          if (!_isRecorded && (canSample || _isEditing))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.isOwner && _countError == null ? _handleCompute : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.isOwner && _countError == null
                      ? AppColors.primary
                      : AppColors.dark.withValues(alpha: 0.2),
                  foregroundColor: widget.isOwner && _countError == null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  disabledBackgroundColor: AppColors.dark.withValues(
                    alpha: 0.2,
                  ),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.isOwner ? 'Compute Results' : 'Compute Results (Owner Only)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          if (!_isRecorded && !canSample && !_isEditing)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: Text(
                  'Sampling available in ${7 - TankService.instance.daysSinceLastSampling} days',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark.withValues(alpha: 0.15),
                  foregroundColor: AppColors.dark.withValues(alpha: 0.5),
                  disabledBackgroundColor: AppColors.dark.withValues(
                    alpha: 0.15,
                  ),
                  disabledForegroundColor: AppColors.dark.withValues(
                    alpha: 0.5,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
    double subtitleBottomSpacing = 8,
  }) {
    final borderColor = hasError && enabled
        ? AppColors.critical.withValues(alpha: 0.6)
        : AppColors.dark.withValues(alpha: 0.15);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primaryWith(0.03)
            : AppColors.primaryWith(0.01),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError && enabled
              ? AppColors.critical.withValues(alpha: 0.35)
              : (enabled ? AppColors.darkWith(0.08) : AppColors.darkWith(0.04)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                  : (enabled
                        ? AppColors.darkWith(0.5)
                        : AppColors.darkWith(0.3)),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: subtitleBottomSpacing),
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
              hintStyle: TextStyle(
                fontSize: 12,
                color: AppColors.darkWith(0.3),
              ),
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

  static const List<_StageRange> _stages = [
    _StageRange(abwMin: 1, abwMax: 5, ablMin: 2, ablMax: 4),
    _StageRange(abwMin: 5, abwMax: 15, ablMin: 4, ablMax: 6),
    _StageRange(abwMin: 15, abwMax: 50, ablMin: 6, ablMax: 10),
    _StageRange(abwMin: 50, abwMax: 100, ablMin: 10, ablMax: 12),
  ];

  static const List<String> _labels = [
    'Early Juvenile',
    'Advanced Juvenile',
    'Pre-Adult',
    'Market Size',
  ];

  int _indexOf(GrowthStage stage) {
    switch (stage) {
      case GrowthStage.earlyJuvenile: return 0;
      case GrowthStage.advancedJuvenile: return 1;
      case GrowthStage.preAdult: return 2;
      case GrowthStage.marketSize: return 3;
    }
  }

  double _calcProgress(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (value - min) / (max - min);
  }

  @override
  Widget build(BuildContext context) {
    final service = TankService.instance;
    final history = service.samplingHistory;

    final currentAbw = history.isNotEmpty
        ? history.last.abw
        : service.initialWeight;

    final currentAbl = history.isNotEmpty
        ? history.last.avgLength
        : service.initialLength;

    final currentStage = service.currentGrowthStage;
    final activeIndex = _indexOf(currentStage);
    final range = _stages[activeIndex];

    final abwProgress = _calcProgress(currentAbw, range.abwMin, range.abwMax);
    final ablProgress = currentAbl > 0
        ? _calcProgress(currentAbl, range.ablMin, range.ablMax)
        : 1.0;
    final stageProgress = (abwProgress < ablProgress ? abwProgress : ablProgress).clamp(0.0, 1.0);

    // Scale progress across the entire bar (4 stages, each represents 25% or 0.25)
    final progress = ((activeIndex * 0.25) + (stageProgress * 0.25)).clamp(0.0, 1.0);

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
                    'Current: ${_labels[activeIndex]}',
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

          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.darkWith(0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_labels.length, (i) {
              final isThisActive = i == activeIndex;
              final isReached = i <= activeIndex;

              return Expanded(
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: isThisActive
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: isThisActive
                        ? AppColors.primary
                        : isReached
                        ? AppColors.darkWith(0.7)
                        : AppColors.darkWith(0.3),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ABW: ${currentAbw.toStringAsFixed(1)}g',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 1,
                      height: 14,
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    Text(
                      'ABL: ${currentAbl.toStringAsFixed(1)}cm',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Stage is based on both ABW and ABL.',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRange {
  final double abwMin;
  final double abwMax;
  final double ablMin;
  final double ablMax;

  const _StageRange({
    required this.abwMin,
    required this.abwMax,
    required this.ablMin,
    required this.ablMax,
  });
}

class _HistoryEntry {
  final String title;
  final String dateLabel;
  final double abw;
  final double abl;
  final int sampleSize;
  final double? gainW;
  final double? gainL;
  final Widget? icon;
  _HistoryEntry({
    this.title = '',
    this.dateLabel = '',
    this.abw = 0,
    this.abl = 0,
    this.sampleSize = 0,
    this.gainW,
    this.gainL,
    this.icon,
  });
}

class SamplingHistoryPanel extends StatelessWidget {
  const SamplingHistoryPanel({super.key});

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

  void _showAllHistory(BuildContext context) {
    final service = TankService.instance;
    final allHistory = service.samplingHistory
        .where((e) => !e.isBaseline)
        .toList();

    List<_HistoryEntry> entries = [];
    entries.add(
      _HistoryEntry(
        title: 'Week 0 (Baseline)',
        dateLabel: _formatDate(service.stockingDate),
        abw: service.initialWeight,
        abl: service.initialLength,
        sampleSize: service.sampleCount,
        icon: Image.asset(
          'assets/images/InitialPopulation.png',
          width: 20,
          height: 20,
        ),
      ),
    );
    for (int i = 0; i < allHistory.length; i++) {
      final entry = allHistory[i];
      final prevAbw = i == 0 ? service.initialWeight : allHistory[i - 1].abw;
      final prevAbl = i == 0
          ? service.initialLength
          : allHistory[i - 1].avgLength;
      entries.add(
        _HistoryEntry(
          title: 'Week ${i + 1}',
          dateLabel: _formatDate(entry.date),
          abw: entry.abw,
          abl: entry.avgLength,
          sampleSize: entry.sampleSize,
          gainW: entry.abw - prevAbw,
          gainL: entry.avgLength - prevAbl,
          icon: const Icon(
            Icons.biotech_rounded,
            size: 18,
            color: AppColors.primary,
          ),
        ),
      );
    }

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
                    '${entries.length} entries',
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
                  itemCount: entries.reversed.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final entry = entries.reversed.toList()[i];
                    final isLatest =
                        i == 0 && !entry.title.contains('Baseline');
                    return _buildHistoryCard(
                      title: entry.title,
                      dateLabel: entry.dateLabel,
                      abw: entry.abw,
                      abl: entry.abl,
                      sampleSize: entry.sampleSize,
                      isLatest: isLatest,
                      icon: entry.icon!,
                      gainW: entry.gainW,
                      gainL: entry.gainL,
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    double? gainW,
    double? gainL,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.dark.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  ],
                ),
              ),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Latest',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDetailBadge(
                  'Sample Size',
                  '$sampleSize',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDetailBadge(
                  'ABW',
                  '${abw.toStringAsFixed(2)} g',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDetailBadge(
                  'ABL',
                  '${abl.toStringAsFixed(2)} cm',
                  AppColors.success,
                ),
              ),
            ],
          ),
          if (gainW != null && gainL != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 12,
                  color: gainW >= 0 ? AppColors.success : AppColors.critical,
                ),
                const SizedBox(width: 4),
                Text(
                  'Weight Gain: ${gainW >= 0 ? "+" : ""}${gainW.toStringAsFixed(2)}g',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: gainW >= 0 ? AppColors.success : AppColors.critical,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Length Gain: ${gainL >= 0 ? "+" : ""}${gainL.toStringAsFixed(2)}cm',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: gainL >= 0 ? AppColors.success : AppColors.critical,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMainViewCards() {
    final service = TankService.instance;
    final weeklyHistory = service.samplingHistory
        .where((e) => !e.isBaseline)
        .toList();

    if (weeklyHistory.isEmpty) {
      return [
        _buildHistoryCard(
          title: 'Week 0 (Baseline)',
          dateLabel: _formatDate(service.stockingDate),
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
      ];
    }

    final totalWeekly = weeklyHistory.length;
    final showCount = totalWeekly >= 2 ? 2 : 1;
    final recent = weeklyHistory.reversed.take(showCount).toList();

    return recent.asMap().entries.map((e) {
      final idxInRecent = e.key;
      final idxInHistory = totalWeekly - 1 - idxInRecent;
      final entry = e.value;

      final prevIdx = idxInHistory - 1;
      final prevAbw = prevIdx < 0
          ? service.initialWeight
          : weeklyHistory[prevIdx].abw;
      final prevAbl = prevIdx < 0
          ? service.initialLength
          : weeklyHistory[prevIdx].avgLength;

      return _buildHistoryCard(
        title: 'Week ${idxInHistory + 1}',
        dateLabel: _formatDate(entry.date),
        abw: entry.abw,
        abl: entry.avgLength,
        sampleSize: entry.sampleSize,
        isLatest: idxInRecent == 0,
        icon: const Icon(
          Icons.biotech_rounded,
          size: 18,
          color: AppColors.primary,
        ),
        gainW: entry.abw - prevAbw,
        gainL: entry.avgLength - prevAbl,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          if (!TankService.instance.isInitialized)
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
            ..._buildMainViewCards(),
          ],
        ],
      ),
    );
  }
}
