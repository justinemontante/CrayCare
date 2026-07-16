import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/crayfish_batch.dart';

enum GrowthStage {
  earlyJuvenile('Early Juvenile', '1-5g', '2-4cm', 'Nursery / Initial Stocking', 'SRAC Pub 244'),
  advancedJuvenile('Advanced Juvenile', '5-15g', '4-6cm', 'Pre-Grow-out', 'Queensland Gov'),
  preAdult('Pre-Adult', '15-50g', '6-10cm', 'Active Growth', 'FAO / SRAC'),
  marketSize('Market Size / Adult', '50-120g+', '10cm+', 'Harvest / Broodstock', 'Queensland Gov / SRAC');

  final String label;
  final String weightRange;
  final String lengthRange;
  final String subPhase;
  final String source;

  const GrowthStage(this.label, this.weightRange, this.lengthRange, this.subPhase, this.source);
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
  final int? sampleSize;
  final double? abw;
  final double? avgLength;

  TankActivity({
    required this.action,
    required this.date,
    required this.time,
    required this.type,
    this.timestamp = 0,
    this.sampleSize,
    this.abw,
    this.avgLength,
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

  // Active batch state (backward-compatible)
  int _initialCount = 0;
  int _mortality = 0;
  bool _isInitialized = false;
  bool _setupComplete = false;
  DateTime _stockingDate = DateTime.now();
  DateTime _lastSampleDate = DateTime.now();

  // Multi-batch support
  List<CrayfishBatch> _batches = [];
  String? _selectedBatchId;

  // Archive view mode
  bool _isArchiveView = false;

  String _tankOwnerUid = '';

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  int _sampleCount = 0;
  double _initialWeight = 0.0;
  double _initialLength = 0.0;
  double _totalSampleWeight = 0.0;
  double _totalSampleLength = 0.0;
  List<SamplingEntry> _samplingHistory = [];
  String? _lastSamplingDocId;
  List<TankActivity> _activities = [];
  List<MortalityEntry> _mortalityHistory = [];
  List<CrayfishBatch> _harvestHistory = [];
  List<CrayfishHarvestRecord> _harvestRecords = [];
  int _totalHarvested = 0;

  bool get isInitialized => _isInitialized;
  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get totalHarvested => _totalHarvested;
  int get liveCount => _initialCount - _mortality;
  int get inTankCount => (_initialCount - _mortality - _totalHarvested).clamp(0, _initialCount);
  double get survivalRate =>
      _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;

  int get daysInCulture {
    if (_isArchiveView) {
      final batch = selectedBatch;
      if (batch != null) return batch.daysInCulture;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.difference(DateTime(_stockingDate.year, _stockingDate.month, _stockingDate.day)).inDays;
  }

  int get daysSinceLastSampling {
    if (_isArchiveView) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_samplingHistory.isEmpty) return daysInCulture;
    final last = _samplingHistory.last.date;
    return today.difference(DateTime(last.year, last.month, last.day)).inDays;
  }

  bool get hasSamplingThisWeek {
    if (_samplingHistory.isEmpty) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = today.add(Duration(days: 7 - today.weekday));
    for (final entry in _samplingHistory) {
      if (entry.isBaseline) continue;
      final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
      if (!entryDate.isBefore(monday) && !entryDate.isAfter(sunday)) return true;
    }
    return false;
  }

  bool get canSample => daysSinceLastSampling >= 7 && !hasSamplingThisWeek;
  int get daysUntilNextSampling {
    final daysPassed = daysSinceLastSampling;
    final remaining = 7 - daysPassed;
    return remaining < 0 ? 0 : remaining;
  }

  int get sampleCount => _sampleCount;
  double get initialWeight => _initialWeight;
  double get initialLength => _initialLength;
  double get initialTotalWeight => _totalSampleWeight;
  double get initialTotalLength => _totalSampleLength;

  List<SamplingEntry> get samplingHistory => List.unmodifiable(_samplingHistory);
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);
  List<MortalityEntry> get mortalityHistory => List.unmodifiable(_mortalityHistory);
  List<CrayfishBatch> get harvestHistory => List.unmodifiable(_harvestHistory.reversed);
  List<CrayfishHarvestRecord> get harvestRecords {
    final filtered = _selectedBatchId != null
        ? _harvestRecords.where((r) => r.batchId == _selectedBatchId).toList()
        : List<CrayfishHarvestRecord>.from(_harvestRecords);
    return List.unmodifiable(filtered.reversed);
  }

  // Multi-batch getters
  List<CrayfishBatch> get batches => List.unmodifiable(_batches);
  List<CrayfishBatch> get activeBatches =>
      _batches.where((b) => b.status == 'active').toList();
  String? get selectedBatchId => _selectedBatchId;
  CrayfishBatch? get selectedBatch =>
      _selectedBatchId != null
          ? _batches.cast<CrayfishBatch?>().firstWhere(
              (b) => b?.batchId == _selectedBatchId, orElse: () => null)
          : null;

  CrayfishBatch? get activeOrLatestBatch {
    if (_batches.isEmpty) return null;
    final active = _batches.where((b) => b.status == 'active').toList();
    if (active.isNotEmpty) return active.first;
    return _batches.first;
  }

  int get totalMortality => _mortalityHistory.fold(0, (sum, e) => sum + e.count);

  GrowthStage get currentGrowthStage {
    final latest = _samplingHistory.isNotEmpty ? _samplingHistory.last : null;
    final abw = latest?.abw ?? _initialWeight;
    final abl = latest?.avgLength ?? _initialLength;
    if (abw < 5 || abl < 4) return GrowthStage.earlyJuvenile;
    if (abw < 15 || abl < 6) return GrowthStage.advancedJuvenile;
    if (abw < 50 || abl < 10) return GrowthStage.preAdult;
    return GrowthStage.marketSize;
  }

  void init() async {
    final initialUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint('[TankService] init() currentUser.uid="$initialUid"');
    if (initialUid.isNotEmpty) {
      _tankOwnerUid = initialUid;
      await _loadConfig();
      _listenFirebase();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid ?? '';
      debugPrint('[TankService] authStateChanges event: uid="$uid"');
      if (uid.isEmpty) {
        _resetAll();
        return;
      }
      if (uid == _tankOwnerUid) return;
      _tankOwnerUid = uid;
      _cancelSubscriptions();
      _loadConfig().then((_) => _listenFirebase());
    });
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await _fs.collection('config').doc(_tankOwnerUid).get();
      if (!doc.exists) {
        debugPrint('[TankService] _loadConfig: config doc does NOT exist');
        _resetAll();
        return;
      }
      final data = doc.data() ?? <String, dynamic>{};
      final isInit = (data['isInitialized'] as bool?) ?? false;
      if (!isInit) {
        _resetAll();
        return;
      }
      _initialCount = (data['initialPopulation'] as int?) ?? 0;
      _mortality = (data['Mortality'] as int?) ?? 0;
      _totalHarvested = (data['totalHarvested'] as int?) ?? 0;
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
    _totalHarvested = 0;
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
    _harvestRecords.clear();
    notifyListeners();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _samplingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mortalitySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activitiesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _harvestsSub;

  void _cancelSubscriptions() {
    _batchesSub?.cancel();
    _batchesSub = null;
    _samplingSub?.cancel();
    _samplingSub = null;
    _mortalitySub?.cancel();
    _mortalitySub = null;
    _activitiesSub?.cancel();
    _activitiesSub = null;
    _harvestsSub?.cancel();
    _harvestsSub = null;
  }

  void _parseBatchesFromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <CrayfishBatch>[];
    for (final doc in snap.docs) {
      try {
        final map = Map<String, dynamic>.from(doc.data());
        if (map['archivedSampling'] is Map) {
          map['archivedSampling'] = _convertMap(map['archivedSampling'] as Map);
        }
        if (map['archivedMortality'] is Map) {
          map['archivedMortality'] = _convertMap(map['archivedMortality'] as Map);
        }
        if (map['batchId'] == null) {
          debugPrint('[TankService] _parseBatchesFromSnapshot: skipping entry without batchId');
          continue;
        }
        list.add(CrayfishBatch.fromJson(map));
      } catch (e) {
        debugPrint('[TankService] _parseBatchesFromSnapshot: error parsing batch entry: $e');
      }
    }
    list.sort((a, b) => b.stockingDate.compareTo(a.stockingDate));

    _batches = list;
    _harvestHistory = list.where((b) => b.status == 'harvested' || b.status == 'superseded').toList();

    final currentSelectionStillExists = _selectedBatchId != null && list.any((b) => b.batchId == _selectedBatchId);
    if (!currentSelectionStillExists) {
      final active = list.where((b) => b.status == 'active');
      final newBatchId = active.isNotEmpty ? active.first.batchId : null;
      _selectedBatchId = newBatchId;
      if (newBatchId != null) {
        final batch = active.first;
        if (batch.status == 'harvested' || batch.status == 'superseded') {
          _enterArchiveView(batch);
        } else {
          _isArchiveView = false;
          _clearArchiveState();
          _restoreFromBatchRecord(batch);
          _reloadLiveDataFromFirebase();
        }
      }
    }
    notifyListeners();
  }

