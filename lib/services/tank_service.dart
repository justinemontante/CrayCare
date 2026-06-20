import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'settings_service.dart';

enum GrowthStage {
  earlyJuvenile(
    'Early Juvenile',
    '1-5g',
    '2-4cm',
    'Nursery / Initial Stocking',
    'SRAC Pub 244',
  ),
  advancedJuvenile(
    'Advanced Juvenile',
    '5-15g',
    '4-6cm',
    'Pre-Grow-out',
    'Queensland Gov',
  ),
  preAdult('Pre-Adult', '15-50g', '6-10cm', 'Active Growth', 'FAO / SRAC'),
  marketSize(
    'Market Size / Adult',
    '50-120g+',
    '10cm+',
    'Harvest / Broodstock',
    'Queensland Gov / SRAC',
  );

  final String label;
  final String weightRange;
  final String lengthRange;
  final String subPhase;
  final String source;

  const GrowthStage(
    this.label,
    this.weightRange,
    this.lengthRange,
    this.subPhase,
    this.source,
  );
}

class SamplingEntry {
  final DateTime date;
  final double abw;
  final double avgLength;
  final int sampleSize;
  final double totalWeight;
  final double totalLength;
  final double biomass;
  final int liveCount;
  final bool isBaseline;

  SamplingEntry({
    required this.date,
    required this.abw,
    required this.avgLength,
    required this.sampleSize,
    required this.totalWeight,
    required this.totalLength,
    required this.biomass,
    required this.liveCount,
    this.isBaseline = false,
  });
}

class TankActivity {
  final String action;
  final String date;
  final String time;
  final String type;
  final int timestamp;

  TankActivity({
    required this.action,
    required this.date,
    required this.time,
    required this.type,
    this.timestamp = 0,
  });
}

class MortalityEntry {
  final DateTime date;
  final int count;
  MortalityEntry({required this.date, required this.count});
}

class TankService extends ChangeNotifier {
  static final TankService instance = TankService._();
  TankService._();

  static Map<String, dynamic> _convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  int _initialCount = 0;
  int _mortality = 0;
  bool _isInitialized = false;
  bool _setupComplete = false;
  DateTime _stockingDate = DateTime.now();
  DateTime _lastSampleDate = DateTime.now();

  // ─── Firebase refs (shared tank_data path: lahat ay pwedeng magbasa, owner lang magsulat) ───
  String _tankOwnerUid = '';
  DatabaseReference get _inventoryRef =>
      FirebaseDatabase.instance.ref('tank_data/$_tankOwnerUid/inventory');
  DatabaseReference get _samplingRef =>
      FirebaseDatabase.instance.ref('tank_data/$_tankOwnerUid/sampling');
  DatabaseReference get _mortalityRef =>
      FirebaseDatabase.instance.ref('tank_data/$_tankOwnerUid/mortality');
  DatabaseReference get _activitiesRef =>
      FirebaseDatabase.instance.ref('tank_data/$_tankOwnerUid/logs');

  // Baseline Sampling Data
  int _sampleCount = 0;
  double _initialWeight = 0.0;   // ABW (average body weight) — computed from total / sampleCount
  double _initialLength = 0.0;   // ABL (average body length) — computed from total / sampleCount
  double _totalSampleWeight = 0.0;  // Raw total weight entered by user
  double _totalSampleLength = 0.0;  // Raw total length entered by user
  List<SamplingEntry> _samplingHistory = [];
  String? _lastSamplingPushKey;
  List<TankActivity> _activities = [];
  List<MortalityEntry> _mortalityHistory = [];

  bool get isInitialized => _isInitialized;
  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get liveCount => _initialCount - _mortality;
  double get survivalRate =>
      _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;
  int get daysInCulture {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(DateTime(_stockingDate.year, _stockingDate.month, _stockingDate.day)).inDays;
  }

