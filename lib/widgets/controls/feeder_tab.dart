import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/control_types.dart';

class FeederTab extends StatelessWidget {
  final bool feederAuto;
  final List<ScheduleItem> schedules;
  final TextEditingController timeCtl;
  final TextEditingController gramsCtl;
  final VoidCallback onToggleFeeder;
  final VoidCallback onFeedNow;
  final VoidCallback onAddSchedule;
  final VoidCallback onShowLog;

  const FeederTab({
    super.key,
    required this.feederAuto,
    required this.schedules,
    required this.timeCtl,
    required this.gramsCtl,
    required this.onToggleFeeder,
    required this.onFeedNow,
    required this.onAddSchedule,
    required this.onShowLog,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFeederGroup(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFeederGroup() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.03),
        border: Border.all(color: AppColors.darkWith(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.egg_alt, size: 12, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(
                    'Auto Feeder',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: onShowLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWith(0.1),
                    border: Border.all(color: AppColors.primaryWith(0.2)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.menu_book, size: 10, color: AppColors.primary),
                      SizedBox(width: 4),
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
          const SizedBox(height: 8),
          _buildFeederCardBody(),
        ],
      ),
    );
  }

  Widget _buildFeederCardBody() {
    final morning = schedules.where((s) => s.ampm == 'AM').toList();
    final afternoon = schedules.where((s) => s.ampm == 'PM').toList();
    final morningGrams = morning.fold(0, (sum, s) => sum + s.grams);
    final afternoonGrams = afternoon.fold(0, (sum, s) => sum + s.grams);
    final totalGrams = morningGrams + afternoonGrams;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkWith(0.1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkWith(0.07),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryWith(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.egg_alt,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Auto Feeder',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark,
                    ),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      feederAuto ? 'Auto' : 'Manual',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: onToggleFeeder,
                      child: Container(
                        width: 40,
                        height: 22,
                        decoration: BoxDecoration(
                          color: feederAuto
                              ? AppColors.primary
                              : AppColors.darkWith(0.15),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: feederAuto
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 2),
                              ],
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
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
          ),
          const SizedBox(height: 14),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.successWith(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.successWith(0.2),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/crayfish_feeder.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.egg, size: 12, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      '$totalGrams g Total',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSchedulePeriod(
                  'Morning',
                  Icons.wb_sunny_outlined,
                  morning,
                  morningGrams,
                ),
                const SizedBox(height: 12),
                _buildSchedulePeriod(
                  'Afternoon',
                  Icons.wb_twilight_outlined,
                  afternoon,
                  afternoonGrams,
                ),
                const SizedBox(height: 12),
                _buildAddScheduleRow(),
              ],
            ),
          ),
          _buildAIRecommendation(),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildSchedulePeriod(
    String label,
    IconData icon,
    List<ScheduleItem> items,
    int totalGrams,
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryWith(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${totalGrams}g',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
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
            ...items.map((s) => _buildScheduleItem(s)),
        ],
      ),
    );
  }

  Widget _buildScheduleItem(ScheduleItem s) {
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

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
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
              color: AppColors.primaryWith(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${s.grams}g',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
    );
  }

  Widget _buildAddScheduleRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.darkWith(0.15)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: timeCtl,
              decoration: InputDecoration(
                hintText: 'HH:MM',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: AppColors.darkWith(0.3),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
              style: const TextStyle(fontSize: 11, color: AppColors.dark),
              keyboardType: TextInputType.datetime,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 50,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.darkWith(0.15)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: gramsCtl,
              decoration: InputDecoration(
                hintText: 'g',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: AppColors.darkWith(0.3),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
              ),
              style: const TextStyle(fontSize: 11, color: AppColors.dark),
              keyboardType: TextInputType.number,
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onAddSchedule,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Add',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAIRecommendation() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryWith(0.06),
        border: Border.all(color: AppColors.primaryWith(0.15)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.smart_toy, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'AI Feeding Recommendation',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryWith(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryWith(0.12)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.smart_toy,
                  size: 16,
                  color: AppColors.primary,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your crayfish are doing well! Current feeding schedule is optimized based on your population.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.dark,
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

  String _scheduleStatus(ScheduleItem s) {
    final now = DateTime.now();
    final sMin = _toMinutes(s);
    final nowMin = now.hour * 60 + now.minute;
    if (sMin < nowMin) return 'completed';
    if (sMin == nowMin) return 'pending';
    return 'upcoming';
  }

  int _toMinutes(ScheduleItem s) {
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }
}
