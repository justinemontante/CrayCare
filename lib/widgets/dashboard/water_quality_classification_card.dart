import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme/app_colors.dart';

/// Displays the latest water-quality classification and its source reading.
class WaterQualityClassificationCard extends StatelessWidget {
  final String predictionStatus;
  final int? classCode;
  final String? classLabel;
  final String? insight;
  final String? recommendation;
  final DateTime? sourceRecordedAt;
  final VoidCallback? onHistoryTap;

  const WaterQualityClassificationCard({
    super.key,
    this.predictionStatus = 'model_not_ready',
    this.classCode,
    this.classLabel,
    this.insight,
    this.recommendation,
    this.sourceRecordedAt,
    this.onHistoryTap,
  });

  bool get _hasClassification =>
      predictionStatus == 'classified' &&
      (classLabel?.trim().isNotEmpty == true || classCode != null);

  bool get _isModelPending => predictionStatus == 'model_not_ready';
  bool get _isAwaitingReading => predictionStatus == 'awaiting_reading';

  _ClassificationStyle get _style {
    if (!_hasClassification) return _ClassificationStyle.waiting;
    return switch (classCode) {
      0 => _ClassificationStyle.critical,
      1 => _ClassificationStyle.poor,
      2 => _ClassificationStyle.good,
      _ => switch (classLabel?.trim().toLowerCase()) {
        'critical' => _ClassificationStyle.critical,
        'poor' => _ClassificationStyle.poor,
        'good' => _ClassificationStyle.good,
        _ => _ClassificationStyle.waiting,
      },
    };
  }

  String get _displayLabel {
    if (_isModelPending) return 'Waiting for model';
    if (_isAwaitingReading) return 'Waiting for next history reading';
    if (predictionStatus == 'insufficient_data') return 'Insufficient data';
    if (predictionStatus == 'unavailable') return 'Result unavailable';
    if (!_hasClassification) return 'Insufficient data';
    final label = classLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return switch (classCode) {
      0 => 'Critical',
      1 => 'Poor',
      2 => 'Optimal',
      _ => 'Unclassified',
    };
  }

