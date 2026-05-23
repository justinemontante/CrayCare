import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/section_label.dart';
import '../widgets/gradient_button.dart';

class ControlsScreen extends StatefulWidget {
  const ControlsScreen({super.key});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  bool _feederAuto = true;
  final List<_ScheduleItem> _schedules = [
    _ScheduleItem('6:00', 'AM', 22),
    _ScheduleItem('6:00', 'PM', 22),
  ];
  final TextEditingController _timeCtl = TextEditingController();
  final TextEditingController _gramsCtl = TextEditingController();
  // (edit mode fields reserved for future use)

  final Map<String, String> _hwModes = {
    'aerator1': 'auto',
    'aerator2': 'auto',
    'pump': 'auto',
  };

  final List<_LogEntry> _feederLogs = [
    _LogEntry('Dispensed 44.1g feed (Scheduled)', 'auto', '6:00 AM', 'Today'),
  ];

  final Map<String, List<_LogEntry>> _hwLogs = {
    'aerator1': [
      _LogEntry('Set to AUTO', 'auto', '8:05 AM', 'Today'),
      _LogEntry('Switched ON', 'on', '7:50 AM', 'Today'),
      _LogEntry('Switched OFF', 'off', '7:30 AM', 'Today'),
    ],
    'aerator2': [
      _LogEntry('Set to AUTO', 'auto', '8:10 AM', 'Today'),
      _LogEntry('Switched ON', 'on', '7:45 AM', 'Today'),
      _LogEntry('Switched OFF', 'off', '7:20 AM', 'Today'),
    ],
    'pump': [
      _LogEntry('Set to AUTO', 'auto', '8:10 AM', 'Today'),
      _LogEntry('Switched ON', 'on', '7:55 AM', 'Today'),
      _LogEntry('Switched OFF', 'off', '7:20 AM', 'Today'),
    ],
  };

  void _toggleFeeder() {
    setState(() => _feederAuto = !_feederAuto);
  }

  void _feedNow() {
    _addFeederLog('Manual Feed — Feed Now triggered', 'manual');
  }

  void _addFeederLog(String action, String type) {
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    setState(() {
      _feederLogs.insert(0, _LogEntry(action, type, time, 'Today'));
      if (_feederLogs.length > 50) _feederLogs.removeLast();
    });
  }

  String _formatTimeInput(String val) {
    final parts = val.split(':');
    if (parts.length != 2) return val;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $ampm';
  }

  void _addSchedule() {
    if (_timeCtl.text.isEmpty) return;
    final formatted = _formatTimeInput(_timeCtl.text);
    final grams = int.tryParse(_gramsCtl.text) ?? 10;
    final isPM = formatted.contains('PM');
    final hStr = formatted.split(':')[0];
    final hour = int.tryParse(hStr) ?? 6;
    setState(() {
      _schedules.add(
        _ScheduleItem(
          '$hour:${formatted.split(':')[1].split(' ')[0]}',
          isPM ? 'PM' : 'AM',
          grams,
        ),
      );
      _schedules.sort((a, b) {
        final aMin = _toMinutes(a);
        final bMin = _toMinutes(b);
        return aMin.compareTo(bMin);
      });
      _timeCtl.clear();
      _gramsCtl.clear();
    });
  }

  int _toMinutes(_ScheduleItem s) {
    int h = int.tryParse(s.time.split(':')[0]) ?? 6;
    final m = int.tryParse(s.time.split(':')[1]) ?? 0;
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    return h * 60 + m;
  }

  void _setHwMode(String device, String mode) {
    setState(() => _hwModes[device] = mode);
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    final modeNames = {
      'on': 'Switched ON',
      'auto': 'Set to AUTO',
      'off': 'Switched OFF',
    };
    if (_hwLogs[device] != null) {
      _hwLogs[device]!.insert(
        0,
        _LogEntry(modeNames[mode] ?? mode, mode, time, 'Today'),
      );
      if (_hwLogs[device]!.length > 20) _hwLogs[device]!.removeLast();
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'on':
        return AppColors.primary;
      case 'auto':
        return AppColors.warning;
      case 'off':
        return AppColors.critical;
      default:
        return AppColors.darkWith(0.4);
    }
  }

