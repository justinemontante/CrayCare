import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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
  growOut('Grow-out Phase', '15-50g', '6-10cm', 'Active Growth', 'FAO / SRAC'),
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

  // ─── Firebase refs (per-user: bawat account ay may kanya-kanyang data) ───
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';
  DatabaseReference get _configRef =>
      FirebaseDatabase.instance.ref('users/$_userId/tank/config');
  DatabaseReference get _samplingRef =>
      FirebaseDatabase.instance.ref('users/$_userId/tank/sampling');
  DatabaseReference get _mortalityRef =>
      FirebaseDatabase.instance.ref('users/$_userId/tank/mortality');
  DatabaseReference get _activitiesRef =>
      FirebaseDatabase.instance.ref('users/$_userId/tank/activities');

  // Baseline Sampling Data
  int _sampleCount = 0;
  double _initialWeight = 0.0;
  double _initialLength = 0.0;
  List<SamplingEntry> _samplingHistory = [];
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
  double get initialWeight => _initialWeight;
  double get initialLength => _initialLength;

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
    if (abw < 5) return GrowthStage.earlyJuvenile;
    if (abw < 15) return GrowthStage.advancedJuvenile;
    if (abw < 50) return GrowthStage.growOut;
    return GrowthStage.marketSize;
  }

  // --- INITIALIZATION ---
  void init() async {
    await _loadConfig();
    _listenFirebase();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _cancelSubscriptions();
        _loadConfig();
        _listenFirebase();
      }
    });
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await _configRef.get();
      if (!snap.exists) return;
      final data = _convertMap(snap.value as Map);
      final isInit = (data['isInitialized'] as bool?) ?? false;
      if (!isInit) {
        _resetAll();
        await _configRef.remove();
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
      _initialWeight = (data['initialSampleWeight'] as num?)?.toDouble() ?? 0.0;
      _initialLength = (data['initialSampleLength'] as num?)?.toDouble() ?? 0.0;
      _isInitialized = isInit;
      _setupComplete = isInit;
      notifyListeners();
    } catch (e) {
      debugPrint('[TankService] loadConfig error: $e');
    }
  }

  void _resetAll() {
    _initialCount = 0;
    _mortality = 0;
    _sampleCount = 0;
    _initialWeight = 0.0;
    _initialLength = 0.0;
    _isInitialized = false;
    _setupComplete = false;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();
    notifyListeners();
  }

  Future<void> _loadHistoryData() async {
    try {
      final mSnap = await _mortalityRef.get();
      if (mSnap.exists) {
        final mData = _convertMap(mSnap.value as Map);
        _mortalityHistory = mData.values.map((e) {
          final map = _convertMap(e as Map);
          return MortalityEntry(
            date: DateTime.fromMillisecondsSinceEpoch(map['date']),
            count: map['count'],
          );
        }).toList()..sort((a, b) => a.date.compareTo(b.date));
      }

      final sSnap = await _samplingRef.get();
      if (sSnap.exists) {
        final sData = _convertMap(sSnap.value as Map);
        _samplingHistory = sData.values.map((e) {
          final map = _convertMap(e as Map);
          return SamplingEntry(
            date: DateTime.fromMillisecondsSinceEpoch(map['date']),
            abw: (map['abw'] as num).toDouble(),
            avgLength: (map['avgLength'] as num).toDouble(),
            sampleSize: map['sampleSize'],
            totalWeight: (map['totalWeight'] as num).toDouble(),
            totalLength: (map['totalLength'] as num).toDouble(),
            biomass: (map['biomass'] as num).toDouble(),
            liveCount: map['liveCount'],
            isBaseline: map['isBaseline'] == true,
          );
        }).toList()..sort((a, b) => a.date.compareTo(b.date));
      }

      final aSnap = await _activitiesRef.get();
      if (aSnap.exists) {
        final aData = _convertMap(aSnap.value as Map);
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
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[TankService] loadHistory error: $e');
    }
  }

  StreamSubscription<DatabaseEvent>? _configSub;
  StreamSubscription<DatabaseEvent>? _mortalitySub;
  StreamSubscription<DatabaseEvent>? _samplingSub;
  StreamSubscription<DatabaseEvent>? _activitiesSub;

  void _cancelSubscriptions() {
    _configSub?.cancel();
    _mortalitySub?.cancel();
    _samplingSub?.cancel();
    _activitiesSub?.cancel();
    _configSub = null;
    _mortalitySub = null;
    _samplingSub = null;
    _activitiesSub = null;
  }

  void _listenFirebase() {
    _configSub = _configRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _resetAll();
        return;
      }
      final data = _convertMap(e.snapshot.value as Map);
      final isInit = (data['isInitialized'] as bool?) ?? false;
      if (!isInit) return;
      _initialCount = (data['initialPopulation'] as int?) ?? _initialCount;
      _mortality = (data['Mortality'] as int?) ?? _mortality;
      _sampleCount = (data['sampleCount'] as int?) ?? _sampleCount;
      _initialWeight = (data['initialSampleWeight'] as num?)?.toDouble() ?? 0.0;
      _initialLength = (data['initialSampleLength'] as num?)?.toDouble() ?? 0.0;
      if (data.containsKey('stockingDate')) {
        _stockingDate = DateTime.fromMillisecondsSinceEpoch(
          data['stockingDate'] as int,
        );
      }
      notifyListeners();
    });

    _samplingSub = _samplingRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _samplingHistory.clear();
        notifyListeners();
        return;
      }
      final sData = _convertMap(e.snapshot.value as Map);
      _samplingHistory = sData.values.map((e) {
        final map = _convertMap(e as Map);
        return SamplingEntry(
          date: DateTime.fromMillisecondsSinceEpoch(map['date']),
          abw: (map['abw'] as num).toDouble(),
          avgLength: (map['avgLength'] as num).toDouble(),
          sampleSize: map['sampleSize'],
          totalWeight: (map['totalWeight'] as num).toDouble(),
          totalLength: (map['totalLength'] as num).toDouble(),
          biomass: (map['biomass'] as num).toDouble(),
          liveCount: map['liveCount'],
          isBaseline: map['isBaseline'] == true,
        );
      }).toList()..sort((a, b) => a.date.compareTo(b.date));
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
      await _configRef.set({
        'initialPopulation': _initialCount,
        'stockingDate': _stockingDate.millisecondsSinceEpoch,
        'Mortality': _mortality,
        'sampleCount': _sampleCount,
        'initialSampleWeight': _initialWeight,
        'initialSampleLength': _initialLength,
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
    _isInitialized = false;
    _setupComplete = false;

    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();

    await _configRef.remove();
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
    _stockingDate = date;
    _sampleCount = sampleCount;
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
    notifyListeners();
  }

  void addSamplingEntry(int count, double weight, double length) {
    _setupComplete = true;
    final abw = weight / count;
    final avgLength = length / count;
    final entry = SamplingEntry(
      date: DateTime.now(),
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
