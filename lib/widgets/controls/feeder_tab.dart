import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../models/control_types.dart';
import '../../utils/snackbar_helper.dart';

class FeederTab extends StatelessWidget {
  // Feeder schedules are anchored to Asia/Manila wall-clock time to match the
  // ESP32's NTP-synced clock and the Cloud Function's MANILA_OFFSET_MS. Using
  // DateTime.now() here compares against the device timezone, which can cause
  // false "missed"/"completed" states when the phone is abroad.
  static DateTime _manilaNow() => manilaWallClock();

  final List<ScheduleItem> schedules;
  final TextEditingController timeCtl;
  final VoidCallback onFeedNow;
  final Future<bool> Function(double? grams, String days) onAddSchedule;
  final void Function(int index) onDeleteSchedule;
  final void Function(int index, ScheduleItem item) onEditSchedule;
  final void Function(int index, bool enabled) onToggleSchedule;
  final List<LogEntry> feederLogs;
  final Set<String> fedToday;

  final bool isOnline;
  final bool isRunning;
  final String feederStatus;
  final bool canFeed;
  final String feedBlockedReason;
  final double? feedLevelPercent;
  final double? estimatedFeedGrams;
  final double consumptionTodayGrams;
  final int completedFeedingsToday;

  const FeederTab({
    super.key,
    required this.schedules,
    required this.timeCtl,
    required this.onFeedNow,
    required this.onAddSchedule,
    required this.onDeleteSchedule,
    required this.onEditSchedule,
    required this.onToggleSchedule,
    required this.feederLogs,
    this.fedToday = const {},
    this.isOnline = true,
    this.isRunning = false,
    this.feederStatus = 'idle',
    this.canFeed = true,
    this.feedBlockedReason = '',
    this.feedLevelPercent,
    this.estimatedFeedGrams,
    this.consumptionTodayGrams = 0,
    this.completedFeedingsToday = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildFeederCardBody(context),
    );
  }

