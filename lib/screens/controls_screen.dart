import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme/app_colors.dart';
import '../widgets/common/read_only_banner.dart';
import '../widgets/controls/feeder_tab.dart';
import '../widgets/controls/devices_tab.dart';
import '../models/control_types.dart';
import '../services/feeder_service.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';

class ControlsScreen extends StatefulWidget {
  final bool isOwner;
  const ControlsScreen({super.key, this.isOwner = true});

  @override
  State<ControlsScreen> createState() => ControlsScreenState();
}

enum _FeedState { hidden, dispensing, done, failed }

class ControlsScreenState extends State<ControlsScreen> {
  void switchToTab(int index) {
    if (index < 0 || index > 1) return;
    setState(() => _activeTab = index);
  }
  static Map<String, dynamic> _convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  int _activeTab = 0;
  _FeedState _feedState = _FeedState.hidden;
  bool _wasRunning = false;
  int _lastFeedCount = 0;
  int _feedCountAtStart = 0;
  Timer? _feedTimer;
  Timer? _dispenseTimer;
  final TextEditingController _timeCtl = TextEditingController();
  final Set<String> _fedToday = {};
  String _lastDateKey = '';

  @override
  void initState() {
    super.initState();
    final svc = FeederService.instance;
    _wasRunning = svc.isRunning;
    _lastFeedCount = svc.feedCount;
    _feedCountAtStart = svc.feedCount;
    _lastDateKey = _todayKey();
    svc.addListener(_onFeederUpdate);
    SensorService.instance.addListener(_onSensorDataUpdate);
    _initDeviceModes();
    _initDeviceLogs();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() => _computeRuntimeLabels());
      },
    );
  }

  void _initDeviceModes() {
    _devicesSub = DatabaseService.instance.deviceModesStream.listen((event) {
      if (event.snapshot.value != null && event.snapshot.value is Map) {
        final data = _convertMap(event.snapshot.value as Map);
        final modes = <String, String>{};
        for (final e in data.entries) {
          modes[e.key] = e.value.toString();
        }
        if (mounted) setState(() => _hwModes = modes);
      }
    });
  }

  void _initDeviceLogs() {
    for (final deviceId in ['aerator1', 'aerator2', 'pump']) {
      final sub = DatabaseService.instance.deviceLogsStream(deviceId).listen((event) {
        if (event.snapshot.value == null) return;
        final data = _convertMap(event.snapshot.value as Map);
        final list = data.values.map((e) {
          final map = _convertMap(e as Map);
          return LogEntry(
            map['action'] as String? ?? '',
            map['type'] as String? ?? '',
            map['time'] as String? ?? '',
            map['date'] as String? ?? '',
            timestamp: map['timestamp'] as int? ?? 0,
          );
        }).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        if (mounted) {
          setState(() => _hwLogs[deviceId] = list);
        }
      });
      _deviceLogSubs.add(sub);
    }
  }

  void _computeRuntimeLabels() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final labels = <String, String>{};

    for (final deviceId in _hwModes.keys) {
      final logs = _hwLogs[deviceId] ?? [];
      int? lastOnTs;
      int? lastOffTs;

      for (final log in logs) {
        if (log.action.contains('Switched ON')) {
          if (lastOnTs == null || log.timestamp > lastOnTs) {
            lastOnTs = log.timestamp;
          }
        } else if (log.action.contains('Switched OFF')) {
          if (lastOffTs == null || log.timestamp > lastOffTs) {
            lastOffTs = log.timestamp;
          }
        }
      }

      if (lastOnTs != null && (lastOffTs == null || lastOnTs > lastOffTs)) {
        final elapsed = now - lastOnTs;
        labels[deviceId] = _formatDuration(elapsed ~/ 1000);
      } else {
        labels[deviceId] = '';
      }
    }

    _deviceRuntimeLabels = labels;
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours < 24) return '${hours}h ${mins}m';
    final days = hours ~/ 24;
    final hrs = hours % 24;
    return '${days}d ${hrs}h';
  }

  void _onSensorDataUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FeederService.instance.removeListener(_onFeederUpdate);
    SensorService.instance.removeListener(_onSensorDataUpdate);
    _devicesSub?.cancel();
    for (final sub in _deviceLogSubs) {
      sub.cancel();
    }
    _feedTimer?.cancel();
    _dispenseTimer?.cancel();
    _runtimeTimer?.cancel();
    _timeCtl.dispose();
    super.dispose();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  void _checkDateReset() {
    final key = _todayKey();
    if (_lastDateKey != key) {
      _fedToday.clear();
      _lastDateKey = key;
    }
  }

  void _onFeederUpdate() {
    _checkDateReset();
    final svc = FeederService.instance;
    final isRunning = svc.isRunning;

    // Detect start: isRunning false → true
    if (_wasRunning != isRunning) {
      if (isRunning) {
        _feedCountAtStart = svc.feedCount;
        _feedState = _FeedState.dispensing;
        _dispenseTimer?.cancel();
        _dispenseTimer = Timer(const Duration(seconds: 60), () {
          if (!mounted) return;
          FeederService.instance.logFeedFailure();
          _feedState = _FeedState.failed;
          _feedTimer?.cancel();
          _feedTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _feedState = _FeedState.hidden);
          });
          if (mounted) setState(() {});
        });
      } else {
        _dispenseTimer?.cancel();
        // isRunning went true → false: check if feed actually dispensed
        if (_feedState == _FeedState.dispensing && svc.feedCount == _feedCountAtStart) {
          FeederService.instance.logFeedFailure();
          _feedState = _FeedState.failed;
          _feedTimer?.cancel();
          _feedTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _feedState = _FeedState.hidden);
          });
        }
      }
      _wasRunning = isRunning;
    }

    // Detect completion: feedCount incremented
    if (svc.feedCount != _lastFeedCount) {
      if (_feedState == _FeedState.dispensing) {
        _dispenseTimer?.cancel();
        _feedState = _FeedState.done;
        _feedTimer?.cancel();
        _feedTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _feedState = _FeedState.hidden);
        });
      }
      _lastFeedCount = svc.feedCount;
      if (svc.feedSource == 'scheduled') _markNearestScheduleFed();
    }

    if (mounted) setState(() {});
  }

  void _markNearestScheduleFed() {
    final now = DateTime.now();
    final svc = FeederService.instance;
    for (final s in svc.schedules) {
      int h = int.tryParse(s.time.split(':')[0]) ?? 6;
      final m = int.tryParse(s.time.split(':')[1]) ?? 0;
      if (s.ampm == 'PM' && h != 12) h += 12;
      if (s.ampm == 'AM' && h == 12) h = 0;
      final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
      if (now.difference(scheduleDt).inMinutes.abs() <= 2) {
        _fedToday.add('${s.time}_${s.ampm}');
      }
    }
  }

  Map<String, String> _hwModes = {
    'aerator1': 'auto',
    'aerator2': 'auto',
    'pump': 'auto',
  };
  StreamSubscription<DatabaseEvent>? _devicesSub;
  final List<StreamSubscription<DatabaseEvent>> _deviceLogSubs = [];
  final Map<String, List<LogEntry>> _hwLogs = {};
  Map<String, String> _deviceRuntimeLabels = {};
  Timer? _runtimeTimer;

  bool get _canFeed {
    if (!widget.isOwner) return false;
    if (!FeederService.instance.isOnline) return false;
    final svc = SensorService.instance;
    final ranges = SettingsService.instance.currentRanges;
    if (svc.turbidityAir) return false;
    final turbMax = ranges['turb']?['max'] ?? 999.0;
    final turb = svc.getLatestValue('turb');
    if (turb > turbMax) return false;
    return true;
  }

  String get _feedBlockedReason {
    final svc = SensorService.instance;
    if (svc.turbidityAir) return 'Feed blocked: turbidity sensor in air';
    final ranges = SettingsService.instance.currentRanges;
    final turbMax = ranges['turb']?['max'] ?? 999.0;
    final turb = svc.getLatestValue('turb');
    if (turb > turbMax) return 'Feed blocked: turbidity too high (${turb.toStringAsFixed(0)} > ${turbMax.toStringAsFixed(0)} NTU)';
    return '';
  }

  void _feedNow({double? grams}) {
    if (!widget.isOwner) return;
    final svc = FeederService.instance;
    if (!svc.isOnline) {
      setState(() => _feedState = _FeedState.failed);
      _feedTimer?.cancel();
      _feedTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _feedState = _FeedState.hidden);
      });
      return;
    }
    _feedCountAtStart = svc.feedCount;
    _dispenseTimer?.cancel();
    _dispenseTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      FeederService.instance.logFeedFailure();
      _feedState = _FeedState.failed;
      _feedTimer?.cancel();
      _feedTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _feedState = _FeedState.hidden);
      });
      if (mounted) setState(() {});
    });
    svc.feedNow(grams: grams);
    setState(() => _feedState = _FeedState.dispensing);
  }

  void _showFeedNowDialog() {
    if (!widget.isOwner) return;
    final gramsCtl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            String? gramsError;
            if (gramsCtl.text.isNotEmpty) {
              final raw = double.tryParse(gramsCtl.text);
              if (raw == null) {
                gramsError = 'Please enter a valid number';
              } else if (raw <= 0) {
                gramsError = 'Grams must be greater than 0';
              }
            }
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 22, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Feed Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                          SizedBox(height: 2),
                          Text('Optional: set grams to dispense', style: TextStyle(fontSize: 10, color: Color(0x80000000))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: gramsCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Grams (optional)',
                      hintText: 'e.g. 50',
                      suffixText: 'g',
                      errorText: gramsError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.critical, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.critical, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: gramsError != null
                          ? null
                          : () {
                              final grams = gramsCtl.text.isNotEmpty
                                  ? double.tryParse(gramsCtl.text)
                                  : null;
                              Navigator.pop(sheetCtx);
                              _feedNow(grams: grams);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.grey.shade500,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Dispense Feed', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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

  String _formatTimeInput(String val) {
    final parts = val.split(':');
    if (parts.length != 2) return val;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $ampm';
  }

  void _addSchedule({double? grams}) {
    if (!widget.isOwner) return;
    if (_timeCtl.text.isEmpty) return;
    final formatted = _formatTimeInput(_timeCtl.text);
    final isPM = formatted.contains('PM');
    final hStr = formatted.split(':')[0];
    final hour = int.tryParse(hStr) ?? 6;
    final timeStr = '$hour:${formatted.split(':')[1].split(' ')[0]}';
    FeederService.instance.addSchedule(timeStr, isPM ? 'PM' : 'AM', grams: grams);
    _timeCtl.clear();
  }

  void _deleteSchedule(int index) {
    if (!widget.isOwner) return;
    FeederService.instance.deleteSchedule(index);
  }

  void _editSchedule(int index, ScheduleItem item) {
    if (!widget.isOwner) return;
    FeederService.instance.editSchedule(
      index,
      time: item.time,
      ampm: item.ampm,
      enabled: item.enabled,
      grams: item.grams,
      clearGrams: item.grams == null,
    );
  }

  void _setHwMode(String device, String mode) {
    if (!widget.isOwner) return;
    setState(() => _hwModes[device] = mode);
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final modeNames = {
      'on': 'Switched ON',
      'auto': 'Set to AUTO',
      'off': 'Switched OFF',
    };
    final deviceNames = {
      'aerator1': 'Aerator 1',
      'aerator2': 'Aerator 2',
      'pump': 'Water Pump',
    };
    DatabaseService.instance.saveDeviceMode(
      deviceId: device,
      mode: mode,
      deviceName: deviceNames[device] ?? device,
      modeLabel: modeNames[mode] ?? mode,
      time: time,
      date: dateStr,
    ).catchError((e) {
      debugPrint('[Controls] ERROR saving $device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save $device mode: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              if (!widget.isOwner) _buildReadOnlyBanner(),
              Expanded(
                child: IndexedStack(
                  index: _activeTab,
                  children: [
                    FeederTab(
                      schedules: FeederService.instance.schedules,
                      timeCtl: _timeCtl,
                      onFeedNow: _showFeedNowDialog,
                      onAddSchedule: (grams) => _addSchedule(grams: grams),
                      onDeleteSchedule: _deleteSchedule,
                      onEditSchedule: _editSchedule,
                      feederLogs: FeederService.instance.logs,
                      fedToday: _fedToday,
                      feederError: FeederService.instance.feederError,
                      isOwner: widget.isOwner,
                      isOnline: FeederService.instance.isOnline,
                      isRunning: FeederService.instance.isRunning,
                      canFeed: _canFeed,
                      feedBlockedReason: _feedBlockedReason,
                    ),
                    DevicesTab(
                      hwModes: _hwModes,
                      onSetMode: _setHwMode,
                      onShowGroupLog: _showHwGroupLog,
                      deviceRuntimeLabels: _deviceRuntimeLabels,
                      isOwner: widget.isOwner,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_feedState != _FeedState.hidden) _buildFeedOverlay(),
        ],
      ),
    );
  }

  Widget _buildFeedOverlay() {
    final isFailed = _feedState == _FeedState.failed;
    final isDone = _feedState == _FeedState.done;
    final isDispensing = _feedState == _FeedState.dispensing;
    final isScheduled = FeederService.instance.feedSource == 'scheduled';

    final (String title, String subtitle, IconData icon, Color iconColor) = switch ((isFailed, isDone, isDispensing, isScheduled)) {
      (true,  _,     _,      _)     => ('Feed Failed!',          'Feed did not dispense. Check feeder.',        Icons.error_outline_rounded, AppColors.critical),
      (_,     true,  _,      true)  => ('Feed Complete!',        'Scheduled feed has been dispensed.',          Icons.check_circle_rounded,  AppColors.success),
      (_,     true,  _,      false) => ('Done!',                 'Feed has been dispensed successfully.',       Icons.check_circle_rounded,  AppColors.success),
      (_,     _,     true,   true)  => ('Auto-feeding...',       'Scheduled feed in progress.',                 Icons.schedule,              AppColors.primary),
      (_,     _,     true,   false) => ('Dispensing...',         'Please wait while the feeder is running.',    Icons.schedule,              AppColors.primary),
      _                              => ('Dispensing...',         'Please wait while the feeder is running.',    Icons.schedule,              AppColors.primary),
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: Colors.black26,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 48),
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isFailed
                        ? AppColors.critical.withValues(alpha: 0.12)
                        : isDone
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: isDispensing
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(icon, color: iconColor, size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.dark.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyBanner() {
    return const ReadOnlyBanner(
      message:
          'You can view all farm data, logs, and records. Only the Farm Owner can control hardware, manage feeding schedules, or modify settings.',
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
            width: 220,
            height: 140,
            child: Image.asset(
              'assets/images/controls_image.png',
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

  void _showHwGroupLog(
    BuildContext context,
    String label,
    List<(String, String, String, String?)> devices,
  ) {
    final allLogs = <LogEntry>[];
    for (final d in devices) {
      final deviceId = d.$1;
      final logs = _hwLogs[deviceId] ?? [];
      allLogs.addAll(logs);
    }
    allLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _showDeviceLogSheet(context, label, '', '', allLogs, null);
  }

  void _showDeviceLogSheet(
    BuildContext context,
    String title,
    String subtitle,
    String mode,
    List<LogEntry> logs,
    String? deviceId,
  ) {
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
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
                          color: const Color(0xFF1FA5A5).withValues(alpha: 0.1),
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
                              color: const Color(0xFF0B3C49).withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (deviceId != null) ...[
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
                                ? const Color(0xFF1FA5A5).withValues(alpha: 0.12)
                                : mode == 'auto'
                                    ? const Color(0xFFf59e0b).withValues(alpha: 0.12)
                                    : const Color(0xFFE63946).withValues(alpha: 0.08),
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
                            color: const Color(0xFF0B3C49).withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
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
                            color: const Color(0xFF0B3C49).withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    )
                  else
                    ...logs
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                          color: const Color(0xFF0B3C49).withValues(alpha: 0.4),
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
        ),
        );
      },
    );
  }
}
