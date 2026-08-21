import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/control_types.dart';
import 'connectivity_service.dart';
import 'sensor_service.dart';
import 'settings_service.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._();

  static const _months = [
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

  /// Formats an epoch-ms timestamp as "3:45 PM" (matches the old pre-formatted
  /// string the ESP32 used to send).
  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Formats an epoch-ms timestamp as "Aug 17, 2026".
  static String _formatDate(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  /// Accepts the canonical epoch-ms feeder timestamp plus legacy Firestore
  /// Timestamp/DateTime/ISO-string values so one old log cannot break the
  /// entire realtime feeder-log snapshot.
  static int _parseLoggedAtMillis(dynamic raw) {
    if (raw == null) return 0;
    if (raw is Timestamp) return raw.toDate().toUtc().millisecondsSinceEpoch;
    if (raw is DateTime) return raw.toUtc().millisecondsSinceEpoch;
    if (raw is num) {
      final value = raw.toInt();
      if (value <= 0) return 0;
      // Legacy integrations occasionally stored Unix seconds rather than ms.
      return value < 100000000000 ? value * 1000 : value;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return 0;
      final numeric = num.tryParse(text);
      if (numeric != null) return _parseLoggedAtMillis(numeric);
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed.toUtc().millisecondsSinceEpoch;
    }
    return 0;
  }

  // The feeder schedule times (and the Cloud Function that dispatches/confirms
  // them) are always expressed in Asia/Manila wall-clock time, regardless of
  // where the viewing device is physically located (e.g. someone
  // checking in from a different timezone). Using DateTime.now() directly
  // would compare schedule times against the DEVICE's local clock instead,
  // causing missed-schedule false positives and feederDispatched date-key
  // mismatches with the Cloud Function (functions/notifications/index.js,
  // which hardcodes MANILA_OFFSET_MS). Mirror that same fixed +8h approach
  // here so both sides agree on "today" and "now".
  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => manilaWallClock();

  bool _initialized = false;

  /// Resolved tank_id for the signed-in user. Feeder data now lives under
  /// tanks/{tank_id}/feeder, feeder_schedules, feeder_logs, feeder_commands.
  String? _tankId;

  Future<String?> _resolveTankId() async {
    if (_tankId != null) return _tankId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final profileDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final profile = profileDoc.data();
    if (profile?['role'] == 'admin') return null;
    var tankId = profile?['tank_id'] as String?;
    if (tankId == null || tankId.isEmpty) {
      tankId = uid;
      // Same safe legacy claim used by SensorService/TankService.
      await profileDoc.reference.set({'tank_id': uid}, SetOptions(merge: true));
    }
    _tankId = tankId;
    return _tankId;
  }

  DocumentReference<Map<String, dynamic>>? _tankDoc() => _tankId == null
      ? null
      : FirebaseFirestore.instance.collection('tanks').doc(_tankId);

  StreamSubscription? _statusSub;
  StreamSubscription? _schedulesSub;
  StreamSubscription? _logsSub;

  bool _isRunning = false;
  int _dispenseCount = 0;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;

  final List<LogEntry> _logs = [];
  final List<ScheduleItem> _schedules = [];
  final List<String> _scheduleKeys = [];

  Timer? _scheduleTimer;
  String _lastCheckDate = '';
  final Set<String> _missedLogged = {};

  bool get isRunning => _isRunning;
  int get dispenseCount => _dispenseCount;
  DateTime get lastSeen => _lastSeen;
  String? get lastError => _lastError;

  bool get isOnline => DateTime.now().difference(_lastSeen).inSeconds < 30;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);

  void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      _startScheduleTimer();
      if (FirebaseAuth.instance.currentUser != null) {
        _reinitListeners();
      }
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _cancelSubscriptions();
          _tankId = null;
          _reinitListeners();
        } else {
          _cancelSubscriptions();
          _tankId = null;
        }
      });
    } catch (e) {
      debugPrint('[FeederService] Initialization error: $e');
    }
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  Future<void> _reinitListeners() async {
    final tankId = await _resolveTankId();
    if (tankId == null) {
      debugPrint(
        '[FeederService] No tank_id resolved for user; feeder listeners not started.',
      );
      return;
    }
    _listenStatus();
    _listenSchedules();
    _listenLogs();
  }

  bool canFeedNow() {
    final ranges = SettingsService.instance.currentRanges;
    final turbMax = ranges['turb']?['max'] ?? 999.0;
    final turb = SensorService.instance.getLatestValue('turb');
    if (SensorService.instance.turbidityAir) return false;
    if (turb > turbMax) return false;
    return true;
  }

  void _onReconnect() {
    debugPrint('[FeederService] Internet reconnected — refreshing listeners');
    if (FirebaseAuth.instance.currentUser != null) {
      _cancelSubscriptions();
      unawaited(_reinitListeners());
    }
  }

  void _cancelSubscriptions() {
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _statusSub = null;
    _schedulesSub = null;
    _logsSub = null;
  }

  void _listenStatus() {
    _statusSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _statusSub = tankDoc
          .collection('feeder')
          .doc('status')
          .snapshots()
          .listen(
            (snapshot) {
              _lastError = null;
              if (!snapshot.exists || snapshot.data() == null) return;
              try {
                final data = snapshot.data()!;
                _isRunning = data['status'] == 'dispensing';
                _dispenseCount =
                    (data['dispenseCount'] as num?)?.toInt() ?? _dispenseCount;
                final seen = data['lastSeen'];
                if (seen is int && seen > 0) {
                  _lastSeen = DateTime.fromMillisecondsSinceEpoch(seen);
                } else if (seen is double && seen > 0) {
                  _lastSeen = DateTime.fromMillisecondsSinceEpoch(seen.toInt());
                }
              } catch (e) {
                debugPrint('[FeederService] Status parse error: $e');
              }
              notifyListeners();
            },
            onError: (error) {
              _lastError = error.toString();
              debugPrint('[FeederService] Status stream error: $error');
              notifyListeners();
            },
          );
    } catch (e) {
      debugPrint('[FeederService] Status listen error: $e');
    }
  }

  void _listenSchedules() {
    _schedulesSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _schedulesSub = tankDoc
          .collection('feeder_schedules')
          .orderBy('timeValue')
          .limit(20)
          .snapshots()
          .listen(
            (snapshot) {
              try {
                _schedules.clear();
                _scheduleKeys.clear();
                for (final doc in snapshot.docs) {
                  final data = doc.data();
                  _scheduleKeys.add(doc.id);
                  DateTime? effectiveAt;
                  final effectiveRaw = data['effective_at_ms'];
                  if (effectiveRaw is num && effectiveRaw.toInt() > 0) {
                    effectiveAt = DateTime.fromMillisecondsSinceEpoch(
                      effectiveRaw.toInt(),
                      isUtc: true,
                    );
                  } else {
                    final createdRaw = data['created_at'];
                    if (createdRaw is Timestamp) {
                      effectiveAt = createdRaw.toDate();
                    } else if (createdRaw is num && createdRaw.toInt() > 0) {
                      effectiveAt = DateTime.fromMillisecondsSinceEpoch(
                        createdRaw.toInt(),
                        isUtc: true,
                      );
                    }
                  }
                  _schedules.add(
                    ScheduleItem(
                      data['time'] as String? ?? '6:00',
                      data['ampm'] as String? ?? 'AM',
                      enabled: data['enabled'] as bool? ?? true,
                      isDone: data['isDone'] as bool? ?? false,
                      grams: (data['grams'] as num?)?.toDouble(),
                      days: data['days'] as String? ?? '1111111',
                      id: doc.id,
                      effectiveAt: effectiveAt,
                    ),
                  );
                }
                FeedState.schedules.value = List.from(_schedules);
              } catch (e) {
                debugPrint('[FeederService] Schedules parse error: $e');
              }
              notifyListeners();
            },
            onError: (error) {
              debugPrint('[FeederService] Schedules stream error: $error');
            },
          );
    } catch (e) {
      debugPrint('[FeederService] Schedules listen error: $e');
    }
  }

  void _listenLogs() {
    _logsSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _logsSub = tankDoc
          .collection('feeder_logs')
          .orderBy('logged_at', descending: true)
          .limit(50)
          .snapshots()
          .listen(
            (snapshot) {
              try {
                _logs.clear();
                for (final doc in snapshot.docs) {
                  try {
                    final data = doc.data();
                    // time/date are derived from logged_at (no longer stored) so the
                    // display matches the single source of truth for "when". Schedules
                    // and ESP NTP are anchored to Asia/Manila wall-clock time, so the
                    // log timestamps must be rendered in Manila too — otherwise a
                    // device in a different timezone fails to match its log against
                    // the schedule (false "Feed missed" detection).
                    final ts = _parseLoggedAtMillis(data['logged_at']);
                    final dt = ts > 0
                        ? DateTime.fromMillisecondsSinceEpoch(
                            ts,
                            isUtc: true,
                          ).add(_manilaOffset)
                        : null;
                    _logs.add(
                      LogEntry(
                        data['action'] as String? ?? '',
                        data['type'] as String? ?? 'auto',
                        dt == null ? '' : _formatTime(dt),
                        dt == null ? '' : _formatDate(dt),
                        timestamp: ts,
                        scheduleKey: data['schedule_key'] as String?,
                        scheduleTime: data['schedule_time'] as String?,
                      ),
                    );
                  } catch (e) {
                    debugPrint(
                      '[FeederService] Skipping malformed log ${doc.id}: $e',
                    );
                  }
                }
                FeedState.feederLogs.value = List.from(_logs);
              } catch (e) {
                debugPrint('[FeederService] Logs parse error: $e');
              }
              notifyListeners();
            },
            onError: (error) {
              debugPrint('[FeederService] Logs stream error: $error');
            },
          );
    } catch (e) {
      debugPrint('[FeederService] Logs listen error: $e');
    }
  }

  Future<void> feedNow({double? grams}) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      // New structure: tanks/{tank_id}/feeder_commands/{autoId}
      // ESP32 listens here, executes, then deletes the command.
      final cmd = <String, dynamic>{
        'command_type': 'feed_now',
        'issued_by': uid,
        'issued_at': FieldValue.serverTimestamp(),
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      await tankDoc.collection('feeder_commands').add(cmd);
      // NOTE: do NOT write a feeder_logs entry here.
      // The ESP32 writes the confirmed log after the servo physically completes,
      // which is the reliable source of truth. Writing here too causes duplicates.
      // Scheduled dispatch is owned by the ESP32 (it compares its synced
      // schedules against its own NTP-synced clock); the app does not enqueue
      // feed commands on a schedule.
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
    notifyListeners();
  }

  Future<void> logFeedFailure() async {
    await _addLogEntry(action: 'Feed failed to dispense', type: 'error');
  }

  Future<void> _addLogEntry({
    required String action,
    required String type,
  }) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      // tanks/{tank_id}/feeder_logs/{autoId}
      //
      // Store a true Unix epoch (UTC milliseconds) so it matches what the
      // ESP32 writes and can be rendered/ordered correctly anywhere. The
      // Manila wall-clock conversion is applied only when formatting.
      // `type` is the source of truth for how the feed was initiated:
      //   auto/missed → clock-driven (scheduled)
      //   error/manual → user-initiated or failure
      await tankDoc.collection('feeder_logs').add({
        'action': action,
        'type': type,
        'logged_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[FeederService] addLogEntry error: $e');
    }
  }

  Future<void> addSchedule(
    String time,
    String ampm, {
    double? grams,
    String days = '1111111',
  }) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final requested = ScheduleItem(time, ampm, grams: grams, days: days);
    _throwIfScheduleConflicts(requested);
    try {
      final parts = time.split(':');
      final h = int.tryParse(parts[0]) ?? 6;
      final m = int.tryParse(parts[1]) ?? 0;
      final hour24 = ampm == 'PM' ? (h == 12 ? 12 : h + 12) : (h == 12 ? 0 : h);
      final timeValue = hour24 * 60 + m;
      // tanks/{tank_id}/feeder_schedules/{autoId}
      await tankDoc.collection('feeder_schedules').add({
        'time': time,
        'ampm': ampm,
        'enabled': true,
        'isDone': false,
        'grams': grams,
        'timeValue': timeValue,
        'days': days,
        'created_at': FieldValue.serverTimestamp(),
        'effective_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      await _addLogEntry(
        action: 'Scheduled auto feed at $time $ampm$gramsStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] addSchedule error: $e');
    }
    notifyListeners();
  }

  String getScheduleTime(int index) {
    if (index < 0 || index >= _schedules.length) return '';
    final s = _schedules[index];
    return '${s.time} ${s.ampm}';
  }

  Future<void> deleteSchedule(int index) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final timeStr = getScheduleTime(index);
    try {
      await tankDoc
          .collection('feeder_schedules')
          .doc(_scheduleKeys[index])
          .delete();
      await _addLogEntry(action: 'Removed schedule at $timeStr', type: 'auto');
    } catch (e) {
      debugPrint('[FeederService] deleteSchedule error: $e');
    }
    notifyListeners();
  }

  /// Quick ON/OFF toggle for a schedule (alarm-clock style). Toggles the
  /// `enabled` flag without opening the edit modal.
  Future<void> toggleSchedule(int index, bool enabled) async {
    if (index < 0 ||
        index >= _scheduleKeys.length ||
        index >= _schedules.length) {
      return;
    }
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final scheduleKey = _scheduleKeys[index];
    final previous = _schedules[index];
    final timeStr = getScheduleTime(index);

    if (enabled) {
      _throwIfScheduleConflicts(
        ScheduleItem(
          previous.time,
          previous.ampm,
          enabled: true,
          grams: previous.grams,
          days: previous.days,
        ),
        excludingIndex: index,
      );
    }

    // Update the switch immediately; Firestore persistence continues in the
    // background. This avoids making the UI animation wait on the network and
    // the audit-log write.
    final effectiveNow = enabled
        ? DateTime.now().toUtc()
        : previous.effectiveAt;
    _schedules[index] = ScheduleItem(
      previous.time,
      previous.ampm,
      enabled: enabled,
      isDone: false,
      grams: previous.grams,
      days: previous.days,
      id: previous.id,
      effectiveAt: effectiveNow,
    );
    FeedState.schedules.value = List.from(_schedules);
    notifyListeners();

    try {
      await tankDoc.collection('feeder_schedules').doc(scheduleKey).update({
        'enabled': enabled,
        'isDone': false,
        if (enabled)
          'effective_at_ms': effectiveNow!.millisecondsSinceEpoch,
      });
      await _addLogEntry(
        action: enabled
            ? 'Schedule enabled: $timeStr'
            : 'Schedule disabled: $timeStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] toggleSchedule error: $e');
      // Roll back only if this same schedule has not received a newer toggle
      // or been replaced by a realtime Firestore snapshot in the meantime.
      if (index < _scheduleKeys.length &&
          index < _schedules.length &&
          _scheduleKeys[index] == scheduleKey &&
          _schedules[index].enabled == enabled) {
        _schedules[index] = previous;
        FeedState.schedules.value = List.from(_schedules);
        notifyListeners();
      }
    }
  }

  Future<void> editSchedule(
    int index, {
    required String time,
    required String ampm,
    bool? enabled,
    double? grams,
    bool clearGrams = false,
    String days = '1111111',
  }) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final requested = ScheduleItem(
      time,
      ampm,
      enabled: enabled ?? true,
      grams: grams,
      days: days,
    );
    _throwIfScheduleConflicts(requested, excludingIndex: index);
    try {
      final parts = time.split(':');
      final hour = int.tryParse(parts.first) ?? 6;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final timeValue =
          (ampm == 'PM' && hour != 12
                  ? hour + 12
                  : (ampm == 'AM' && hour == 12 ? 0 : hour)) *
              60 +
          minute;
      await tankDoc
          .collection('feeder_schedules')
          .doc(_scheduleKeys[index])
          .update({
            'time': time,
            'ampm': ampm,
            'timeValue': timeValue,
            'enabled': enabled ?? true,
            'isDone': false,
            'grams': grams,
            'days': days,
            'effective_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
          });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      await _addLogEntry(
        action: 'Edited schedule to $time $ampm$gramsStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] editSchedule error: $e');
    }
    notifyListeners();
  }

  void _throwIfScheduleConflicts(
    ScheduleItem requested, {
    int? excludingIndex,
  }) {
    for (var index = 0; index < _schedules.length; index++) {
      if (index == excludingIndex) continue;
      final existing = _schedules[index];
      if (feederSchedulesConflict(requested, existing)) {
        throw FeederScheduleConflictException(requested, existing);
      }
    }
  }

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_checkSchedules());
    });
  }

  Future<void> _checkSchedules() async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final now = _manilaNow();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastCheckDate != todayKey) {
      // Wait until the Firestore listener has loaded the schedule keys. If the
      // timer marks the date first while the list is still empty, yesterday's
      // isDone values would never be reset after startup.
      if (_scheduleKeys.isEmpty) return;
      _missedLogged.clear();
      for (final key in _scheduleKeys) {
        await tankDoc.collection('feeder_schedules').doc(key).update({
          'isDone': false,
        });
      }
      _lastCheckDate = todayKey;
    }

    for (int i = 0; i < _schedules.length; i++) {
      final s = _schedules[i];
      if (!s.enabled || s.isDone) continue;
      // Skip schedules that are not active on today's weekday (Sunday-first).
      if (!feederScheduleRunsOnDate(s, now)) continue;
      final key = i < _scheduleKeys.length
          ? _scheduleKeys[i]
          : (s.id ?? '${s.time}_${s.ampm}');

      final scheduleMinutes = feederScheduleMinutes(s);
      final hour24 = scheduleMinutes ~/ 60;
      final m = scheduleMinutes % 60;
      final scheduleDt = DateTime(now.year, now.month, now.day, hour24, m);
      if (!feederScheduleWasEffectiveAt(s, scheduleDt)) continue;
      final occurrenceKey = '$key|$scheduleMinutes';
      if (_missedLogged.contains(occurrenceKey)) continue;

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
      final expectedDate = '${months[now.month - 1]} ${now.day}, ${now.year}';
      final expectedTime = '${s.time} ${s.ampm}';
      final alreadyConfirmed = _logs.any((log) {
        final action = log.action.toLowerCase();
        return log.type == 'auto' &&
            (action.contains('dispensed feed (scheduled)') ||
                action.contains('auto feed dispensed')) &&
            log.time == expectedTime &&
            log.date == expectedDate;
      });
      if (alreadyConfirmed) continue;

      if (now.difference(scheduleDt).inMinutes >= 5) {
        _missedLogged.add(occurrenceKey);
        final reason = isOnline
            ? 'No confirmed feeder log received'
            : 'ESP was offline';
        // Use a deterministic document ID so an app restart or multiple
        // devices cannot write duplicate "Feed skipped" logs for the same
        // schedule on the same Manila day.
        final missedDocId = 'missed_${todayKey}_${key}_$scheduleMinutes'
            .replaceAll('/', '_')
            .replaceAll(RegExp(r'[^\w.\-]'), '_');
        await tankDoc.collection('feeder_logs').doc(missedDocId).set({
          'action': 'Feed missed - $reason',
          'type': 'missed',
          // Store the real current UTC instant. `now` is only a Manila
          // wall-clock view used for schedule comparison/date keys.
          'logged_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          'schedule_key': key,
          'schedule_time': expectedTime,
        }, SetOptions(merge: true));
        debugPrint('[FeederService] Missed schedule: $key ($reason)');
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