  Widget _buildFeederCardBody(BuildContext ctx) {
    final morning = schedules.where((s) => s.ampm == 'AM').toList();
    final afternoon = schedules.where((s) => s.ampm == 'PM').toList();
    final hasEnabledSchedules = schedules.any((s) => s.enabled);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.15), width: 1.5),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/images/FeedingImage.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Automatic Feeder',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _showFeederLog(ctx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 11,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Log',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: hasEnabledSchedules
                                  ? AppColors.success
                                  : AppColors.darkWith(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            switch (feederStatus) {
                              'checking_feed_level' => 'Checking Feed Level',
                              'dispensing' => 'Dispensing',
                              'completed' => 'Completed',
                              'skipped_insufficient' =>
                                'Skipped • Insufficient Feed',
                              'blocked' => 'Feed Blocked',
                              _ =>
                                schedules.isEmpty
                                    ? 'Auto Mode • No Schedules'
                                    : hasEnabledSchedules
                                    ? 'Auto Mode • Ready'
                                    : 'Auto Mode • Paused',
                            },
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color:
                                  feederStatus == 'skipped_insufficient' ||
                                      feederStatus == 'blocked'
                                  ? AppColors.critical
                                  : hasEnabledSchedules
                                  ? AppColors.success
                                  : AppColors.darkWith(0.4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFeedInventorySummary(),
            if (schedules.isNotEmpty) _buildCountdown(),
            const SizedBox(height: 12),
            _buildFeedNowButton(ctx),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Schedules:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showScheduleModal(ctx),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 10, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          'Add Schedule',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
              ],
            ),
            if (schedules.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSchedulePeriod(
                ctx,
                'Morning',
                Icons.wb_sunny_outlined,
                morning,
              ),
              const SizedBox(height: 12),
              _buildSchedulePeriod(
                ctx,
                'Afternoon',
                Icons.wb_twilight_outlined,
                afternoon,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.schedule_send_outlined,
                        size: 28,
                        color: AppColors.darkWith(0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No schedules yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkWith(0.4),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap above to add a feeding schedule',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.darkWith(0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedInventorySummary() {
    final now = _manilaNow();
    final nextOccurrence = nextEnabledFeeding(schedules, now);
    final nextGrams = nextOccurrence?.schedule.grams ?? defaultFeederGrams;
    final level = feedLevelPercent;
    final available = estimatedFeedGrams;
    final hasLevel = level != null && available != null;
    final availableValue = available ?? 0.0;
    final enoughForNext = hasLevel && availableValue + 0.5 >= nextGrams;
    final tomorrow = now.add(const Duration(days: 1));
    final endOfTomorrow = DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      23,
      59,
      59,
    );
    var requiredThroughTomorrow = 0.0;
    for (var dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final day = DateTime(now.year, now.month, now.day + dayOffset);
      for (final schedule in schedules) {
        if (!feederScheduleRunsOnDate(schedule, day)) continue;
        final minutes = feederScheduleMinutes(schedule);
        final occurrence = DateTime(
          day.year,
          day.month,
          day.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (!occurrence.isAfter(now) || occurrence.isAfter(endOfTomorrow)) {
          continue;
        }
        requiredThroughTomorrow += schedule.grams ?? defaultFeederGrams;
      }
    }

    Color levelColor = AppColors.darkWith(0.35);
    String levelLabel = 'Waiting for sensor';
    if (level != null) {
      if (level <= 0) {
        levelColor = AppColors.critical;
        levelLabel = 'Empty';
      } else if (level <= 10) {
        levelColor = AppColors.critical;
        levelLabel = 'Critical Feed Level';
      } else if (level <= 20) {
        levelColor = AppColors.warning;
        levelLabel = 'Low Feed';
      } else {
        levelColor = AppColors.success;
        levelLabel = 'Normal';
      }
    }

    String availabilityText;
    Color availabilityColor;
    IconData availabilityIcon;
    if (!hasLevel) {
      availabilityText = 'Feed availability is not available yet';
      availabilityColor = AppColors.darkWith(0.45);
      availabilityIcon = Icons.sensors_off_outlined;
    } else if (nextOccurrence == null) {
      availabilityText = 'No upcoming feeding to evaluate';
      availabilityColor = AppColors.darkWith(0.5);
      availabilityIcon = Icons.event_available_outlined;
    } else if (enoughForNext &&
        availableValue + 0.5 < requiredThroughTomorrow) {
      final shortBy = requiredThroughTomorrow - availableValue;
      availabilityText =
          'Refill reminder: ~${availableValue.toStringAsFixed(0)}g available, ${requiredThroughTomorrow.toStringAsFixed(0)}g needed through tomorrow (short ${shortBy.toStringAsFixed(0)}g)';
      availabilityColor = AppColors.warning;
      availabilityIcon = Icons.inventory_outlined;
    } else if (enoughForNext) {
      availabilityText = level <= 10
          ? 'Critical level, but feed can still proceed'
          : 'Feed available for next feeding';
      availabilityColor = level <= 10 ? AppColors.warning : AppColors.success;
      availabilityIcon = Icons.check_circle_outline;
    } else {
      availabilityText =
          'Insufficient: ~${availableValue.toStringAsFixed(0)}g available • ${nextGrams.toStringAsFixed(0)}g required';
      availabilityColor = AppColors.critical;
      availabilityIcon = Icons.error_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryWith(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryWith(0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _inventoryMetric(
                  Icons.inventory_2_outlined,
                  'Feed Level',
                  level == null ? '--' : '${level.toStringAsFixed(0)}%',
                  levelLabel,
                  levelColor,
                ),
              ),
              Container(width: 1, height: 46, color: AppColors.darkWith(0.08)),
              Expanded(
                child: _inventoryMetric(
                  Icons.scale_outlined,
                  'Consumption Today',
                  '${consumptionTodayGrams.toStringAsFixed(0)} g',
                  '$completedFeedingsToday completed',
                  AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: availabilityColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(availabilityIcon, size: 14, color: availabilityColor),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    availabilityText,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: availabilityColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inventoryMetric(
    IconData icon,
    String label,
    String value,
    String detail,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: AppColors.darkWith(0.45),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.dark,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedNowButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: !canFeed && isOnline ? feedBlockedReason : '',
        decoration: BoxDecoration(
          color: AppColors.critical,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        waitDuration: const Duration(milliseconds: 100),
        child: ElevatedButton(
          onPressed: isOnline && !isRunning && canFeed
              ? onFeedNow
              : () {
                  if (!isOnline) {
                    showBeautifulSnackbar(
                      context,
                      'Feeder is offline. Cannot dispense feed.',
                      false,
                      title: 'Feeder Offline',
                    );
                  } else if (!canFeed) {
                    showBeautifulSnackbar(
                      context,
                      feedBlockedReason,
                      false,
                      title: 'Feed Blocked',
                    );
                  }
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: isOnline
                ? AppColors.primary
                : Colors.grey.shade300,
            foregroundColor: isOnline ? Colors.white : Colors.grey.shade500,
            padding: const EdgeInsets.symmetric(vertical: 11),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRunning
                    ? Icons.hourglass_top
                    : !isOnline
                    ? Icons.wifi_off
                    : !canFeed
                    ? Icons.block
                    : Icons.play_arrow,
                size: 14,
                color: isOnline ? Colors.white : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                isRunning
                    ? 'Feeding...'
                    : !isOnline
                    ? 'Feeder Offline'
                    : !canFeed
                    ? 'Feed Blocked'
                    : 'Feed Now',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isOnline ? Colors.white : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = _manilaNow();

        final statuses = <ScheduleItem, String>{
          for (final schedule in schedules) schedule: _scheduleStatus(schedule),
        };
        final nextOccurrence = nextEnabledFeeding(
          schedules,
          now,
          skipToday: (schedule) => statuses[schedule] == 'completed',
        );
        final next = nextOccurrence?.schedule;
        final nextAt = nextOccurrence?.at;

        final bool noUpcoming = next == null || nextAt == null;

        String? display;
        String? scheduleLabel;
        if (!noUpcoming) {
          display = _formatDuration(nextAt.difference(now));
          scheduleLabel =
              '${next.time} ${next.ampm} • ${_scheduleDayLabel(nextAt, now)}';
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.darkWith(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  noUpcoming ? Icons.info_outline : Icons.timer_outlined,
                  size: 14,
                  color: noUpcoming
                      ? AppColors.darkWith(0.4)
                      : AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    noUpcoming
                        ? 'No enabled feeding schedule'
                        : 'Next: $scheduleLabel',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ),
                if (display != null)
                  Text(
                    display,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final h = d.inHours.remainder(24);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (h > 0) parts.add('${h}h');
    parts.add('${m}m');
    parts.add('${s}s');
    return parts.join(' ');
  }

  String _scheduleDayLabel(DateTime target, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);
    final dayOffset = targetDay.difference(today).inDays;
    if (dayOffset == 0) return 'Today';
    if (dayOffset == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[target.weekday - 1];
  }

  String _logDateString() {
    final now = _manilaNow();
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
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  /// Converts a day mask ("1111111") into a readable label like
  /// "Every day", "Weekdays", or "Mon, Wed, Fri".
  String _formatDays(String days) {
    if (days.length < 7) return 'Every day';
    if (days == '1111111') return 'Every day';
    if (days == '0111110') return 'Weekdays';
    if (days == '1000001') return 'Weekends';
    final labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final parts = <String>[];
    for (var i = 0; i < 7; i++) {
      if (days[i] == '1') parts.add(labels[i]);
    }
    if (parts.isEmpty) return 'No days';
    return parts.join(', ');
  }

  String _scheduleStatus(ScheduleItem s) {
    if (!s.enabled) return 'disabled';
    // Not active today → show as "off today" (not due).
    final now = _manilaNow();
    if (!feederScheduleRunsOnDate(s, now)) return 'off_today';
    if (s.isDone) return 'completed';
    final key = '${s.time}_${s.ampm}';
    if (fedToday.contains(key)) return 'completed';
    final scheduleTimeStr = '${s.time} ${s.ampm}';
    final todayStr = _logDateString();
    for (final log in feederLogs) {
      final a = log.action.toLowerCase();
      if ((a.contains('dispensed feed (scheduled)') ||
              a.contains('auto feed dispensed')) &&
          log.time == scheduleTimeStr &&
          log.date == todayStr) {
        return 'completed';
      }
    }
    for (final log in feederLogs) {
      if (log.type == 'missed' &&
          s.id != null &&
          log.scheduleKey == s.id &&
          log.scheduleTime == scheduleTimeStr &&
          log.date == todayStr) {
        return 'missed';
      }
    }
    final minutes = feederScheduleMinutes(s);
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    if (!feederScheduleWasEffectiveAt(s, scheduleDt)) return 'upcoming';
    if (now.isBefore(scheduleDt)) return 'upcoming';
    return 'pending';
  }

  Widget _buildSchedulePeriod(
    BuildContext ctx,
    String label,
    IconData icon,
    List<ScheduleItem> items,
  ) {
    const previewLimit = 2;
    final previewItems = items.take(previewLimit).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ],
              ),
              Text(
                '${items.length} schedule${items.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkWith(0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                'No schedules set',
                style: TextStyle(fontSize: 10, color: AppColors.darkWith(0.3)),
              ),
            )
          else
            ...previewItems.map(
              (s) => _buildScheduleItem(ctx, schedules.indexOf(s), s),
            ),
          if (items.length > previewLimit) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _showAllSchedules(ctx, label, icon, items),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                label: Text('View all ${items.length} schedules'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.07),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAllSchedules(
    BuildContext ctx,
    String label,
    IconData icon,
    List<ScheduleItem> items,
  ) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FractionallySizedBox(
        heightFactor: 0.76,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkWith(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 19, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$label Schedules',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.dark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${items.length} feeding schedule${items.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.darkWith(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.darkWith(0.55),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.darkWith(0.08)),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 5),
                      itemBuilder: (_, itemIndex) {
                        final schedule = items[itemIndex];
                        return _buildScheduleItem(
                          sheetCtx,
                          schedules.indexOf(schedule),
                          schedule,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleItem(BuildContext ctx, int index, ScheduleItem s) {
    final status = _scheduleStatus(s);
    Color bgColor;
    Color borderColor;
    Color dotColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        bgColor = AppColors.success.withValues(alpha: 0.08);
        borderColor = Colors.transparent;
        dotColor = AppColors.success;
        statusLabel = 'Completed';
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        borderColor = AppColors.warning.withValues(alpha: 0.25);
        dotColor = AppColors.warning;
        statusLabel = 'Pending';
        statusIcon = Icons.hourglass_bottom;
        break;
      case 'missed':
        bgColor = AppColors.darkWith(0.06);
        borderColor = AppColors.darkWith(0.15);
        dotColor = AppColors.darkWith(0.4);
        statusLabel = 'Missed';
        statusIcon = Icons.error_outline;
        break;
      case 'off_today':
        bgColor = AppColors.darkWith(0.03);
        borderColor = AppColors.darkWith(0.1);
        dotColor = AppColors.darkWith(0.35);
        statusLabel = 'Off today';
        statusIcon = Icons.event_busy;
        break;
      case 'disabled':
        bgColor = AppColors.darkWith(0.05);
        borderColor = AppColors.darkWith(0.12);
        dotColor = AppColors.darkWith(0.4);
        statusLabel = 'Paused';
        statusIcon = Icons.pause_circle_outline;
        break;
      default:
        bgColor = Colors.white;
        borderColor = AppColors.darkWith(0.08);
        dotColor = AppColors.primaryWith(0.5);
        statusLabel = 'Upcoming';
        statusIcon = Icons.schedule;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(statusIcon, size: 11, color: dotColor),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.time} ${s.ampm}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: status == 'disabled'
                          ? AppColors.darkWith(0.4)
                          : AppColors.dark,
                      decoration: status == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppColors.darkWith(0.3),
                    ),
                  ),
                  if (s.grams != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      '${s.grams!.toStringAsFixed(1)}g',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 1),
                  Text(
                    _formatDays(s.days),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: AppColors.darkWith(0.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: status == 'completed'
                        ? AppColors.success.withValues(alpha: 0.15)
                        : status == 'pending'
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : status == 'missed'
                        ? AppColors.darkWith(0.1)
                        : AppColors.darkWith(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: status == 'completed'
                          ? AppColors.success
                          : status == 'pending'
                          ? const Color(0xFFc97d08)
                          : AppColors.darkWith(0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 30,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Switch(
                          value: s.enabled,
                          activeTrackColor: AppColors.primary,
                          onChanged: (val) => onToggleSchedule(index, val),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: PopupMenuButton<String>(
                        tooltip: 'Schedule actions',
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: AppColors.darkWith(0.55),
                        ),
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showScheduleModal(ctx, index: index, existing: s);
                          } else if (action == 'delete') {
                            _confirmDelete(ctx, index);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 10),
                                Text('Edit schedule'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppColors.critical,
                                ),
                                SizedBox(width: 10),
                                Text('Delete schedule'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, int index) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, size: 20, color: AppColors.critical),
            SizedBox(width: 8),
            Text(
              'Delete Schedule',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to delete this schedule?',
          style: TextStyle(fontSize: 12, color: AppColors.dark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onDeleteSchedule(index);
            },
            child: const Text(
              'Delete',
              style: TextStyle(
                color: AppColors.critical,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFeederLog(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.5,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
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
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            'assets/images/FeedingImage.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Feeder Log',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          Text(
                            'Recent feeding activity',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.darkWith(0.45),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: feederLogs.isEmpty
                        ? Center(
                            child: Text(
                              'No activity yet.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.darkWith(0.35),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: feederLogs
                                  .take(20)
                                  .map(
                                    (l) => Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.darkWith(0.03),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color:
                                                  l.status ==
                                                          'skipped_insufficient' ||
                                                      l.status == 'blocked' ||
                                                      l.status == 'failed' ||
                                                      l.type == 'error'
                                                  ? AppColors.critical
                                                  : l.type == 'auto'
                                                  ? AppColors.primary
                                                  : AppColors.warning,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  l.action,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.dark,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  '${l.date} \u00B7 ${l.time}',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    color: AppColors.darkWith(
                                                      0.4,
                                                    ),
                                                  ),
                                                ),
                                                if (l.requestedGrams !=
                                                    null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    [
                                                      'Required ${l.requestedGrams!.toStringAsFixed(0)}g',
                                                      if (l.estimatedAvailableGrams !=
                                                          null)
                                                        'Available ~${l.estimatedAvailableGrams!.toStringAsFixed(0)}g',
                                                      if (l.feedLevelBefore !=
                                                          null)
                                                        'Before ${l.feedLevelBefore!.toStringAsFixed(0)}%',
                                                      if (l.feedLevelAfter !=
                                                          null)
                                                        'After ${l.feedLevelAfter!.toStringAsFixed(0)}%',
                                                    ].join('  •  '),
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      height: 1.35,
                                                      color: AppColors.darkWith(
                                                        0.55,
                                                      ),
                                                    ),
                                                  ),
                                                  if (l.status == 'completed' &&
                                                      l.levelChangeDetected ==
                                                          false)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 3,
                                                          ),
                                                      child: Text(
                                                        'Possible dispense issue: no detectable level change',
                                                        style: TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              AppColors.warning,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showScheduleModal(
    BuildContext ctx, {
    int? index,
    ScheduleItem? existing,
  }) {
    final isEdit = existing != null;
    TimeOfDay selectedTime;
    if (isEdit) {
      int h = int.tryParse(existing.time.split(':')[0]) ?? 6;
      final m = int.tryParse(existing.time.split(':')[1]) ?? 0;
      if (existing.ampm == 'PM' && h != 12) h += 12;
      if (existing.ampm == 'AM' && h == 12) h = 0;
      selectedTime = TimeOfDay(hour: h, minute: m);
    } else {
      selectedTime = const TimeOfDay(hour: 6, minute: 0);
    }
    final gramsCtl = TextEditingController(
      text: existing?.grams != null ? existing!.grams!.toStringAsFixed(1) : '',
    );
    // Day-of-week mask, Sunday first: index 0..6. Default = every day.
    final selectedDays = <int>{
      for (var i = 0; i < 7; i++)
        if (existing == null ||
            existing.days.length <= i ||
            existing.days[i] == '1')
          i,
    };
    var isSaving = false;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            String? gramsError;
            if (gramsCtl.text.isNotEmpty) {
              final v = double.tryParse(gramsCtl.text);
              if (v == null) {
                gramsError = 'Enter a valid number';
              } else if (v <= 0) {
                gramsError = 'Grams must be greater than 0';
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isEdit ? 'Edit Schedule' : 'Add Schedule',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.dark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Time picker
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: sheetCtx,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setSheetState(() => selectedTime = picked);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.darkWith(0.15)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            selectedTime.format(sheetCtx),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark,
                            ),
                          ),
                          Icon(
                            Icons.access_time,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Grams field
                  TextField(
                    controller: gramsCtl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Grams (optional)',
                      hintText: 'e.g. 50',
                      suffixText: 'g',
                      errorText: gramsError,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.darkWith(0.15),
                          width: 1.5,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.critical,
                          width: 1.5,
                        ),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.critical,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Days of the week selector (alarm-clock style)
                  Text(
                    'Repeat on',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (i) {
                      final on = selectedDays.contains(i);
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          if (on) {
                            selectedDays.remove(i);
                          } else {
                            selectedDays.add(i);
                          }
                        }),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on ? AppColors.primary : Colors.transparent,
                            border: Border.all(
                              color: on
                                  ? AppColors.primary
                                  : AppColors.darkWith(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][i],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: on
                                  ? Colors.white
                                  : AppColors.darkWith(0.5),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (selectedDays.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Select at least one day',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.critical,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: gramsError != null || selectedDays.isEmpty || isSaving
                          ? null
                          : () async {
                              final h = selectedTime.hour;
                              final m = selectedTime.minute;
                              final ampm = h >= 12 ? 'PM' : 'AM';
                              final h12 = h % 12 == 0 ? 12 : h % 12;
                              final timeStr =
                                  '$h12:${m.toString().padLeft(2, '0')}';
                              final grams = double.tryParse(gramsCtl.text);
                              final daysMask = String.fromCharCodes(
                                List.generate(
                                  7,
                                  (i) => selectedDays.contains(i) ? 49 : 48,
                                ),
                              );
                              final requested = ScheduleItem(
                                timeStr,
                                ampm,
                                grams: grams,
                                days: daysMask,
                              );
                              ScheduleItem? conflict;
                              for (final e in schedules.asMap().entries) {
                                if (isEdit && e.key == index) continue;
                                final s = e.value;
                                if (feederSchedulesConflict(requested, s)) {
                                  conflict = s;
                                  break;
                                }
                              }
                              if (conflict != null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      feederScheduleConflictMessage(
                                        requested,
                                        conflict,
                                      ),
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: AppColors.critical,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              if (isEdit) {
                                onEditSchedule(
                                  index!,
                                  ScheduleItem(
                                    timeStr,
                                    ampm,
                                    grams: grams,
                                    days: daysMask,
                                  ),
                                );
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              } else {
                                timeCtl.text = '$timeStr:$ampm';
                                setSheetState(() => isSaving = true);
                                final saved = await onAddSchedule(grams, daysMask);
                                if (!sheetCtx.mounted) return;
                                if (!saved) {
                                  setSheetState(() => isSaving = false);
                                  return;
                                }
                                Navigator.pop(sheetCtx);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.grey.shade500,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEdit ? 'Save' : 'Add',
                              style: const TextStyle(
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
      },
    );
  }
}
