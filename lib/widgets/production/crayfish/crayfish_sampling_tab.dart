import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_colors.dart';
import '../../../services/tank_service.dart';
import '../../../utils/snackbar_helper.dart';

class SamplingTab extends StatelessWidget {
  final DateTime lastEdited;

  const SamplingTab({
    super.key,
    required this.lastEdited,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!TankService.instance.isInitialized)
            _buildEmptyState()
          else ...[
            _buildSectionHeader(),
            const SizedBox(height: 8),
            NextSamplingPanel(),
            const SizedBox(height: 12),
            GrowthOverviewPanel(),
            const SizedBox(height: 12),
            SamplingFormPanel(),
            const SizedBox(height: 12),
          ],
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
            'Record Sampling',
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
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.speed_rounded,
              size: 32,
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
          const SizedBox(height: 12),
        ],
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
    final nextWeekNum = service.samplingHistory.where((e) => !e.isBaseline).length;

    return Container(
      width: double.infinity,
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
          // ── Header Row inside container ──
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 8),
              const Text(
                'Sampling Schedule',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
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
                  'Week $nextWeekNum',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: AppColors.dark.withValues(alpha: 0.05)),
          const SizedBox(height: 12),

          // ── Details Row (Clean, Non-Redundant) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next Session',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.45),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    daysRemaining == 0
                        ? 'Today (Due)'
                        : _formatDate(DateTime.now().add(Duration(days: daysRemaining))),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Time Remaining',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.45),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    daysRemaining == 0
                        ? 'Ready to record'
                        : '$daysRemaining days left',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
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

