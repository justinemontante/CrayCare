import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/control_types.dart';

class FeederTab extends StatelessWidget {
  final bool feederAuto;
  final List<ScheduleItem> schedules;
  final TextEditingController timeCtl;
  final VoidCallback onToggleFeeder;
  final VoidCallback onFeedNow;
  final VoidCallback onAddSchedule;
  final void Function(int index) onDeleteSchedule;
  final void Function(int index, ScheduleItem item) onEditSchedule;
  final List<LogEntry> feederLogs;
  final Set<String> fedToday;

  const FeederTab({
    super.key,
    required this.feederAuto,
    required this.schedules,
    required this.timeCtl,
    required this.onToggleFeeder,
    required this.onFeedNow,
    required this.onAddSchedule,
    required this.onDeleteSchedule,
    required this.onEditSchedule,
    required this.feederLogs,
    this.fedToday = const {},
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

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/images/FeedingImage.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Automatic Feeder',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dark,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _showFeederLog(ctx),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history, size: 11, color: AppColors.primary),
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
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: feederAuto
                                  ? AppColors.success
                                  : AppColors.darkWith(0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            feederAuto ? 'Auto Mode' : 'Manual Mode',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: feederAuto
                                  ? AppColors.success
                                  : AppColors.darkWith(0.4),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onToggleFeeder,
                            child: Container(
                              width: 36,
                              height: 20,
                              decoration: BoxDecoration(
                                color: feederAuto
                                    ? AppColors.primary
                                    : AppColors.darkWith(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 200),
                                alignment: feederAuto
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  margin: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (schedules.isNotEmpty) _buildCountdown(),
            if (feederAuto) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Schedules:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showScheduleModal(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 12, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Add Schedule',
                            style: TextStyle(
                              fontSize: 10,
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
              const SizedBox(height: 12),
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
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onFeedNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Feed Now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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

  Widget _buildCountdown() {
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = DateTime.now();
        final nowMin = now.hour * 60 + now.minute;

        ScheduleItem? next;
        for (final s in schedules) {
          final sMin = _toScheduleMinutes(s);
          if (sMin > nowMin) {
            next = s;
            break;
          }
        }

        String display;
        if (next == null) {
          display = 'No upcoming feeding';
        } else {
          int h = int.parse(next.time.split(':')[0]);
          final m = int.parse(next.time.split(':')[1]);
          if (next.ampm == 'PM' && h != 12) h += 12;
          if (next.ampm == 'AM' && h == 12) h = 0;
          final target = DateTime(now.year, now.month, now.day, h, m);
          final diff = target.difference(now);
          if (diff.isNegative) {
            final nextDay = target.add(const Duration(days: 1));
            final diff2 = nextDay.difference(now);
            display = _formatDuration(diff2);
          } else {
            display = _formatDuration(diff);
          }
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkWith(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Next feeding in  ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkWith(0.6),
                  ),
                ),
                Text(
                  display,
                  style: const TextStyle(
                    fontSize: 13,
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
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    parts.add('${m}m');
    parts.add('${s}s');
    return parts.join(' ');
  }

  int _toScheduleMinutes(ScheduleItem s) {
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }

  String _scheduleStatus(ScheduleItem s) {
    final key = '${s.time}_${s.ampm}';
    if (fedToday.contains(key)) return 'completed';
    final now = DateTime.now();
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    final diffSec = now.difference(scheduleDt).inSeconds;
    if (diffSec > 30) return 'completed';
    if (diffSec >= 0) return 'pending';
    return 'upcoming';
  }

  Widget _buildSchedulePeriod(
    BuildContext ctx,
    String label,
    IconData icon,
    List<ScheduleItem> items,
  ) {
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
            ...items.map(
              (s) => _buildScheduleItem(
                ctx,
                schedules.indexWhere((x) => x.time == s.time && x.ampm == s.ampm),
                s,
              ),
            ),
        ],
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
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, size: 12, color: dotColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.time} ${s.ampm}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                        decoration: status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.darkWith(0.3),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status == 'completed'
                          ? AppColors.success.withValues(alpha: 0.15)
                          : status == 'pending'
                          ? AppColors.warning.withValues(alpha: 0.15)
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showScheduleModal(ctx, index: index, existing: s),
            child: Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onDeleteSchedule(index),
            child: Icon(Icons.delete_outline, size: 14, color: AppColors.critical),
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
                        child: const Icon(
                          Icons.history,
                          size: 20,
                          color: AppColors.primary,
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
                              children: feederLogs.take(20).map(
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
                                          color: l.type == 'auto'
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
                                                color: AppColors.darkWith(0.4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ).toList(),
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

  void _showScheduleModal(BuildContext ctx, {int? index, ScheduleItem? existing}) {
    final isEdit = existing != null;
    TimeOfDay selectedTime;
    if (isEdit) {
      int h = int.parse(existing.time.split(':')[0]);
      final m = int.parse(existing.time.split(':')[1]);
      if (existing.ampm == 'PM' && h != 12) h += 12;
      if (existing.ampm == 'AM' && h == 12) h = 0;
      selectedTime = TimeOfDay(hour: h, minute: m);
    } else {
      selectedTime = const TimeOfDay(hour: 6, minute: 0);
    }

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
                        border: Border.all(
                          color: AppColors.darkWith(0.15),
                        ),
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
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final h = selectedTime.hour;
                        final m = selectedTime.minute;
                        final ampm = h >= 12 ? 'PM' : 'AM';
                        final h12 = h % 12 == 0 ? 12 : h % 12;
                        final timeStr =
                            '$h12:${m.toString().padLeft(2, '0')}';
                        if (isEdit) {
                          onEditSchedule(
                            index!,
                            ScheduleItem(timeStr, ampm),
                          );
                        } else {
                          timeCtl.text = '$timeStr:$ampm';
                          onAddSchedule();
                        }
                        Navigator.pop(sheetCtx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
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
