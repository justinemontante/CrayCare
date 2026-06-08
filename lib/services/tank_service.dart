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
  final String recordedBy;

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
    this.recordedBy = '',
  });
}

class TankActivity {
  final String action;
  final String date;
  final String time;
  final String type;
  final int timestamp;
  final String recordedBy;

  TankActivity({
    required this.action,
    required this.date,
    required this.time,
    required this.type,
    this.timestamp = 0,
    this.recordedBy = '',
  });
}

class MortalityEntry {
  final DateTime date;
  final int count;
  final String recordedBy;
  MortalityEntry({required this.date, required this.count, this.recordedBy = ''});
}

class TankService extends ChangeNotifier {
  static final TankService instance = TankService._();
  TankService._();

  int _initialCount = 0;
  int _mortality = 0;
  bool _isInitialized = false;
  bool _setupComplete = false;
  DateTime _stockingDate = DateTime.now();

  // ─── Firebase refs (Naka-set para pare-pareho kayong 5 na makakita ng iisang data) ───
  final DatabaseReference _configRef = FirebaseDatabase.instance.ref(
    'tank/config',
  );
  final DatabaseReference _samplingRef = FirebaseDatabase.instance.ref(
    'tank/sampling',
  );
  final DatabaseReference _mortalityRef = FirebaseDatabase.instance.ref(
    'tank/mortality',
  );
  final DatabaseReference _activitiesRef = FirebaseDatabase.instance.ref(
    'tank/activities',
  );

  // Baseline Sampling Data
  int _sampleCount = 0;
  double _initialWeight = 0.0;
  double _initialLength = 0.0;
  String _recordedBy = '';

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
  String get recordedBy => _recordedBy;

  List<SamplingEntry> get samplingHistory =>
      List.unmodifiable(_samplingHistory);
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);
  List<MortalityEntry> get mortalityHistory =>
      List.unmodifiable(_mortalityHistory);

  String _getUserName() {
    return FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
  }

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
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await _configRef.get();
      if (!snap.exists) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
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
      _recordedBy = data['recordedBy'] as String? ?? '';
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
    _recordedBy = '';
    _isInitialized = false;
    _setupComplete = false;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();
    notifyListeners();
  }

  Future<void> _loadHistoryData() async {
    try {
      // Load Mortality
      final mSnap = await _mortalityRef.get();
      if (mSnap.exists) {
        final mData = Map<String, dynamic>.from(mSnap.value as Map);
        _mortalityHistory = mData.values.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return MortalityEntry(
            date: DateTime.fromMillisecondsSinceEpoch(map['date']),
            count: map['count'],
            recordedBy: map['recordedBy'] as String? ?? '',
          );
        }).toList()..sort((a, b) => a.date.compareTo(b.date));
      }

      // Load Sampling
      final sSnap = await _samplingRef.get();
      if (sSnap.exists) {
        final sData = Map<String, dynamic>.from(sSnap.value as Map);
        _samplingHistory = sData.values.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
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
            recordedBy: map['recordedBy'] as String? ?? '',
          );
        }).toList()..sort((a, b) => a.date.compareTo(b.date));
      }

      // Load Activities
      final aSnap = await _activitiesRef.get();
      if (aSnap.exists) {
        final aData = Map<String, dynamic>.from(aSnap.value as Map);
        _activities = aData.values.map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return TankActivity(
            action: map['action'],
            date: map['date'],
            time: map['time'],
            type: map['type'],
            timestamp: map['timestamp'] ?? 0,
            recordedBy: map['recordedBy'] as String? ?? '',
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

  void _listenFirebase() {
    _configSub = _configRef.onValue.listen((e) {
      if (!e.snapshot.exists) {
        _resetAll();
        return;
      }
      final data = Map<String, dynamic>.from(e.snapshot.value as Map);
      final isInit = (data['isInitialized'] as bool?) ?? false;
      if (!isInit) return;
      _initialCount = (data['initialPopulation'] as int?) ?? _initialCount;
      _mortality = (data['Mortality'] as int?) ?? _mortality;
      _sampleCount = (data['sampleCount'] as int?) ?? _sampleCount;
      _initialWeight = (data['initialSampleWeight'] as num?)?.toDouble() ?? 0.0;
      _initialLength = (data['initialSampleLength'] as num?)?.toDouble() ?? 0.0;
      _recordedBy = data['recordedBy'] as String? ?? _recordedBy;
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
      final sData = Map<String, dynamic>.from(e.snapshot.value as Map);
      _samplingHistory = sData.values.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return SamplingEntry(
          date: DateTime.fromMillisecondsSinceEpoch(map['date']),
          abw: (map['abw'] as num).toDouble(),
          avgLength: (map['avgLength'] as num).toDouble(),
          sampleSize: map['sampleSize'],
          totalWeight: (map['totalWeight'] as num).toDouble(),
          totalLength: (map['totalLength'] as num).toDouble(),
          biomass: (map['biomass'] as num).toDouble(),
          liveCount: map['liveCount'],
          recordedBy: map['recordedBy'] as String? ?? '',
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
      final mData = Map<String, dynamic>.from(e.snapshot.value as Map);
      _mortalityHistory = mData.values.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return MortalityEntry(
          date: DateTime.fromMillisecondsSinceEpoch(map['date']),
          count: map['count'],
          recordedBy: map['recordedBy'] as String? ?? '',
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
      final aData = Map<String, dynamic>.from(e.snapshot.value as Map);
      _activities = aData.values.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return TankActivity(
          action: map['action'],
          date: map['date'],
          time: map['time'],
          type: map['type'],
          timestamp: map['timestamp'] ?? 0,
          recordedBy: map['recordedBy'] as String? ?? '',
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
        'recordedBy': _recordedBy,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[TankService] saveConfig error: $e');
    }
  }

  // --- BAGONG FUNCTION: Gamitin ito para ma-wipeout yung test data ---
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
    _recordedBy = _getUserName();

    // Always reset mortality and history on init
    _mortality = 0;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();

    // Await para siguradong natanggal ang lumang data bago mag-save
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
    final userName = _getUserName();
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
      recordedBy: userName,
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
      'recordedBy': userName,
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
    final userName = _getUserName();
    final mEntry = MortalityEntry(
      date: date ?? DateTime.now(),
      count: val,
      recordedBy: userName,
    );
    _mortalityHistory.add(mEntry);
    _mortalityRef.push().set({
      'date': mEntry.date.millisecondsSinceEpoch,
      'count': mEntry.count,
      'recordedBy': userName,
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
    final userName = _getUserName();
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
      recordedBy: userName,
    );
    _activities.add(act);

    _activitiesRef.push().set({
      'action': action,
      'date': dateStr,
      'time': timeStr,
      'type': type,
      'recordedBy': userName,
      'timestamp': timestamp,
    });
  }
}