  String _formatReadingTime(DateTime? value) {
    if (value == null) return 'Time unavailable';
    final local = value.toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'AM' : 'PM';
    const months = <String>[
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
    return '${months[local.month - 1]} ${local.day}, ${local.year} · '
        '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final hasInsight = insight?.trim().isNotEmpty == true;
    final hasRecommendation = recommendation?.trim().isNotEmpty == true;
    final hasDetails =
        hasInsight ||
        hasRecommendation ||
        _isModelPending ||
        _isAwaitingReading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: _ClassificationIntervalIndicator(),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.darkText.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkText.withValues(alpha: 0.035),
                  blurRadius: 9,
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
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1FAFA),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Image.asset(
                        'assets/images/water_quality_analysis_icon.png',
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Water Quality Classification',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkText,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Machine Learning Analysis',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppColors.subtitleText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: onHistoryTap,
                      icon: const Icon(Icons.history_rounded, size: 13),
                      label: const Text('History'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasClassification ? 'OVERALL QUALITY' : 'STATUS',
                        style: const TextStyle(
                          color: AppColors.subtitleText,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.45,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _displayLabel,
                          key: ValueKey(_displayLabel),
                          style: TextStyle(
                            color: _hasClassification
                                ? style.color
                                : AppColors.mutedText,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_hasClassification && sourceRecordedAt != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Based on reading · ${_formatReadingTime(sourceRecordedAt)}',
                          style: const TextStyle(
                            color: AppColors.subtitleText,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasDetails) ...[
                  const SizedBox(height: 2),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      collapsedShape: const Border(),
                      shape: const Border(),
                      title: Text(
                        hasInsight || hasRecommendation
                            ? 'View insight and recommendation'
                            : 'View details',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      children: [
                        if (_isModelPending)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'A result will appear after a complete sensor-history reading is processed.',
                              style: TextStyle(
                                color: AppColors.subtitleText,
                                fontSize: 10,
                                height: 1.35,
                              ),
                            ),
                          ),
                        if (_isAwaitingReading)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'A new classification appears after the next 10-minute sensor-history reading.',
                              style: TextStyle(
                                color: AppColors.subtitleText,
                                fontSize: 10,
                                height: 1.35,
                              ),
                            ),
                          ),
                        if (hasInsight) ...[
                          const SizedBox(height: 4),
                          _DetailBlock(
                            title: 'INSIGHT',
                            text: insight!.trim(),
                            icon: Icons.insights_outlined,
                          ),
                        ],
                        if (hasRecommendation) ...[
                          const SizedBox(height: 8),
                          _DetailBlock(
                            title: 'RECOMMENDATION',
                            text: recommendation!.trim(),
                            icon: Icons.lightbulb_outline_rounded,
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassificationIntervalIndicator extends StatefulWidget {
  const _ClassificationIntervalIndicator();

  @override
  State<_ClassificationIntervalIndicator> createState() =>
      _ClassificationIntervalIndicatorState();
}

class _ClassificationIntervalIndicatorState
    extends State<_ClassificationIntervalIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dotColor = Color(0xFF22C55E);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final progress = _pulse.value;
            return SizedBox(
              width: 12,
              height: 12,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 0.75 + (progress * 0.65),
                    child: Opacity(
                      opacity: 0.32 * (1 - progress),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 5),
        FadeTransition(
          opacity: Tween<double>(begin: 0.78, end: 1).animate(_pulse),
          child: const Text(
            'Every 10 minutes',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showWaterQualityClassificationHistory(
  BuildContext context, {
  required String tankId,
  DateTime? initialDate,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) =>
        _ClassificationHistorySheet(tankId: tankId, initialDate: initialDate),
  );
}

class _ClassificationHistorySheet extends StatefulWidget {
  final String tankId;
  final DateTime? initialDate;

  const _ClassificationHistorySheet({required this.tankId, this.initialDate});

  @override
  State<_ClassificationHistorySheet> createState() =>
      _ClassificationHistorySheetState();
}

class _ClassificationHistorySheetState
    extends State<_ClassificationHistorySheet> {
  late final List<String> _days;
  String? _selectedDay;
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _cache = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final anchor = widget.initialDate?.toLocal() ?? DateTime.now();
    _days = _buildRecentDays(anchor);
    _selectedDay = _dateKey(anchor);
    _loadEntries(_selectedDay!);
  }

  String _dateKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<String> _buildRecentDays(DateTime anchor) {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final days = List.generate(
      30,
      (index) => _dateKey(base.subtract(Duration(days: index))),
    );
    final initialKey = _dateKey(anchor);
    if (!days.contains(initialKey)) days.insert(0, initialKey);
    return days;
  }

  Future<void> _loadEntries(String dateKey) async {
    if (_cache.containsKey(dateKey)) {
      if (mounted) setState(() {});
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('tanks')
          .doc(widget.tankId)
          .collection('water_quality_classification_history')
          .doc(dateKey)
          .collection('entries')
          .orderBy('source_recorded_at', descending: true)
          .limit(144)
          .get();

      _cache[dateKey] = snap.docs;
    } catch (e) {
      debugPrint('[WQ classification history] error: $e');
      _cache[dateKey] = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectDay(String dateKey) {
    if (_selectedDay == dateKey) return;
    setState(() => _selectedDay = dateKey);
    _loadEntries(dateKey);
  }

  DateTime? _parseDateKey(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  String _dayLabel(String value) {
    final date = _parseDateKey(value);
    if (date == null) return value;
    final today = DateTime.now();
    final localToday = DateTime(today.year, today.month, today.day);
    final diff = localToday.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
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
    return '${months[date.month - 1]} ${date.day}';
  }

  String _timeLabel(dynamic value) {
    final date = value is Timestamp
        ? value.toDate().toLocal()
        : value is DateTime
        ? value.toLocal()
        : null;
    if (date == null) return 'Time unavailable';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
  }

  Color _statusColor(String label) {
    return switch (label.toLowerCase()) {
      'optimal' || 'good' => const Color(0xFF168A52),
      'poor' => const Color(0xFFB7791F),
      'critical' => const Color(0xFFB42318),
      _ => AppColors.mutedText,
    };
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.78;
    return SizedBox(
      height: sheetHeight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryWith(0.14),
                          AppColors.primaryWith(0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: AppColors.primaryWith(0.18),
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/water_quality_analysis_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Classification History',
                          style: TextStyle(
                            color: AppColors.darkText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Random Forest Water Quality Timeline',
                          style: TextStyle(
                            color: AppColors.subtitleText,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.dark.withValues(alpha: 0.035),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _days.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (context, index) {
                      final day = _days[index];
                      final isActive = day == _selectedDay;
                      return GestureDetector(
                        onTap: () => _selectDay(day),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: AppColors.dark.withValues(alpha: 0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 11,
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.dark.withValues(alpha: 0.40),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _dayLabel(day),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? AppColors.primary
                                        : AppColors.dark.withValues(alpha: 0.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _isLoading && !_cache.containsKey(_selectedDay)
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final entries = _cache[_selectedDay] ?? const [];
                          if (entries.isEmpty) {
                            return const Center(
                              child: Text(
                                'No classification results for this date.',
                                style: TextStyle(
                                  color: AppColors.subtitleText,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final data = entries[index].data();
                              final label =
                                  data['class_label']?.toString() ??
                                  (data['prediction_status'] ==
                                          'insufficient_data'
                                      ? 'Insufficient data'
                                      : 'Unclassified');
                              final color = _statusColor(label);
                              final rawInsight =
                                  data['insight']?.toString().trim() ?? '';
                              final insight = rawInsight;
                              final recommendation =
                                  data['recommendation']?.toString().trim() ??
                                  '';
                              return _ClassificationHistoryItem(
                                data: data,
                                label: label,
                                color: color,
                                insight: insight,
                                recommendation: recommendation,
                                timeLabel: _timeLabel,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassificationHistoryItem extends StatefulWidget {
  final Map<String, dynamic> data;
  final String label;
  final Color color;
  final String insight;
  final String recommendation;
  final String Function(dynamic) timeLabel;

  const _ClassificationHistoryItem({
    required this.data,
    required this.label,
    required this.color,
    required this.insight,
    required this.recommendation,
    required this.timeLabel,
  });

  @override
  State<_ClassificationHistoryItem> createState() =>
      _ClassificationHistoryItemState();
}

class _ClassificationHistoryItemState
    extends State<_ClassificationHistoryItem> {
  bool _expanded = false;

  bool get _hasClassification =>
      widget.label == 'Optimal' ||
      widget.label == 'Good' ||
      widget.label == 'Poor' ||
      widget.label == 'Critical';

  @override
  Widget build(BuildContext context) {
    final hasDetails =
        widget.insight.isNotEmpty || widget.recommendation.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.darkText.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkText.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: hasDetails
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasClassification) ...[
                  const Text(
                    'OVERALL QUALITY',
                    style: TextStyle(
                      color: AppColors.subtitleText,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: widget.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.timeLabel(widget.data['source_recorded_at']),
                      style: const TextStyle(
                        color: AppColors.subtitleText,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (hasDetails)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.subtitleText,
                        ),
                      ),
                  ],
                ),
                if (!_expanded && widget.insight.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.insight,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.subtitleText,
                      fontSize: 9.5,
                    ),
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  if (widget.insight.isNotEmpty) ...[
                    _DetailBlock(
                      title: 'INSIGHT',
                      text: widget.insight,
                      icon: Icons.insights_outlined,
                    ),
                  ],
                  if (widget.recommendation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _DetailBlock(
                      title: 'RECOMMENDATION',
                      text: widget.recommendation,
                      icon: Icons.lightbulb_outline_rounded,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String text;
  final IconData icon;

  const _DetailBlock({
    required this.title,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkText.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.subtitleText,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.45,
                  ),
                ),
                const SizedBox(height: 3),
                _buildFormattedText(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattedText(BuildContext context) {
    const defaultStyle = TextStyle(
      color: AppColors.darkText,
      fontSize: 10,
      height: 1.35,
    );

    final match = RegExp(r'(?:\n+)?\bRecent [Tt]rend:\s*').firstMatch(text);
    if (match != null) {
      final before = text.substring(0, match.start).trimRight();
      final after = text.substring(match.end).trim();
      return Text.rich(
        TextSpan(
          style: defaultStyle,
          children: [
            if (before.isNotEmpty) TextSpan(text: before),
            if (before.isNotEmpty) const TextSpan(text: '\n\n'),
            const TextSpan(
              text: 'Recent Trend: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
              ),
            ),
            TextSpan(text: after),
          ],
        ),
      );
    }

    return Text(
      text,
      style: defaultStyle,
    );
  }
}

class _ClassificationStyle {
  final Color color;

  const _ClassificationStyle(this.color);

  static const good = _ClassificationStyle(Color(0xFF168A52));
  static const poor = _ClassificationStyle(Color(0xFFB7791F));
  static const critical = _ClassificationStyle(Color(0xFFB42318));
  static const waiting = _ClassificationStyle(AppColors.mutedText);
}