  int get daysSinceLastSampling {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_samplingHistory.isEmpty) return daysInCulture;
    final last = _samplingHistory.last.date;
    return today.difference(DateTime(last.year, last.month, last.day)).inDays;
  }

  bool get canSample => daysSinceLastSampling >= 7;

  int get daysUntilNextSampling {
    final daysPassed = daysSinceLastSampling;
    final remaining = 7 - daysPassed;
    return remaining < 0 ? 0 : remaining;
  }

  int get sampleCount => _sampleCount;
  double get initialWeight => _initialWeight;      // ABW
  double get initialLength => _initialLength;      // ABL
  double get initialTotalWeight => _totalSampleWeight;   // Total weight of initial sample
  double get initialTotalLength => _totalSampleLength;   // Total length of initial sample

  List<SamplingEntry> get samplingHistory =>
      List.unmodifiable(_samplingHistory);
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);
  List<MortalityEntry> get mortalityHistory =>
      List.unmodifiable(_mortalityHistory);

  int get totalMortality {
    return _mortalityHistory.fold(0, (sum, e) => sum + e.count);
  }

  GrowthStage get currentGrowthStage {
    final latest = _samplingHistory.isNotEmpty ? _samplingHistory.last : null;
    final abw = latest?.abw ?? _initialWeight;
    final abl = latest?.avgLength ?? _initialLength;
    if (abw < 5 || abl < 4) return GrowthStage.earlyJuvenile;
    if (abw < 15 || abl < 6) return GrowthStage.advancedJuvenile;
    if (abw < 50 || abl < 10) return GrowthStage.preAdult;
    return GrowthStage.marketSize;
  }

  bool _firstAuthEvent = true;

  // --- INITIALIZATION ---
  void init() async {
    _tankOwnerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Check profile early to detect monitor and load correct data from the start
    await _checkProfileForMonitor();
    await _loadConfig();
    _listenFirebase();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_firstAuthEvent) {
        _firstAuthEvent = false;
        return;
      }
      _cancelSubscriptions();
      if (user != null) {
        _tankOwnerUid = user.uid;
        _loadConfig();
        _listenFirebase();
      } else {
        _resetAll();
      }
    });
  }

  Future<void> _checkProfileForMonitor() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseDatabase.instance
          .ref('users/$uid/profile/ownerUid')
          .get();
      final ownerUid = snap.value as String?;
      if (ownerUid != null && ownerUid.isNotEmpty) {
        debugPrint('[TankService] Monitor detected in init, ownerUid=$ownerUid');
        _tankOwnerUid = ownerUid;
      }
    } catch (e) {
      debugPrint('[TankService] _checkProfileForMonitor error: $e');
    }
  }

  /// Called by [MainShell] when profile confirms user is a monitor.
  /// Switches all reads to the owner's tank_data path.
  Future<void> switchToOwnerUid(String ownerUid) async {
    if (ownerUid == _tankOwnerUid) return;
    debugPrint('[TankService] switchToOwnerUid -> $ownerUid (was $_tankOwnerUid)');
    _cancelSubscriptions();
    _tankOwnerUid = ownerUid;
    await _loadConfig();
    _listenFirebase();
    notifyListeners();
  }

  Future<void> _loadConfig() async {
    try {
      final path = _inventoryRef.path;
      debugPrint('[TankService] _loadConfig from path: $path');
      final snap = await _inventoryRef.get();
      if (!snap.exists) {
        debugPrint('[TankService] _loadConfig: snapshot does NOT exist at $path');
        return;
      }
      final data = _convertMap(snap.value as Map);
      final isInit = (data['isInitialized'] as bool?) ?? false;
      debugPrint('[TankService] _loadConfig: exists, isInitialized=$isInit');
      if (!isInit) {
        _resetAll();
        await _inventoryRef.remove();
        await _mortalityRef.remove();
        await _samplingRef.remove();
        await _activitiesRef.remove();
        return;
      }
      _initialCount = (data['initialPopulation'] as int?) ?? 0;
      _mortality = (data['Mortality'] as int?) ?? 0;
      _stockingDate = DateTime.fromMillisecondsSinceEpoch(
        (data['stockingDate'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );
      _sampleCount = (data['sampleCount'] as int?) ?? 0;
      _totalSampleWeight = (data['initialTotalSampleWeight'] as num?)?.toDouble() ?? 0.0;
      _totalSampleLength = (data['initialTotalSampleLength'] as num?)?.toDouble() ?? 0.0;
      if (data.containsKey('initialSampleWeight')) {
        _initialWeight = (data['initialSampleWeight'] as num?)?.toDouble() ?? 0.0;
        _initialLength = (data['initialSampleLength'] as num?)?.toDouble() ?? 0.0;
        _totalSampleWeight = _initialWeight * _sampleCount;
        _totalSampleLength = _initialLength * _sampleCount;
      } else {
        _initialWeight = _sampleCount > 0 ? _totalSampleWeight / _sampleCount : 0.0;
        _initialLength = _sampleCount > 0 ? _totalSampleLength / _sampleCount : 0.0;
      }
      _lastSampleDate = DateTime.fromMillisecondsSinceEpoch(
        (data['lastSampleDate'] as int?) ?? _stockingDate.millisecondsSinceEpoch,
      );
      _isInitialized = isInit;
      _setupComplete = isInit;
      notifyListeners();
    } catch (e) {
      debugPrint('[TankService] loadConfig ERROR: $e');
    }
  }

  void _resetAll() {
    _initialCount = 0;
    _mortality = 0;
    _sampleCount = 0;
    _initialWeight = 0.0;
    _initialLength = 0.0;
    _totalSampleWeight = 0.0;
    _totalSampleLength = 0.0;
    _isInitialized = false;
    _setupComplete = false;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();
    notifyListeners();
  }

  StreamSubscription<DatabaseEvent>? _inventorySub;
  StreamSubscription<DatabaseEvent>? _mortalitySub;
  StreamSubscription<DatabaseEvent>? _samplingSub;
  StreamSubscription<DatabaseEvent>? _activitiesSub;

  void _cancelSubscriptions() {
    _inventorySub?.cancel();
    _mortalitySub?.cancel();
    _samplingSub?.cancel();
    _activitiesSub?.cancel();
    _inventorySub = null;
    _mortalitySub = null;
    _samplingSub = null;
    _activitiesSub = null;
  }

  void _listenFirebase() {
    _inventorySub = _inventoryRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _resetAll();
        return;
      }
      final data = _convertMap(e.snapshot.value as Map);
      final isInit = (data['isInitialized'] as bool?) ?? false;
      if (!isInit) return;
      _isInitialized = true;
      _setupComplete = true;
      _initialCount = (data['initialPopulation'] as int?) ?? _initialCount;
      _mortality = (data['Mortality'] as int?) ?? _mortality;
      _sampleCount = (data['sampleCount'] as int?) ?? _sampleCount;
      _totalSampleWeight = (data['initialTotalSampleWeight'] as num?)?.toDouble() ?? _totalSampleWeight;
      _totalSampleLength = (data['initialTotalSampleLength'] as num?)?.toDouble() ?? _totalSampleLength;
      _initialWeight = _sampleCount > 0 ? _totalSampleWeight / _sampleCount : 0.0;
      _initialLength = _sampleCount > 0 ? _totalSampleLength / _sampleCount : 0.0;
      if (data.containsKey('stockingDate')) {
        _stockingDate = DateTime.fromMillisecondsSinceEpoch(
          data['stockingDate'] as int,
        );
      }
      if (data.containsKey('lastSampleDate')) {
        _lastSampleDate = DateTime.fromMillisecondsSinceEpoch(
          data['lastSampleDate'] as int,
        );
      }
      notifyListeners();
    });

    _samplingSub = _samplingRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _samplingHistory.clear();
        _lastSamplingPushKey = null;
        notifyListeners();
        return;
      }
      final sData = _convertMap(e.snapshot.value as Map);
      final entries = <SamplingEntry>[];
      String? lastKey;
      DateTime? lastDate;
      for (final entry in sData.entries) {
        final map = _convertMap(entry.value as Map);
        final date = DateTime.fromMillisecondsSinceEpoch(map['date']);
        entries.add(SamplingEntry(
          date: date,
          abw: (map['abw'] as num).toDouble(),
          avgLength: (map['avgLength'] as num).toDouble(),
          sampleSize: map['sampleSize'],
          totalWeight: (map['totalWeight'] as num).toDouble(),
          totalLength: (map['totalLength'] as num).toDouble(),
          biomass: (map['biomass'] as num).toDouble(),
          liveCount: map['liveCount'],
          isBaseline: map['isBaseline'] == true,
        ));
        if (lastDate == null || date.isAfter(lastDate)) {
          lastDate = date;
          lastKey = entry.key;
        }
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      _samplingHistory = entries;
      _lastSamplingPushKey = lastKey;
      notifyListeners();
    });

    _mortalitySub = _mortalityRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _mortalityHistory.clear();
        notifyListeners();
        return;
      }
      final mData = _convertMap(e.snapshot.value as Map);
      _mortalityHistory = mData.values.map((e) {
        final map = _convertMap(e as Map);
        return MortalityEntry(
          date: DateTime.fromMillisecondsSinceEpoch(map['date']),
          count: map['count'],
        );
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    });

    _activitiesSub = _activitiesRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _activities.clear();
        notifyListeners();
        return;
      }
      final aData = _convertMap(e.snapshot.value as Map);
      _activities = aData.values.map((e) {
        final map = _convertMap(e as Map);
        return TankActivity(
          action: map['action'],
          date: map['date'],
          time: map['time'],
          type: map['type'],
          timestamp: map['timestamp'] ?? 0,
        );
      }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
    });
  }

  Future<void> _saveConfig() async {
    if (!_setupComplete) return;
    try {
      await _inventoryRef.set({
        'initialPopulation': _initialCount,
        'stockingDate': _stockingDate.millisecondsSinceEpoch,
        'lastSampleDate': _lastSampleDate.millisecondsSinceEpoch,
        'Mortality': _mortality,
        'sampleCount': _sampleCount,
        'initialTotalSampleWeight': _totalSampleWeight,
        'initialTotalSampleLength': _totalSampleLength,
        'Alive': _initialCount - _mortality,
        'isInitialized': _isInitialized,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[TankService] saveConfig error: $e');
    }
  }

  Future<void> resetExperiment() async {
    _initialCount = 0;
    _mortality = 0;
    _sampleCount = 0;
    _initialWeight = 0.0;
    _initialLength = 0.0;
    _totalSampleWeight = 0.0;
    _totalSampleLength = 0.0;
    _isInitialized = false;
    _setupComplete = false;

    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();

    await _inventoryRef.remove();
    await _samplingRef.remove();
    await _mortalityRef.remove();
    await _activitiesRef.remove();

    notifyListeners();
  }

  Future<void> initializeGrowOut(
    int initial,
    int sampleCount,
    double totalWeight,
    double totalLength,
    DateTime date,
  ) async {
    bool isNewSetup = !_isInitialized;

    _initialCount = initial;
    if (isNewSetup) {
      _stockingDate = date;
      _lastSampleDate = date;
    }
    _sampleCount = sampleCount;
    _totalSampleWeight = totalWeight;
    _totalSampleLength = totalLength;
    _initialWeight = sampleCount > 0 ? (totalWeight / sampleCount) : 0.0;
    _initialLength = sampleCount > 0 ? (totalLength / sampleCount) : 0.0;
    _isInitialized = true;
    _setupComplete = true;

    _mortality = 0;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();

    await Future.wait([
      _samplingRef.remove(),
      _mortalityRef.remove(),
      _activitiesRef.remove(),
    ]);

    _addActivity(
      isNewSetup
          ? 'Initialized grow-out with $initial population'
          : 'Updated setup configuration',
      isNewSetup ? 'init' : 'edit',
      customDate: date,
    );

    await _saveConfig();
    SettingsService.instance.autoDetectStage(_initialWeight, _initialLength);
    notifyListeners();
  }

  void addSamplingEntry(int count, double weight, double length) {
    _setupComplete = true;
    final now = DateTime.now();
    _lastSampleDate = now;
    final abw = weight / count;
    final avgLength = length / count;
    final entry = SamplingEntry(
      date: now,
      abw: abw,
      avgLength: avgLength,
      sampleSize: count,
      totalWeight: weight,
      totalLength: length,
      biomass: liveCount * abw,
      liveCount: liveCount,
    );
    _samplingHistory.add(entry);
    _samplingRef.push().set({
      'date': entry.date.millisecondsSinceEpoch,
      'abw': entry.abw,
      'avgLength': entry.avgLength,
      'sampleSize': entry.sampleSize,
      'totalWeight': entry.totalWeight,
      'totalLength': entry.totalLength,
      'biomass': entry.biomass,
      'liveCount': entry.liveCount,
      'isBaseline': false,
      'timestamp': ServerValue.timestamp,
    });
    _addActivity(
      'Recorded sampling: ${abw.toStringAsFixed(2)}g ABW',
      'sampling',
    );
    _saveConfig();
    SettingsService.instance.autoDetectStage(abw, avgLength);
    notifyListeners();
  }

  void updateLastSamplingEntry(int count, double weight, double length) {
    if (_lastSamplingPushKey == null || _samplingHistory.isEmpty) return;
    final abw = weight / count;
    final avgLength = length / count;
    final updated = SamplingEntry(
      date: _samplingHistory.last.date,
      abw: abw,
      avgLength: avgLength,
      sampleSize: count,
      totalWeight: weight,
      totalLength: length,
      biomass: liveCount * abw,
      liveCount: liveCount,
    );
    _samplingHistory.last = updated;
    _samplingRef.child(_lastSamplingPushKey!).update({
      'abw': updated.abw,
      'avgLength': updated.avgLength,
      'sampleSize': updated.sampleSize,
      'totalWeight': updated.totalWeight,
      'totalLength': updated.totalLength,
      'biomass': updated.biomass,
      'liveCount': updated.liveCount,
      'timestamp': ServerValue.timestamp,
    });
    _saveConfig();
    SettingsService.instance.autoDetectStage(abw, avgLength);
    notifyListeners();
  }

  void addMortality(int val, {DateTime? date}) {
    _mortality += val;
    _setupComplete = true;
    final mEntry = MortalityEntry(
      date: date ?? DateTime.now(),
      count: val,
    );
    _mortalityHistory.add(mEntry);
    _mortalityRef.push().set({
      'date': mEntry.date.millisecondsSinceEpoch,
      'count': mEntry.count,
      'timestamp': ServerValue.timestamp,
    });
    _addActivity(
      'Recorded mortality of $val crayfish (Total: $_mortality)',
      'mortality',
      customDate: date,
    );
    _saveConfig();
    notifyListeners();
  }

  void _addActivity(String action, String type, {DateTime? customDate}) {
    final now = customDate ?? DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    final timestamp = now.millisecondsSinceEpoch;

    final act = TankActivity(
      action: action,
      date: dateStr,
      time: timeStr,
      type: type,
      timestamp: timestamp,
    );
    _activities.add(act);

    _activitiesRef.push().set({
      'action': action,
      'date': dateStr,
      'time': timeStr,
      'type': type,
      'timestamp': timestamp,
    });
  }
}