  bool get isArchiveView => _isArchiveView;

  void _clearArchiveState() {
    _samplingHistory.clear();
    _lastSamplingDocId = null;
    _mortalityHistory.clear();
    _activities.clear();
    _harvestRecords.clear();
    _mortality = 0;
    _totalHarvested = 0;
    _sampleCount = 0;
    _totalSampleWeight = 0.0;
    _totalSampleLength = 0.0;
    _initialWeight = 0.0;
    _initialLength = 0.0;
  }

  void _restoreFromBatchRecord(CrayfishBatch batch) {
    _initialCount = batch.initialCount;
    _initialWeight = batch.initialAbw;
    _initialLength = batch.initialAbl;
    _stockingDate = batch.stockingDate;
    _sampleCount = batch.sampleCount;
    _totalSampleWeight = batch.initialTotalWeight;
    _totalSampleLength = batch.initialTotalLength;
    _isInitialized = true;
    _setupComplete = true;
  }

  Future<void> _reloadLiveDataFromFirebase() async {
    // 1. Load config
    try {
      final doc = await _fs.collection('config').doc(_tankOwnerUid).get();
      if (_isArchiveView) return;
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        final isInit = (data['isInitialized'] as bool?) ?? false;
        if (isInit) {
          _isInitialized = true;
          _setupComplete = true;
          _initialCount = (data['initialPopulation'] as int?) ?? _initialCount;
          _mortality = (data['Mortality'] as int?) ?? _mortality;
          _totalHarvested = (data['totalHarvested'] as int?) ?? _totalHarvested;
          _sampleCount = (data['sampleCount'] as int?) ?? _sampleCount;
          _totalSampleWeight = (data['initialTotalSampleWeight'] as num?)?.toDouble() ?? _totalSampleWeight;
          _totalSampleLength = (data['initialTotalSampleLength'] as num?)?.toDouble() ?? _totalSampleLength;
          if (data['initialSampleWeight'] != null) {
            _initialWeight = (data['initialSampleWeight'] as num).toDouble();
            _initialLength = (data['initialSampleLength'] as num).toDouble();
          } else {
            _initialWeight = _sampleCount > 0 ? _totalSampleWeight / _sampleCount : 0.0;
            _initialLength = _sampleCount > 0 ? _totalSampleLength / _sampleCount : 0.0;
          }
          if (data.containsKey('stockingDate')) {
            _stockingDate = DateTime.fromMillisecondsSinceEpoch(data['stockingDate'] as int);
          }
          if (data.containsKey('lastSampleDate')) {
            _lastSampleDate = DateTime.fromMillisecondsSinceEpoch(data['lastSampleDate'] as int);
          }
        }
      }
    } catch (e) {
      debugPrint('[TankService] _reloadLiveDataFromFirebase loadConfig error: $e');
    }

