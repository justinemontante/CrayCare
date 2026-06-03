import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/control_types.dart';
import '../services/feeder_service.dart';
import '../widgets/controls/feeder_tab.dart';
import '../widgets/controls/devices_tab.dart';

class ControlsScreen extends StatefulWidget {
  const ControlsScreen({super.key});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  int _activeTab = 0;

  final Map<String, String> _hwModes = {
    'aerator1': 'auto',
    'aerator2': 'auto',
    'pump': 'auto',
  };

  final Map<String, List<LogEntry>> _hwLogs = {
    'aerator1': [
      LogEntry('Set to AUTO', 'auto', '8:05 AM', 'Today'),
      LogEntry('Switched ON', 'on', '7:50 AM', 'Today'),
      LogEntry('Switched OFF', 'off', '7:30 AM', 'Today'),
    ],
    'aerator2': [
      LogEntry('Set to AUTO', 'auto', '8:10 AM', 'Today'),
      LogEntry('Switched ON', 'on', '7:45 AM', 'Today'),
      LogEntry('Switched OFF', 'off', '7:20 AM', 'Today'),
    ],
    'pump': [
      LogEntry('Set to AUTO', 'auto', '8:10 AM', 'Today'),
      LogEntry('Switched ON', 'on', '7:55 AM', 'Today'),
      LogEntry('Switched OFF', 'off', '7:20 AM', 'Today'),
    ],
  };

  final FeederService _feeder = FeederService.instance;

  @override
  void initState() {
    super.initState();
    _feeder.addListener(_onFeederChanged);
  }

  void _onFeederChanged() {
    if (mounted) setState(() {});
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
        LogEntry(modeNames[mode] ?? mode, mode, time, 'Today'),
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

  @override
  void dispose() {
    _feeder.removeListener(_onFeederChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: IndexedStack(
              index: _activeTab,
              children: [
                FeederTab(
                  feederAuto: _feeder.autoMode,
                  isOnline: _feeder.isOnline,
                  hopperLevel: _feeder.hopperLevel,
                  schedules: _feeder.schedules,
                  onToggleFeeder: _feeder.toggleMode,
                  onFeedNow: () => _feeder.feedNow(),
                  onAddSchedule: _feeder.addSchedule,
                  onDeleteSchedule: _feeder.deleteSchedule,
                  onEditSchedule: (i, s) => _feeder.editSchedule(
                    i,
                    time: s.time,
                    ampm: s.ampm,
                    enabled: s.enabled,
                  ),
                  feederLogs: _feeder.logs,
                ),
                DevicesTab(
                  hwModes: _hwModes,
                  onSetMode: _setHwMode,
                  onShowLog: _showHwLog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8FFFF),
            Color(0xFFF2FDFD),
            Color(0xFFE8FAFA),
            Color(0xFFDAF4F5),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            width: 170,
            height: 100,
            child: Image.asset(
              'assets/images/crayfish_seaweed_tank.png',
              fit: BoxFit.contain,
              alignment: Alignment.bottomRight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Controls',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.dark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Feeder & Devices',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark.withValues(alpha: 0.5),
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

  Widget _buildTabBar() {
    final tabs = [
      (Icons.bubble_chart, 'Feeding'),
      (Icons.developer_board_outlined, 'Devices'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 14),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.dark.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = _activeTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.dark.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[i].$1,
                      size: 14,
                      color: isActive
                          ? AppColors.primary
                          : AppColors.dark.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? AppColors.primary
                            : AppColors.dark.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

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
