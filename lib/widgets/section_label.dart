import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/control_types.dart';

class SectionLabel extends StatelessWidget {
  final String label;
  final bool showLiveData;
  final IconData? icon;
  final double topPadding;

  const SectionLabel({
    super.key,
    required this.label,
    this.showLiveData = false,
    this.icon,
    this.topPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        if (showLiveData)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF22c55e),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Live Data',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(14, topPadding, 14, 8),
      child: label == 'Operational Schedule'
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 9),
                _buildOperationalScheduleSummary(),
              ],
            )
          : header,
    );
  }

  Widget _buildOperationalScheduleSummary() {
    return ValueListenableBuilder<List<ScheduleItem>>(
      valueListenable: FeedState.schedules,
      builder: (context, schedules, _) {
        final now = manilaWallClock();
        final todaySchedules = schedules
            .where((schedule) => feederScheduleRunsOnDate(schedule, now))
            .toList();

        int countBetween(int startMinute, int endMinute) {
          return todaySchedules.where((schedule) {
            final minutes = feederScheduleMinutes(schedule);
            return minutes >= startMinute && minutes < endMinute;
          }).length;
        }

        final morningCount = countBetween(0, 12 * 60);
        final afternoonCount = countBetween(12 * 60, 18 * 60);
        final eveningCount = countBetween(18 * 60, 24 * 60);
        final total = todaySchedules.length;
        final totalText = total == 1 ? '1 feed today' : '$total feeds today';

        return Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.today_rounded,
                      size: 15,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Today's Feeding Plan",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      totalText,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  _buildPeriodTile(
                    label: 'Morning',
                    detail: 'Before 12 PM',
                    count: morningCount,
                    icon: Icons.wb_sunny_outlined,
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 7),
                  _buildPeriodTile(
                    label: 'Afternoon',
                    detail: '12–6 PM',
                    count: afternoonCount,
                    icon: Icons.light_mode_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  _buildPeriodTile(
                    label: 'Evening',
                    detail: 'After 6 PM',
                    count: eveningCount,
                    icon: Icons.nights_stay_outlined,
                    color: const Color(0xFF6366F1),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeriodTile({
    required String label,
    required String detail,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 6.5,
                fontWeight: FontWeight.w500,
                color: AppColors.darkWith(0.48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