    // sampling, mortality, activities, harvests are kept up to date by
    // the real-time listeners in _listenFirebase(), so no need to re-fetch.

    notifyListeners();
  }

  Future<void> selectBatch(String? batchId) async {
    if (batchId == null) {
      _selectedBatchId = null;
      notifyListeners();
      if (_isArchiveView) {
        _isArchiveView = false;
        _clearArchiveState();
        final activeBatch = _batches.where((b) => b.status == 'active').firstOrNull;
        if (activeBatch != null) {
          _restoreFromBatchRecord(activeBatch);
        }
        await _reloadLiveDataFromFirebase();
      }
      notifyListeners();
      return;
    }

    final exists = _batches.any((b) => b.batchId == batchId);
    if (!exists) return;

    if (_selectedBatchId == batchId) return;

    _selectedBatchId = batchId;
    final batch = _batches.firstWhere((b) => b.batchId == batchId);

    notifyListeners();

    if (batch.status == 'harvested' || batch.status == 'superseded') {
      await _enterArchiveView(batch);
    } else {
      _isArchiveView = false;
      _clearArchiveState();
      _restoreFromBatchRecord(batch);
      await _reloadLiveDataFromFirebase();
      notifyListeners();
    }
  }

  Future<void> _enterArchiveView(CrayfishBatch batch) async {
    _isArchiveView = true;
    _clearArchiveState();
    _initialCount = batch.initialCount;
    _mortality = batch.totalMortality;
    _totalHarvested = batch.harvestCount;
    _stockingDate = batch.stockingDate;
    _initialWeight = batch.initialAbw;
    _initialLength = batch.initialAbl;
    _isInitialized = true;
    _setupComplete = true;
    _sampleCount = batch.sampleCount;
    _totalSampleWeight = batch.initialTotalWeight;
    _totalSampleLength = batch.initialTotalLength;

    final List<SamplingEntry> archivedSampling = [];
    final rawSampling = batch.archivedSampling;
    if (rawSampling != null) {
      for (final v in rawSampling.values) {
        if (v is! Map) continue;
        final sm = _convertMap(v);
        final dateRaw = sm['date'];
        if (dateRaw is! num) {
          debugPrint('[TankService] _enterArchiveView: skipping archived sampling without date');
          continue;
        }
        archivedSampling.add(SamplingEntry(
          date: DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt()),
          abw: (sm['abw'] as num?)?.toDouble() ?? 0.0,
          avgLength: (sm['avgLength'] as num?)?.toDouble() ?? 0.0,
          sampleSize: (sm['sampleSize'] as num?)?.toInt() ?? 0,
          totalWeight: (sm['totalWeight'] as num?)?.toDouble() ?? 0.0,
          totalLength: (sm['totalLength'] as num?)?.toDouble() ?? 0.0,
          biomass: (sm['biomass'] as num?)?.toDouble() ?? 0.0,
          liveCount: (sm['liveCount'] as num?)?.toInt() ?? 0,
          isBaseline: sm['isBaseline'] == true,
        ));
      }
      archivedSampling.sort((a, b) => a.date.compareTo(b.date));
    }
    _samplingHistory = archivedSampling;

    final List<MortalityEntry> archivedMortality = [];
    final rawMortality = batch.archivedMortality;
    if (rawMortality != null) {
      for (final v in rawMortality.values) {
        if (v is! Map) continue;
        final mm = _convertMap(v);
        final dateRaw = mm['date'];
        final countRaw = mm['count'];
        if (dateRaw is! num || countRaw is! num) {
          debugPrint('[TankService] _enterArchiveView: skipping archived mortality without date/count');
          continue;
        }
        archivedMortality.add(MortalityEntry(
          date: DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt()),
          count: countRaw.toInt(),
        ));
      }
      archivedMortality.sort((a, b) => a.date.compareTo(b.date));
    }
    _mortalityHistory = archivedMortality;

    // Load harvest records from Firestore
    try {
      final snap = await _fs
          .collection('harvests')
          .where('uid', isEqualTo: _tankOwnerUid)
          .get();
      if (snap.docs.isNotEmpty) {
        _harvestRecords = snap.docs
            .map((doc) => CrayfishHarvestRecord.fromJson(
                doc.id, Map<String, dynamic>.from(doc.data())))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
      }
    } catch (e) {
      debugPrint('[TankService] _enterArchiveView load harvest error: $e');
    }

    notifyListeners();
  }

  void _listenFirebase() {
    _batchesSub = _fs
        .collection('batches')
        .where('uid', isEqualTo: _tankOwnerUid)
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      if (snap.docs.isEmpty) {
        _batches = [];
        _harvestHistory = [];
        _selectedBatchId = null;
        notifyListeners();
        return;
      }
      _parseBatchesFromSnapshot(snap);
    }, onError: (e) {
      debugPrint('[TankService] _batchesSub error: $e');
    });

    _samplingSub = _fs
        .collection('sampling')
        .where('uid', isEqualTo: _tankOwnerUid)
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      if (snap.docs.isEmpty) {
        _samplingHistory.clear();
        _lastSamplingDocId = null;
        notifyListeners();
        return;
      }
      final entries = <SamplingEntry>[];
      String? lastId;
      DateTime? lastDate;
      for (final doc in snap.docs) {
        final map = doc.data();
        final dateRaw = map['date'];
        if (dateRaw is! num) {
          debugPrint('[TankService] sampling listener: skipping entry without valid date');
          continue;
        }
        final date = DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt());
        entries.add(SamplingEntry(
          date: date,
          abw: (map['abw'] as num?)?.toDouble() ?? 0.0,
          avgLength: (map['avgLength'] as num?)?.toDouble() ?? 0.0,
          sampleSize: (map['sampleSize'] as num?)?.toInt() ?? 0,
          totalWeight: (map['totalWeight'] as num?)?.toDouble() ?? 0.0,
          totalLength: (map['totalLength'] as num?)?.toDouble() ?? 0.0,
          biomass: (map['biomass'] as num?)?.toDouble() ?? 0.0,
          liveCount: (map['liveCount'] as num?)?.toInt() ?? 0,
          isBaseline: map['isBaseline'] == true,
        ));
        if (lastDate == null || date.isAfter(lastDate)) { lastDate = date; lastId = doc.id; }
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      _samplingHistory = entries;
      _lastSamplingDocId = lastId;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _samplingSub error: $e');
    });

    _mortalitySub = _fs
        .collection('mortality')
        .where('uid', isEqualTo: _tankOwnerUid)
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      if (snap.docs.isEmpty) {
        _mortalityHistory.clear();
        notifyListeners();
        return;
      }
      _mortalityHistory = snap.docs.map((doc) {
        final map = doc.data();
        final dateRaw = map['date'];
        final countRaw = map['count'];
        if (dateRaw is! num || countRaw is! num) {
          debugPrint('[TankService] mortality listener: skipping entry with missing date/count');
          return null;
        }
        return MortalityEntry(
          date: DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt()),
          count: countRaw.toInt(),
        );
      }).whereType<MortalityEntry>().toList()..sort((a, b) => a.date.compareTo(b.date));
      _mortality = _mortalityHistory.fold(0, (sum, e) => sum + e.count);
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _mortalitySub error: $e');
    });

    _activitiesSub = _fs
        .collection('activities')
        .where('uid', isEqualTo: _tankOwnerUid)
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      if (snap.docs.isEmpty) {
        _activities.clear();
        notifyListeners();
        return;
      }
      _activities = snap.docs.map((doc) {
        final map = doc.data();
        return TankActivity(
          action: map['action'] ?? '',
          date: map['date'] as String? ?? '',
          time: map['time'] as String? ?? '',
          type: map['type'] ?? '',
          timestamp: map['timestamp'] ?? 0,
        );
      }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _activitiesSub error: $e');
    });

    _harvestsSub = _fs
        .collection('harvests')
        .where('uid', isEqualTo: _tankOwnerUid)
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      if (snap.docs.isEmpty) {
        _harvestRecords.clear();
        notifyListeners();
        return;
      }
      _harvestRecords = snap.docs
          .map((doc) => CrayfishHarvestRecord.fromJson(
              doc.id, Map<String, dynamic>.from(doc.data())))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _harvestsSub error: $e');
    });
  }

  Future<void> _saveConfig() async {
    if (!_setupComplete) return;
    await _fs.collection('config').doc(_tankOwnerUid).set({
      'initialPopulation': _initialCount,
      'stockingDate': _stockingDate.millisecondsSinceEpoch,
      'lastSampleDate': _lastSampleDate.millisecondsSinceEpoch,
      'Mortality': _mortality,
      'sampleCount': _sampleCount,
      'initialTotalSampleWeight': _totalSampleWeight,
      'initialTotalSampleLength': _totalSampleLength,
      'Alive': inTankCount,
      'totalHarvested': _totalHarvested,
      'isInitialized': _isInitialized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resetExperiment() async {
    _resetAll();
    _batches = [];
    _harvestHistory = [];
    await Future.wait([
      _fs.collection('config').doc(_tankOwnerUid).delete(),
      _fs.collection('sampling').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
        for (final doc in snap.docs) { doc.reference.delete(); }
      }),
      _fs.collection('mortality').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
        for (final doc in snap.docs) { doc.reference.delete(); }
      }),
      _fs.collection('activities').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
        for (final doc in snap.docs) { doc.reference.delete(); }
      }),
      _fs.collection('batches').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
        for (final doc in snap.docs) { doc.reference.delete(); }
      }),
    ]);
    notifyListeners();
  }

  Future<void> initializeGrowOut(int initial, int sampleCount, double totalWeight, double totalLength, DateTime date, {String? batchName}) async {
    if (_tankOwnerUid.isEmpty) {
      throw Exception('User not authenticated. Please sign in and try again.');
    }

    // --- Step 1: Archive the currently active batch (if any) before creating a new one ---
    final existingActive = _batches.where((b) => b.status == 'active').firstOrNull;
    if (existingActive != null) {
      try {
        final samplingSnap = await _fs
            .collection('sampling')
            .where('uid', isEqualTo: _tankOwnerUid)
            .get();
        final mortalitySnap = await _fs
            .collection('mortality')
            .where('uid', isEqualTo: _tankOwnerUid)
            .get();
        final archivedBatch = CrayfishBatch(
          batchId: existingActive.batchId,
          status: 'superseded',
          stockingDate: existingActive.stockingDate,
          initialCount: existingActive.initialCount,
          harvestCount: 0, totalMortality: _mortality,
          initialAbw: existingActive.initialAbw, initialAbl: existingActive.initialAbl,
          finalAbw: _samplingHistory.isNotEmpty ? _samplingHistory.last.abw : existingActive.initialAbw,
          finalAbl: _samplingHistory.isNotEmpty ? _samplingHistory.last.avgLength : existingActive.initialAbl,
          daysInCulture: DateTime.now().difference(existingActive.stockingDate).inDays,
          sampleCount: _sampleCount,
          initialTotalWeight: _totalSampleWeight,
          initialTotalLength: _totalSampleLength,
          archivedSampling: samplingSnap.docs.isNotEmpty
              ? Map.fromEntries(samplingSnap.docs.map((d) => MapEntry(d.id, d.data())))
              : null,
          archivedMortality: mortalitySnap.docs.isNotEmpty
              ? Map.fromEntries(mortalitySnap.docs.map((d) => MapEntry(d.id, d.data())))
              : null,
        );
        // Find and update the existing batch doc (preserve uid)
        final batchSnap = await _fs
            .collection('batches')
            .where('batchId', isEqualTo: existingActive.batchId)
            .where('uid', isEqualTo: _tankOwnerUid)
            .get();
        if (batchSnap.docs.isNotEmpty) {
          await batchSnap.docs.first.reference.set({
            ...archivedBatch.toJson(),
            'uid': _tankOwnerUid,
          });
        }
      } catch (e) {
        debugPrint('[TankService] initializeGrowOut: could not archive previous batch: $e');
      }
    }

    // --- Step 2: Clear sampling/mortality/activities data from Firestore ---
    try {
      await Future.wait([
        _fs.collection('sampling').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
          for (final d in snap.docs) { d.reference.delete(); }
        }),
        _fs.collection('mortality').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
          for (final d in snap.docs) { d.reference.delete(); }
        }),
        _fs.collection('activities').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
          for (final d in snap.docs) { d.reference.delete(); }
        }),
      ]);
    } catch (e) {
      debugPrint('[TankService] Error clearing old data: $e');
    }

    // --- Step 3: Set up local state for the new batch ---
    _initialCount = initial;
    _stockingDate = date;
    _lastSampleDate = date;
    _sampleCount = sampleCount;
    _totalSampleWeight = totalWeight;
    _totalSampleLength = totalLength;
    _initialWeight = sampleCount > 0 ? (totalWeight / sampleCount) : 0.0;
    _initialLength = sampleCount > 0 ? (totalLength / sampleCount) : 0.0;
    _isInitialized = true;
    _setupComplete = true;
    _mortality = 0;
    _totalHarvested = 0;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();
    _isArchiveView = false;

    // --- Step 4: Save new config to Firestore ---
    await _saveConfig();
    _addActivity('Initialized new grow-out batch with $initial population', 'init', customDate: date);

    // --- Step 5: Build unique batch ID and push to Firestore ---
    final dateStr = "${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}";
    final seq = (_batches.length + 1).toString().padLeft(3, '0');
    final fallbackBid = 'CR-$dateStr-$seq';
    final bid = (batchName != null && batchName.trim().isNotEmpty) ? batchName.trim() : fallbackBid;

    final newBatch = CrayfishBatch(
      batchId: bid, status: 'active', stockingDate: _stockingDate,
      initialCount: _initialCount, initialAbw: _initialWeight, initialAbl: _initialLength,
      daysInCulture: 0,
      sampleCount: _sampleCount,
      initialTotalWeight: _totalSampleWeight,
      initialTotalLength: _totalSampleLength,
    );

    try {
      await _fs.collection('batches').add({
        ...newBatch.toJson(),
        'uid': _tankOwnerUid,
      });
    } catch (e) {
      debugPrint('[TankService] Batch push error (non-fatal): $e');
    }

    // --- Step 6: Update local batch list and select the new batch immediately ---
    _batches.removeWhere((b) => b.batchId == bid);
    _batches.insert(0, newBatch);
    _selectedBatchId = bid;

    notifyListeners();
  }

  void addSamplingEntry(int count, double weight, double length) {
    _setupComplete = true;
    final now = DateTime.now();
    _lastSampleDate = now;
    final abw = weight / count;
    final avgLength = length / count;
    final entry = SamplingEntry(
      date: now, abw: abw, avgLength: avgLength, sampleSize: count,
      totalWeight: weight, totalLength: length, biomass: inTankCount * abw, liveCount: inTankCount,
    );
    _samplingHistory.add(entry);
    _fs.collection('sampling').add({
      'uid': _tankOwnerUid,
      'batchId': _selectedBatchId ?? '',
      'date': entry.date.millisecondsSinceEpoch,
      'abw': entry.abw,
      'avgLength': entry.avgLength,
      'sampleSize': entry.sampleSize,
      'totalWeight': entry.totalWeight,
      'totalLength': entry.totalLength,
      'biomass': entry.biomass,
      'liveCount': entry.liveCount,
      'isBaseline': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _addActivity('Recorded sampling: ${abw.toStringAsFixed(2)}g ABW, ${avgLength.toStringAsFixed(2)}cm ABL', 'sampling', sampleSize: count, abw: abw, avgLength: avgLength);
    _saveConfig();
    notifyListeners();
  }

  void updateLastSamplingEntry(int count, double weight, double length) {
    if (_lastSamplingDocId == null || _samplingHistory.isEmpty) return;
    final abw = weight / count;
    final avgLength = length / count;
    final updated = SamplingEntry(
      date: _samplingHistory.last.date, abw: abw, avgLength: avgLength,
      sampleSize: count, totalWeight: weight, totalLength: length,
      biomass: inTankCount * abw, liveCount: inTankCount,
    );
    _samplingHistory.last = updated;
    _fs.collection('sampling').doc(_lastSamplingDocId!).update({
      'abw': updated.abw,
      'avgLength': updated.avgLength,
      'sampleSize': updated.sampleSize,
      'totalWeight': updated.totalWeight,
      'totalLength': updated.totalLength,
      'biomass': updated.biomass,
      'liveCount': updated.liveCount,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _saveConfig();
    notifyListeners();
  }

  void addMortality(int val, {DateTime? date}) {
    _mortality += val;
    _setupComplete = true;
    final mEntry = MortalityEntry(date: date ?? DateTime.now(), count: val);
    _mortalityHistory.add(mEntry);
    _fs.collection('mortality').add({
      'uid': _tankOwnerUid,
      'batchId': _selectedBatchId ?? '',
      'date': mEntry.date.millisecondsSinceEpoch,
      'count': mEntry.count,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _addActivity('Recorded mortality of $val crayfish (Total: $_mortality)', 'mortality', customDate: date);
    _saveConfig();
    notifyListeners();
  }

  void addHarvestRecord({
    required int harvestedCount,
    required double totalWeightKg,
    String? batchId,
  }) {
    final now = DateTime.now();
    final abwGrams = harvestedCount > 0 ? (totalWeightKg * 1000) / harvestedCount : 0.0;
    _totalHarvested += harvestedCount;
    final sr = _initialCount > 0 ? (liveCount / _initialCount * 100) : 0.0;
    _fs.collection('harvests').add({
      'uid': _tankOwnerUid,
      'batchId': batchId ?? _selectedBatchId ?? '',
      'date': now.millisecondsSinceEpoch,
      'harvestedCount': harvestedCount,
      'totalWeightKg': totalWeightKg,
      'abwGrams': abwGrams,
      'survivalRate': sr,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _fs.collection('batches')
        .where('batchId', isEqualTo: batchId ?? _selectedBatchId ?? '')
        .where('uid', isEqualTo: _tankOwnerUid)
        .get()
        .then((snap) {
      if (snap.docs.isNotEmpty) {
        final existing = snap.docs.first.data();
        final totalHarvested = ((existing['harvestCount'] as num?)?.toInt() ?? 0) + harvestedCount;
        final existingWeight = (existing['harvestWeightGrams'] as num?)?.toDouble() ?? 0;
        snap.docs.first.reference.set({
          'harvestDate': now.millisecondsSinceEpoch,
          'harvestCount': totalHarvested,
          'harvestWeightGrams': existingWeight + (totalWeightKg * 1000),
        }, SetOptions(merge: true));
      }
    });
    _addActivity(
      'Harvested $harvestedCount crayfish, ${totalWeightKg.toStringAsFixed(2)}kg total (ABW: ${abwGrams.toStringAsFixed(1)}g)',
      'harvest',
    );
    _saveConfig();
    notifyListeners();
  }

  void _addActivity(String action, String type, {DateTime? customDate, int? sampleSize, double? abw, double? avgLength}) {
    final now = customDate ?? DateTime.now();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    final act = TankActivity(action: action, date: dateStr, time: timeStr, type: type, timestamp: now.millisecondsSinceEpoch, sampleSize: sampleSize, abw: abw, avgLength: avgLength);
    _activities.add(act);
    _fs.collection('activities').add({
      'uid': _tankOwnerUid,
      'batchId': _selectedBatchId ?? '',
      'action': action,
      'type': type,
      'date': dateStr,
      'time': timeStr,
      'timestamp': now.millisecondsSinceEpoch,
      if (sampleSize != null) 'sampleSize': sampleSize,
      if (abw != null) 'abw': abw,
      if (avgLength != null) 'avgLength': avgLength,
    });
  }

  Future<void> completeBatch({required int harvestCount, double? harvestWeightGrams, String? batchId}) async {
    if (!_isInitialized || _isArchiveView) return;
    final now = DateTime.now();
    final activeBatchId = _batches.where((b) => b.status == 'active').firstOrNull?.batchId;
    final resolvedId = batchId ?? activeBatchId ?? 'Batch ${_batches.length + 1}';

    try {
      final samplingSnap = await _fs
          .collection('sampling')
          .where('uid', isEqualTo: _tankOwnerUid)
          .get();
      final mortalitySnap = await _fs
          .collection('mortality')
          .where('uid', isEqualTo: _tankOwnerUid)
          .get();

      final batch = CrayfishBatch(
        batchId: resolvedId, status: 'harvested',
        stockingDate: _stockingDate, harvestDate: now,
        initialCount: _initialCount, harvestCount: harvestCount, totalMortality: _mortality,
        harvestWeightGrams: harvestWeightGrams,
        initialAbw: _initialWeight, initialAbl: _initialLength,
        finalAbw: samplingHistory.isNotEmpty ? samplingHistory.last.abw : _initialWeight,
        finalAbl: samplingHistory.isNotEmpty ? samplingHistory.last.avgLength : _initialLength,
        daysInCulture: daysInCulture,
        sampleCount: _sampleCount,
        initialTotalWeight: _totalSampleWeight,
        initialTotalLength: _totalSampleLength,
        archivedSampling: samplingSnap.docs.isNotEmpty
            ? Map.fromEntries(samplingSnap.docs.map((d) => MapEntry(d.id, d.data())))
            : null,
        archivedMortality: mortalitySnap.docs.isNotEmpty
            ? Map.fromEntries(mortalitySnap.docs.map((d) => MapEntry(d.id, d.data())))
            : null,
      );

      // Update batch doc (preserve uid)
      final batchSnap = await _fs
          .collection('batches')
          .where('batchId', isEqualTo: resolvedId)
          .where('uid', isEqualTo: _tankOwnerUid)
          .get();
      if (batchSnap.docs.isNotEmpty) {
        await batchSnap.docs.first.reference.set({
          ...batch.toJson(),
          'uid': _tankOwnerUid,
        });
      }

      // Clear config + sampling + mortality
      await Future.wait([
        _fs.collection('config').doc(_tankOwnerUid).delete(),
        _fs.collection('sampling').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
          for (final d in snap.docs) { d.reference.delete(); }
        }),
        _fs.collection('mortality').where('uid', isEqualTo: _tankOwnerUid).get().then((snap) {
          for (final d in snap.docs) { d.reference.delete(); }
        }),
      ]);
      _addActivity('Completed grow-out batch ($resolvedId). Harvested $harvestCount crayfish${harvestWeightGrams != null ? ', ${harvestWeightGrams.toStringAsFixed(1)}g total' : ''}.', 'harvest');
      _resetAll();
    } catch (e) {
      debugPrint('[TankService] completeBatch error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }
}