  void _showModal(
    BuildContext context,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color iconColor,
    Color iconBgColor,
    String description,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dark.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.dark.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      width: double.infinity,
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
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMiniCard(
                  'Initial Baseline',
                  _formatDate(service.stockingDate),
                  initialW,
                  initialL,
                  false,
                  () => _showModal(
                    context,
                    'Initial Baseline',
                    'ABW: ${initialW.toStringAsFixed(2)} g  |  ABL: ${initialL.toStringAsFixed(2)} cm',
                    'Stocked on ${_formatDate(service.stockingDate)}',
                    Icons.calendar_today_outlined,
                    const Color(0xFF0891B2),
                    const Color(0xFFECFEFF),
                    'These are the initial size measurements of the crayfish recorded at grow-out initialization. They serve as the starting baseline for growth rates and population development.',
                  ),
                ),
                const SizedBox(width: 12),
                hasWeeklySampling
                    ? _buildMiniCard(
                        'Latest Sampling',
                        _formatDate(latest!.date),
                        latestW,
                        latestL,
                        true,
                        () => _showModal(
                          context,
                          'Latest Sampling',
                          'ABW: ${latestW.toStringAsFixed(2)} g  |  ABL: ${latestL.toStringAsFixed(2)} cm',
                          'Recorded on ${_formatDate(latest.date)}',
                          Icons.science_outlined,
                          const Color(0xFF0F766E),
                          const Color(0xFFF0FDFA),
                          'This represents the most recent growth measurements. Regular updates help track weekly changes in Average Body Weight and Average Body Length.',
                        ),
                      )
                    : _buildAwaitingCard(
                        () => _showModal(
                          context,
                          'Latest Sampling',
                          'Awaiting Week 1',
                          'Pending session',
                          Icons.hourglass_empty_rounded,
                          AppColors.darkWith(0.35),
                          AppColors.darkWith(0.06),
                          'No weekly growth data has been recorded yet. The app is waiting for your Week 1 sampling session to begin compiling growth rates.',
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildGrowthFullCard(
            diffW,
            diffL,
            () => _showModal(
              context,
              'Growth Change',
              'Weight: ${diffW >= 0 ? "+" : ""}${diffW.toStringAsFixed(2)} g  |  Length: ${diffL >= 0 ? "+" : ""}${diffL.toStringAsFixed(2)} cm',
              'Total Gain since Stocking',
              Icons.trending_up_rounded,
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.1),
              'This illustrates the overall change in average crayfish weight and length since grow-out stocking initialization.',
            ),
          ),
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
    VoidCallback onTap,
  ) {
    final iconColor = isLatest ? const Color(0xFF0F766E) : const Color(0xFF0891B2);
    final iconBgColor = isLatest ? const Color(0xFFF0FDFA) : const Color(0xFFECFEFF);
    final iconData = isLatest ? Icons.science_outlined : Icons.calendar_today_outlined;
    final titleColor = isLatest ? const Color(0xFF0F766E) : const Color(0xFF0891B2);

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon centered at top ──
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, size: 16, color: iconColor),
                  ),
                  const SizedBox(height: 6),
                  // ── Title & subtitle centered ──
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Full-width divider ──
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: AppColors.dark.withValues(alpha: 0.06),
                  ),
                  const SizedBox(height: 8),
                  // ── ABW and ABL inline ──
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'ABW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkWith(0.45),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${weight.toStringAsFixed(2)} g',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // vertical separator
                        Container(
                          width: 1,
                          color: AppColors.dark.withValues(alpha: 0.08),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'ABL',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkWith(0.45),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${length.toStringAsFixed(2)} cm',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAwaitingCard(VoidCallback onTap) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dark.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppColors.darkWith(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Icon centered at top ──
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FDFA),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── Title & subtitle centered ──
                  const Text(
                    'Latest Sampling',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pending',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Full-width divider ──
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: AppColors.dark.withValues(alpha: 0.06),
                  ),
                  const SizedBox(height: 8),
                  // ── Centered awaiting placeholder ──
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_empty_rounded,
                            size: 20,
                            color: AppColors.darkWith(0.2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Awaiting Week 1',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkWith(0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrowthFullCard(double weight, double length, VoidCallback onTap) {
    final isPosW = weight >= 0;
    final isPosL = length >= 0;
    return Container(
      width: double.infinity,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          ),
        ),
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

  void _showHistoryModal() {
    final service = TankService.instance;
    final history = service.samplingHistory.where((e) => !e.isBaseline).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                  const Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('Sampling History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                  const Spacer(),
                  Text('${history.length} recorded', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.5))),
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
                        Icon(Icons.inbox_rounded, size: 40, color: AppColors.dark.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text('No sampling records yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dark.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: history.reversed.map((e) => _buildModalHistoryCard(e)).toList(),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalHistoryCard(SamplingEntry entry) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[entry.date.month - 1]} ${entry.date.day}, ${entry.date.year}';
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
              child: const Icon(Icons.biotech_rounded, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  const SizedBox(height: 4),
                  Text('${entry.sampleSize} sampled | ABW: ${entry.abw.toStringAsFixed(2)}g | ABL: ${entry.avgLength.toStringAsFixed(1)}cm',
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

  void _revalidateCount() {
    final count = int.tryParse(_countController.text) ?? 0;
    final maxSample = TankService.instance.inTankCount;
    if (count > 0 && maxSample > 0 && count > maxSample) {
      setState(() => _countError = 'Exceeds live count ($maxSample)');
    } else {
      setState(() => _countError = null);
    }
  }

  void _handleCompute() {
    if (!TankService.instance.canSample && !_isEditing) {
      showBeautifulSnackbar(context, '7-day cooldown not yet over. Please wait.', false);
      return;
    }
    _revalidateCount();
    if (_countError != null) return;

    final count = int.tryParse(_countController.text);
    final weight = double.tryParse(_weightController.text);
    final length = double.tryParse(_lengthController.text);

    if (count == null || weight == null || length == null || count <= 0 || weight <= 0 || length <= 0) {
      showBeautifulSnackbar(context, 'All sampling values must be positive numbers.', false);
      return;
    }
    {
      final wasEditing = _isEditing;
      final service = TankService.instance;
      final history = service.samplingHistory;

      // Get previous values to compare against
      final lastEntry = (wasEditing && history.length > 1)
          ? history[history.length - 2]
          : (history.isNotEmpty ? history.last : null);

      final lastTotalWeight = lastEntry != null ? lastEntry.totalWeight : service.initialTotalWeight;
      final lastTotalLength = lastEntry != null ? lastEntry.totalLength : service.initialTotalLength;

      final List<String> errors = [];
      if (weight < lastTotalWeight) {
        errors.add('weight must be at least ${lastTotalWeight.toStringAsFixed(1)} g');
      }
      if (length < lastTotalLength) {
        errors.add('length must be at least ${lastTotalLength.toStringAsFixed(1)} cm');
      }

      if (errors.isNotEmpty) {
        final errorMsg = 'Sample ${errors.join(' and ')}';
        showBeautifulSnackbar(
          context,
          errorMsg,
          false,
        );
        return;
      }

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
    final lastEntryIsToday = service.samplingHistory.isNotEmpty
        ? _isToday(service.samplingHistory.last.date)
        : false;

    return Container(
      width: double.infinity,
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
                'Record Sampling',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  if (_isRecorded && lastEntryIsToday) ...[
                    const SizedBox(width: 6),
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
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                      onPressed: _countError == null ? _handleCompute : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _countError == null
                            ? AppColors.primary
                            : AppColors.dark.withValues(alpha: 0.2),
                        foregroundColor: _countError == null
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
                      child: const Text(
                        'Compute Results',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
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
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.only(top: 20),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
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
          ),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.darkWith(0.06),
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
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
          ),

          const SizedBox(height: 16),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
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
                  AppColors.primary,
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