  String _scheduleStatus(_ScheduleItem s) {
    final now = DateTime.now();
    final sMin = _toMinutes(s);
    final nowMin = now.hour * 60 + now.minute;
    if (sMin < nowMin) return 'completed';
    if (sMin == nowMin) return 'pending';
    return 'upcoming';
  }

  @override
  void dispose() {
    _timeCtl.dispose();
    _gramsCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel(label: 'Hardware Controls'),
            const SizedBox(height: 8),
            _buildFeederGroup(),
            const SizedBox(height: 10),
            _buildAerationGroup(),
            const SizedBox(height: 10),
            _buildFiltrationGroup(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─── FEEDER GROUP ───────────────────────────────────────────
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
                onTap: () => _showFeederLog(context),
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

  // ─── FEEDER CARD BODY ───────────────────────────────────────
  Widget _buildFeederCardBody() {
    final morning = _schedules.where((s) => s.ampm == 'AM').toList();
    final afternoon = _schedules.where((s) => s.ampm == 'PM').toList();
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
          // Toggle row
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
                      _feederAuto ? 'Auto' : 'Manual',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: _toggleFeeder,
                      child: Container(
                        width: 40,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _feederAuto
                              ? AppColors.primary
                              : AppColors.darkWith(0.15),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: AnimatedAlign(
                          duration: const Duration(milliseconds: 200),
                          alignment: _feederAuto
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
          // Feed Now button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _feedNow,
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
          // Feeder image
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
          // Schedule
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                // Grand total
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
                // Morning
                _buildSchedulePeriod(
                  'Morning',
                  Icons.wb_sunny_outlined,
                  morning,
                  morningGrams,
                ),
                const SizedBox(height: 12),
                // Afternoon
                _buildSchedulePeriod(
                  'Afternoon',
                  Icons.wb_twilight_outlined,
                  afternoon,
                  afternoonGrams,
                ),
                const SizedBox(height: 12),
                // Add row
                _buildAddScheduleRow(),
              ],
            ),
          ),
          // AI Recommendation
          _buildAIRecommendation(),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildSchedulePeriod(
    String label,
    IconData icon,
    List<_ScheduleItem> items,
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

  Widget _buildScheduleItem(_ScheduleItem s) {
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
              controller: _timeCtl,
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
              controller: _gramsCtl,
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
          onTap: _addSchedule,
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

  // ─── AI RECOMMENDATION ──────────────────────────────────────
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
          Row(
            children: [
              const Icon(Icons.smart_toy, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.smart_toy,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _feederLogs.isEmpty
                            ? 'Hi! It looks like you haven\'t set your initial stock yet. Once you set it in the Tank tab, I\'ll calculate feeding recommendations.'
                            : 'Your crayfish are doing well! Current feeding schedule is optimized based on your population.',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.dark,
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
    );
  }

  // ─── AERATION GROUP ─────────────────────────────────────────
  Widget _buildAerationGroup() {
    return _buildHwGroup('Aeration', Icons.air, [
      ('aerator1', 'Aerator 1', 'Air Pump'),
      ('aerator2', 'Aerator 2', 'Air Pump'),
    ]);
  }

  // ─── FILTRATION GROUP ───────────────────────────────────────
  Widget _buildFiltrationGroup() {
    return _buildHwGroup('Filtration', Icons.water_drop, [
      ('pump', 'Water Pump', 'Filtration System'),
    ]);
  }

  Widget _buildHwGroup(
    String label,
    IconData icon,
    List<(String, String, String)> devices,
  ) {
    final firstId = devices.isNotEmpty ? devices.first.$1 : '';
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
                  Icon(icon, size: 12, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkWith(0.6),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => _showHwLog(
                  context,
                  firstId,
                  devices.first.$2,
                  devices.first.$3,
                ),
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
          ...devices.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildHwCard(d.$1, d.$2, d.$3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHwCard(String deviceId, String title, String subtitle) {
    final mode = _hwModes[deviceId] ?? 'auto';
    final borderColor = mode == 'on'
        ? AppColors.primaryWith(0.4)
        : mode == 'auto'
        ? AppColors.warning.withValues(alpha: 0.35)
        : AppColors.darkWith(0.1);
    final iconColor = mode == 'on'
        ? AppColors.primary
        : mode == 'auto'
        ? AppColors.warning
        : AppColors.darkWith(0.4);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showHwLog(context, deviceId, title, subtitle),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0f000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.air, size: 18, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.darkWith(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                // Mode buttons (clicking here won't open log)
                _buildHwModeToggle(deviceId, mode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHwModeToggle(String deviceId, String currentMode) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.darkWith(0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['off', 'auto', 'on'].map((m) {
          final isActive = m == currentMode;
          return GestureDetector(
            onTap: () => _setHwMode(deviceId, m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                m.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: isActive ? _modeColor(m) : AppColors.darkWith(0.4),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── FEEDER LOG MODAL ───────────────────────────────────────
  void _showFeederLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SingleChildScrollView(
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
                      const Icon(
                        Icons.menu_book,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Feeder Activity Log',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_feederLogs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No activity yet.',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(
                              0xFF0B3C49,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._feederLogs
                        .take(20)
                        .map(
                          (l) => Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFf7f7f7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: l.type == 'auto'
                                        ? AppColors.warning
                                        : AppColors.primary,
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
                                          color: const Color(
                                            0xFF0B3C49,
                                          ).withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
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

  // ─── HW LOG MODAL ───────────────────────────────────────────
  void _showHwLog(
    BuildContext context,
    String deviceId,
    String title,
    String subtitle,
  ) {
    final mode = _hwModes[deviceId] ?? 'auto';
    final logs = _hwLogs[deviceId] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: SingleChildScrollView(
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
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1FA5A5,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.air,
                              size: 22,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dark,
                                ),
                              ),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: const Color(
                                    0xFF0B3C49,
                                  ).withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: mode == 'on'
                                  ? const Color(
                                      0xFF1FA5A5,
                                    ).withValues(alpha: 0.12)
                                  : mode == 'auto'
                                  ? const Color(
                                      0xFFf59e0b,
                                    ).withValues(alpha: 0.12)
                                  : const Color(
                                      0xFFE63946,
                                    ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              mode.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: mode == 'on'
                                    ? AppColors.primary
                                    : mode == 'auto'
                                    ? const Color(0xFFc97d08)
                                    : AppColors.critical,
                              ),
                            ),
                          ),
                          Text(
                            'Last changed: ${logs.isNotEmpty ? logs.first.time : '--'}',
                            style: TextStyle(
                              fontSize: 9,
                              color: const Color(
                                0xFF0B3C49,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0B3C49,
                          ).withValues(alpha: 0.03),
                          border: Border.all(
                            color: const Color(
                              0xFF0B3C49,
                            ).withValues(alpha: 0.07),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.trending_up,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Dissolved O\u2082: ',
                              style: TextStyle(
                                fontSize: 11,
                                color: const Color(
                                  0xFF0B3C49,
                                ).withValues(alpha: 0.7),
                              ),
                            ),
                            const Text(
                              '4.2 mg/L',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.dark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'MODE CONTROL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkWith(0.4),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0B3C49,
                          ).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: ['off', 'auto', 'on'].map((m) {
                            final isActive =
                                m == (_hwModes[deviceId] ?? 'auto');
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  _setHwMode(deviceId, m);
                                  setDialogState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: isActive
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.1,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    m.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isActive
                                          ? _modeColor(m)
                                          : const Color(
                                              0xFF0B3C49,
                                            ).withValues(alpha: 0.4),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'ACTIVITY LOG',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkWith(0.4),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (logs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'No activity yet.',
                              style: TextStyle(
                                fontSize: 11,
                                color: const Color(
                                  0xFF0B3C49,
                                ).withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        )
                      else
                        ...logs
                            .take(10)
                            .map(
                              (l) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFf7f7f7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: l.type == 'on'
                                            ? AppColors.primary
                                            : l.type == 'auto'
                                            ? AppColors.warning
                                            : AppColors.critical,
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
                                              color: const Color(
                                                0xFF0B3C49,
                                              ).withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
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
      },
    );
  }
}

class _ScheduleItem {
  final String time;
  final String ampm;
  final int grams;
  _ScheduleItem(this.time, this.ampm, this.grams);
}

class _LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  _LogEntry(this.action, this.type, this.time, this.date);
}
