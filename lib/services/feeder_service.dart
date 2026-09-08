import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
      final numeric = raw.toDouble();
      if (!numeric.isFinite || numeric <= 0) return 0;
      final value = numeric.round();
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
  static const _maxFutureHeartbeatSkew = Duration(seconds: 60);
  DateTime _manilaNow() => manilaWallClock();

  bool _initialized = false;

  /// Resolved tank_id for the signed-in user. Feeder data now lives under
  /// tanks/{tank_id}/feeder, feeder_schedules, feeder_logs, feeder_commands.
  String? _tankId;
  int _listenerGeneration = 0;

  Future<String?> _resolveTankId() async {
    if (_tankId != null) return _tankId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final profile = profileDoc.data();
      if (FirebaseAuth.instance.currentUser?.uid != uid) return null;
      final role = profile?['role']?.toString().trim().toLowerCase();
      if (role == 'admin') return null;
      if (!profileDoc.exists || role != 'owner') return null;
      _tankId = uid;
      return _tankId;
    } catch (e) {
      debugPrint('[FeederService] Failed to resolve tank for $uid: $e');
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>>? _tankDoc() => _tankId == null
      ? null
      : FirebaseFirestore.instance.collection('tanks').doc(_tankId);

  StreamSubscription? _statusSub;
  StreamSubscription? _schedulesSub;
  StreamSubscription? _logsSub;
  StreamSubscription? _todayLogsSub;
  StreamSubscription<User?>? _authSub;
  String _totalsDayKey = '';
  double _consumptionToday = 0;
  int _completedToday = 0;

  bool _isRunning = false;
  DateTime? _manualRequestPendingUntil;
  String _status = 'idle';
  String? _statusCommandId;
  String _statusReason = '';
  String? _lastQueuedCommandId;
  int _dispenseCount = 0;
  double? _feedLevelPercent;
  double? _estimatedFeedGrams;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;
  String? _lastFeedRequestError;
  bool _schedulesLoaded = false;

  final List<LogEntry> _logs = [];
  final List<ScheduleItem> _schedules = [];
  final List<String> _scheduleKeys = [];

  Timer? _scheduleTimer;
  bool _scheduleCheckInProgress = false;
  String _lastCheckDate = '';
  final Set<String> _missedLogged = {};

  bool get isRunning => _isRunning;
  String get status => _status;
  String? get statusCommandId => _statusCommandId;
  String get statusReason => _statusReason;
  String? get lastQueuedCommandId => _lastQueuedCommandId;
  int get dispenseCount => _dispenseCount;
  double? get feedLevelPercent => _feedLevelPercent;
  double? get estimatedFeedGrams => _estimatedFeedGrams;
  DateTime get lastSeen => _lastSeen;
  String? get lastError => _lastError;
  String? get lastFeedRequestError => _lastFeedRequestError;
  bool get manualRequestPending =>
      _manualRequestPendingUntil?.isAfter(DateTime.now()) ?? false;

  bool get isOnline {
    final age = DateTime.now().difference(_lastSeen);
    return !age.isNegative && age < const Duration(seconds: 30);
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);

  double get consumptionTodayGrams {
    return _consumptionToday;
  }

  int get completedFeedingsToday {
    return _completedToday;
  }

  // Totals must not depend on the 50-entry history preview (which also
  // contains schedule edits, skipped feeds and other non-consumption events).
  void _listenTodayTotals() {
    final tank = _tankDoc();
    if (tank == null) return;
    final now = _manilaNow();
    final dayKey = '${now.year}-${now.month}-${now.day}';
    if (_totalsDayKey == dayKey && _todayLogsSub != null) return;
    _totalsDayKey = dayKey;
    _todayLogsSub?.cancel();
    _consumptionToday = 0;
    _completedToday = 0;
    final start = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(_manilaOffset).millisecondsSinceEpoch;
    _todayLogsSub = tank
        .collection('feeder_logs')
        .where('logged_at', isGreaterThanOrEqualTo: start)
        .where(
          'logged_at',
          isLessThan: start + const Duration(days: 1).inMilliseconds,
        )
        .snapshots()
        .listen(
          (snapshot) {
            var total = 0.0;
            var completed = 0;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              if (data['status'] != 'completed') continue;
              completed++;
              final grams =
                  (data['estimated_dispensed_grams'] as num?)?.toDouble() ??
                  (data['requested_grams'] as num?)?.toDouble() ??
                  0;
              if (grams.isFinite && grams >= 0) total += grams;
            }
            _consumptionToday = total;
            _completedToday = completed;
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('[FeederService] Today totals failed: $error');
          },
        );
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      _startScheduleTimer();
      if (FirebaseAuth.instance.currentUser != null) {
        unawaited(_reinitListeners());
      }
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _cancelSubscriptions();
          _tankId = null;
          unawaited(_reinitListeners());
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
    final generation = _listenerGeneration;
    final tankId = await _resolveTankId();
    if (generation != _listenerGeneration) return;
    if (tankId == null) {
      debugPrint(
        '[FeederService] No tank_id resolved for user; feeder listeners not started.',
      );
      return;
    }
    _listenStatus();
    _listenSchedules();
    _listenLogs();
    _listenTodayTotals();
  }

  String feedSafetyIssue({double? grams}) {
    final sensors = SensorService.instance;
    const keys = ['temp', 'do', 'ph', 'turb', 'feedlevel'];
    return feederPreflightIssue(
      internetOnline: ConnectivityService.instance.isOnline,
      feederOnline: isOnline,
      busy: _isRunning || manualRequestPending,
      schedulesLoaded: _schedulesLoaded,
      turbidityAir: sensors.turbidityAir,
      values: {for (final key in keys) key: sensors.getLatestValue(key)},
      freshSensors: {
        for (final key in keys)
          if (sensors.hasFreshData(key)) key,
      },
      ranges: SettingsService.instance.currentRanges,
      availableGrams: sensors.estimatedFeedGrams,
      grams: grams,
    );
  }

  bool canFeedNow({double? grams}) => feedSafetyIssue(grams: grams).isEmpty;

  void _onReconnect() {
    debugPrint('[FeederService] Internet reconnected — refreshing listeners');
    if (FirebaseAuth.instance.currentUser != null) {
      _cancelSubscriptions();
      unawaited(_reinitListeners());
    }
  }

  void _cancelSubscriptions() {
    _listenerGeneration++;
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _todayLogsSub?.cancel();
    _todayLogsSub = null;
    _totalsDayKey = '';
    _consumptionToday = 0;
    _completedToday = 0;
    _statusSub = null;
    _schedulesSub = null;
    _logsSub = null;
    _schedules.clear();
    _scheduleKeys.clear();
    _logs.clear();
    _missedLogged.clear();
    _lastCheckDate = '';
    _isRunning = false;
    _status = 'idle';
    _statusCommandId = null;
    _statusReason = '';
    _lastQueuedCommandId = null;
    _manualRequestPendingUntil = null;
    _dispenseCount = 0;
    _feedLevelPercent = null;
    _estimatedFeedGrams = null;
    _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
    _lastError = null;
    _lastFeedRequestError = null;
    _schedulesLoaded = false;
    FeedState.schedules.value = [];
    FeedState.feederLogs.value = [];
    notifyListeners();
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
                _status = data['status'] as String? ?? 'idle';
                _statusCommandId = data['command_id'] as String?;
                if (_statusCommandId != null &&
                    _statusCommandId == _lastQueuedCommandId &&
                    const [
                      'completed',
                      'blocked',
                      'failed',
                      'skipped_insufficient',
                    ].contains(_status)) {
                  _manualRequestPendingUntil = null;
                }
                _statusReason = data['status_reason'] as String? ?? '';
                _isRunning =
                    _status == 'dispensing' || _status == 'checking_feed_level';
                _feedLevelPercent = (data['feed_level'] as num?)?.toDouble();
                _estimatedFeedGrams = (data['estimated_feed_grams'] as num?)
                    ?.toDouble();
                _dispenseCount =
                    (data['dispenseCount'] as num?)?.toInt() ?? _dispenseCount;

                final seenMs = _parseLoggedAtMillis(data['lastSeen']);
                if (seenMs > 0) {
                  final parsed = DateTime.fromMillisecondsSinceEpoch(seenMs);
                  final now = DateTime.now();
                  final futureSkew = parsed.difference(now);
                  if (futureSkew > _maxFutureHeartbeatSkew) {
                    _lastError =
                        'Feeder heartbeat has an invalid future timestamp.';
                  } else {
                    _lastSeen = parsed.isAfter(now) ? now : parsed;
                  }
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
                      lastOutcome: data['last_outcome'] as String?,
                      lastOccurrenceAt:
                          _parseLoggedAtMillis(data['last_occurrence_at']) > 0
                          ? DateTime.fromMillisecondsSinceEpoch(
                              _parseLoggedAtMillis(data['last_occurrence_at']),
                              isUtc: true,
                            )
                          : null,
                    ),
                  );
                }
                FeedState.schedules.value = List.from(_schedules);
                _schedulesLoaded = true;
              } catch (e) {
                _schedulesLoaded = false;
                debugPrint('[FeederService] Schedules parse error: $e');
              }
              notifyListeners();
            },
            onError: (error) {
              _schedulesLoaded = false;
              debugPrint('[FeederService] Schedules stream error: $error');
              notifyListeners();
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
                        status: data['status'] as String?,
                        commandId: data['command_id'] as String?,
                        requestedGrams: (data['requested_grams'] as num?)
                            ?.toDouble(),
                        estimatedDispensedGrams:
                            (data['estimated_dispensed_grams'] as num?)
                                ?.toDouble(),
                        occurrenceTimestamp: data['occurrence_at'] == null
                            ? null
                            : _parseLoggedAtMillis(data['occurrence_at']),
                        estimatedAvailableGrams:
                            (data['estimated_available_grams'] as num?)
                                ?.toDouble(),
                        feedLevelBefore: (data['feed_level_before'] as num?)
                            ?.toDouble(),
                        feedLevelAfter: (data['feed_level_after'] as num?)
                            ?.toDouble(),
                        levelChangeDetected:
                            data['level_change_detected'] as bool?,
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

  Future<bool> feedNow({
    double? grams,
    bool nearScheduleConfirmed = false,
  }) async {
    // Recheck after any confirmation dialog, immediately before dispatch.
    // Callers outside ControlsScreen receive exactly the same protections.
    final issue = feedSafetyIssue(grams: grams);
    if (issue.isNotEmpty) {
      _lastFeedRequestError = issue;
      return false;
    }
    final guard = manualFeedScheduleGuard(_schedules, _manilaNow());
    if (guard.isBlocked ||
        (guard.needsConfirmation && !nearScheduleConfirmed)) {
      _lastFeedRequestError = guard.isBlocked
          ? 'Scheduled feeding is due. Feed Now is temporarily unavailable.'
          : 'Confirm the nearby scheduled feeding before using Feed Now.';
      return false;
    }
    _lastQueuedCommandId = null;
    final tankDoc = _tankDoc();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (tankDoc == null || uid == null || uid != _tankId) {
      _lastFeedRequestError = 'Sign in to the owner account before feeding.';
      return false;
    }
    _lastFeedRequestError = null;
    _manualRequestPendingUntil = DateTime.now().add(
      const Duration(seconds: 60),
    );
    try {
      // New structure: tanks/{tank_id}/feeder_commands/{autoId}
      // ESP32 listens here, executes, then deletes the command.
      final cmd = <String, dynamic>{
        'command_type': 'feed_now',
        'issued_by': uid,
        'issued_at': FieldValue.serverTimestamp(),
        'near_schedule_confirmed': nearScheduleConfirmed,
        // A queued offline write must not become a fresh motor command when
        // Firestore finally commits its server timestamp after reconnect.
        'expires_at': Timestamp.fromDate(
          DateTime.now().add(const Duration(seconds: 60)),
        ),
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      final ref = tankDoc.collection('feeder_commands').doc();
      _lastQueuedCommandId = ref.id;
      await ref.set(cmd);
      // NOTE: do NOT write a feeder_logs entry here.
      // The ESP32 writes the confirmed log after the servo physically completes,
      // which is the reliable source of truth. Writing here too causes duplicates.
      // Scheduled dispatch is owned by the ESP32 (it compares its synced
      // schedules against its own NTP-synced clock); the app does not enqueue
      // feed commands on a schedule.
      notifyListeners();
      return true;
    } catch (e) {
      // The command never reached Firestore, so release the local pending lock
      // immediately. Keeping it set would falsely block a retry for 60 seconds.
      _manualRequestPendingUntil = null;
      _lastQueuedCommandId = null;
      _lastFeedRequestError =
          'Could not send the Feed Now command. Check your connection.';
      debugPrint('[FeederService] feedNow error: $e');
      notifyListeners();
      return false;
    }
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
    if (_tankDoc() == null) {
      throw StateError(
        'No tank is connected to this account. Ask the admin to assign the hardware first.',
      );
    }
    final requested = ScheduleItem(time, ampm, grams: grams, days: days);
    final doseError = validateFeederGrams(grams);
    if (doseError != null) throw ArgumentError(doseError);
    _throwIfScheduleConflicts(requested);
    await _mutateSchedule({
      'operation': 'add',
      'time': time,
      'ampm': ampm,
      'grams': grams,
      'days': days,
      'enabled': true,
    }, requested: requested);
    notifyListeners();
  }

  String getScheduleTime(int index) {
    if (index < 0 || index >= _schedules.length) return '';
    final s = _schedules[index];
    return '${s.time} ${s.ampm}';
  }

  Future<void> deleteSchedule(int index) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    if (_tankDoc() == null) return;
    await _mutateSchedule({
      'operation': 'delete',
      'scheduleId': _scheduleKeys[index],
    });
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
    if (_tankDoc() == null) return;
    final scheduleKey = _scheduleKeys[index];
    final previous = _schedules[index];

    if (enabled) {
      final doseError = validateFeederGrams(previous.grams);
      if (doseError != null) throw ArgumentError(doseError);
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
      await _mutateSchedule({
        'operation': 'toggle',
        'scheduleId': scheduleKey,
        'enabled': enabled,
      }, requested: previous);
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
      rethrow;
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
    if (_tankDoc() == null) return;
    final requested = ScheduleItem(
      time,
      ampm,
      enabled: enabled ?? _schedules[index].enabled,
      grams: grams,
      days: days,
    );
    _throwIfScheduleConflicts(requested, excludingIndex: index);
    final doseError = validateFeederGrams(grams);
    if (doseError != null) throw ArgumentError(doseError);
    await _mutateSchedule({
      'operation': 'edit',
      'scheduleId': _scheduleKeys[index],
      'time': time,
      'ampm': ampm,
      'enabled': requested.enabled,
      'grams': clearGrams ? null : grams,
      'days': days,
    }, requested: requested);
    notifyListeners();
  }

  /// The callable validates against current schedules inside a server
  /// transaction. The local conflict check only provides immediate feedback.
  /// All schedule and audit writes commit together, including two-phone edits.
  Future<void> _mutateSchedule(
    Map<String, dynamic> payload, {
    ScheduleItem? requested,
  }) async {
    if (!ConnectivityService.instance.isOnline) {
      throw StateError('Connect to the internet to update feeding schedules.');
    }
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('mutateFeederSchedule').call(payload);
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final conflict = details is Map ? details['conflictingSchedule'] : null;
      if (error.code == 'already-exists' &&
          requested != null &&
          conflict is Map) {
        throw FeederScheduleConflictException(
          requested,
          ScheduleItem(
            conflict['time']?.toString() ?? requested.time,
            conflict['ampm']?.toString() ?? requested.ampm,
            days: conflict['days']?.toString() ?? '1111111',
          ),
        );
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw StateError(
          'Could not confirm the schedule update. Check the schedules before retrying.',
        );
      }
      throw StateError(
        error.message ?? 'Could not update the feeding schedule.',
      );
    }
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
      if (_scheduleCheckInProgress) return;
      _scheduleCheckInProgress = true;
      unawaited(
        _checkSchedules()
            .catchError((Object error) {
              debugPrint(
                '[FeederService] Schedule reconciliation failed: $error',
              );
            })
            .whenComplete(() => _scheduleCheckInProgress = false),
      );
    });
  }

  Future<void> _checkSchedules() async {
    final generation = _listenerGeneration;
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    _listenTodayTotals();
    final now = _manilaNow();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastCheckDate != todayKey) {
      // Wait until the Firestore listener has loaded the schedule keys. If the
      // timer marks the date first while the list is still empty, yesterday's
      // isDone values would never be reset after startup.
      if (_scheduleKeys.isEmpty) return;
      _missedLogged.clear();
      // Device outcomes carry their occurrence date; never reset them on app startup.
      _lastCheckDate = todayKey;
    }

    for (int i = 0; i < _schedules.length; i++) {
      if (generation != _listenerGeneration) return;
      final s = _schedules[i];
      if (!s.enabled || feederRecordedOutcome(s, now, _logs) != null) continue;
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

      final expectedDate = '${_months[now.month - 1]} ${now.day}, ${now.year}';
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
        const reason = 'Awaiting device confirmation';
        // Use a deterministic document ID so an app restart or multiple
        // devices cannot write duplicate "Feed skipped" logs for the same
        // schedule on the same Manila day.
        final missedDocId = 'missed_${todayKey}_${key}_$scheduleMinutes'
            .replaceAll('/', '_')
            .replaceAll(RegExp(r'[^\w.\-]'), '_');
        final missedRef = tankDoc.collection('feeder_logs').doc(missedDocId);
        var alreadyExists = false;
        try {
          alreadyExists = (await missedRef.get(
            const GetOptions(source: Source.cache),
          )).exists;
        } catch (_) {
          // No cached snapshot is normal on the first run or while offline.
        }
        if (generation != _listenerGeneration) return;

        if (alreadyExists) {
          _missedLogged.add(occurrenceKey);
          continue;
        }

        try {
          await missedRef.set({
            'action': reason,
            'type': 'pending_confirmation',
            // Store the real current UTC instant. `now` is only a Manila
            // wall-clock view used for schedule comparison/date keys.
            'logged_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            'schedule_key': key,
            'schedule_time': expectedTime,
          });
          if (generation != _listenerGeneration) return;
          _missedLogged.add(occurrenceKey);
          debugPrint('[FeederService] Missed schedule: $key ($reason)');
        } catch (e) {
          // Do not mark the occurrence as handled when the write failed. A
          // later timer pass may retry after connectivity/permission recovers.
          debugPrint('[FeederService] Pending confirmation write failed: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _listenerGeneration++;
    _todayLogsSub?.cancel();
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _authSub?.cancel();
    _authSub = null;
    _scheduleTimer?.cancel();
    ConnectivityService.instance.removeOnConnectCallback(_onReconnect);
    _initialized = false;
    super.dispose();
  }
}
