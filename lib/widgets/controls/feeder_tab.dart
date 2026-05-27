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
                      const Text(
                        'Automatic Feeder',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
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

  String _scheduleStatus(ScheduleItem s) {
    final now = DateTime.now();
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    final sMin = h * 60 + m;
    final nowMin = now.hour * 60 + now.minute;
    if (sMin < nowMin) return 'completed';
    if (sMin == nowMin) return 'pending';
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
            ...items.asMap().entries.map(
              (e) => _buildScheduleItem(ctx, e.key, e.value),
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
