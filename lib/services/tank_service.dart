import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/crayfish_batch.dart';
import 'connectivity_service.dart';

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
  final String id;
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
    this.id = '',
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
  final String id;
  final DateTime date;
  final int count;
  MortalityEntry({this.id = '', required this.date, required this.count});
}

class TankService extends ChangeNotifier {
  static final TankService instance = TankService._();
  TankService._();

  int _initialCount = 0;
  int _mortality = 0;
  bool _isInitialized = false;
  bool _setupComplete = false;
  DateTime _stockingDate = DateTime.now();
  DateTime _lastSampleDate = DateTime.now();

  List<CrayfishBatch> _batches = [];
  String? _selectedBatchId;
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
  final List<TankActivity> _activities = [];
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

  int get totalMortalityFromHistory => _mortalityHistory.fold(0, (acc, e) => acc + e.count);

  GrowthStage get currentGrowthStage {
    final latest = _samplingHistory.isNotEmpty ? _samplingHistory.last : null;
    final abw = latest?.abw ?? _initialWeight;
    final abl = latest?.avgLength ?? _initialLength;
    if (abw < 5 || abl < 4) return GrowthStage.earlyJuvenile;
    if (abw < 15 || abl < 6) return GrowthStage.advancedJuvenile;
    if (abw < 50 || abl < 10) return GrowthStage.preAdult;
    return GrowthStage.marketSize;
  }

  // ─── Flat collection references ──────────────────────────────────

  Query<Map<String, dynamic>> get _batchesQ =>
      _fs.collection('batches').where('tankId', isEqualTo: _tankOwnerUid);

  Query<Map<String, dynamic>> _samplingQ(String batchId) =>
      _fs.collection('sampling_records').where('batchId', isEqualTo: batchId);

  Query<Map<String, dynamic>> _mortalityQ(String batchId) =>
      _fs.collection('mortality_records').where('batchId', isEqualTo: batchId);

  Query<Map<String, dynamic>> get _harvestsQ =>
      _fs.collection('harvest_records').where('tankId', isEqualTo: _tankOwnerUid);

  // ─── Lifecycle ─────────────────────────────────────────────────────

  Future<void> refresh() async {
    if (_tankOwnerUid.isEmpty) return;
    debugPrint('[TankService] refresh()');
    _cancelSubscriptions();
    await _loadTank();
    _listenFirebase();
  }

  void init() async {
    final initialUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint('[TankService] init() currentUser.uid="$initialUid"');
    if (initialUid.isNotEmpty) {
      _tankOwnerUid = initialUid;
      await _loadTank();
      await _ensureTankExists();
      _listenFirebase();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      final uid = user?.uid ?? '';
      debugPrint('[TankService] authStateChanges event: uid="$uid"');
      if (uid.isEmpty) {
        _resetAll();
        return;
      }
      if (uid == _tankOwnerUid) return;
      _tankOwnerUid = uid;
      _cancelSubscriptions();
      await _loadTank();
      await _ensureTankExists();
      _listenFirebase();
    });
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _onReconnect() {
    debugPrint('[TankService] Internet reconnected');
    refresh();
  }

  Future<void> _ensureTankExists() async {
    if (_tankOwnerUid.isEmpty) return;
    final doc = await _fs.collection('tanks').doc(_tankOwnerUid).get();
    if (!doc.exists) {
      await _fs.collection('tanks').doc(_tankOwnerUid).set({
        'userId': _tankOwnerUid,
        'currentBatchId': '',
        'lifetimeMortality': 0,
        'lifetimeHarvested': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _loadTank() async {
    try {
      final doc = await _fs.collection('tanks').doc(_tankOwnerUid).get();
      if (!doc.exists) {
        debugPrint('[TankService] _loadTank: tank doc does NOT exist');
        _resetAll();
        return;
      }
      final data = doc.data() ?? <String, dynamic>{};
      _initialCount = (data['initialPopulation'] as int?) ?? 0;
      _mortality = (data['lifetimeMortality'] as int?) ?? 0;
      _totalHarvested = (data['lifetimeHarvested'] as int?) ?? 0;
      _stockingDate = DateTime.fromMillisecondsSinceEpoch(
        (data['stockingDate'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );
      _sampleCount = (data['sampleCount'] as int?) ?? 0;
      _totalSampleWeight = (data['initialTotalSampleWeight'] as num?)?.toDouble() ?? 0.0;
      _totalSampleLength = (data['initialTotalSampleLength'] as num?)?.toDouble() ?? 0.0;
      _initialWeight = _sampleCount > 0 ? _totalSampleWeight / _sampleCount : 0.0;
      _initialLength = _sampleCount > 0 ? _totalSampleLength / _sampleCount : 0.0;
      _lastSampleDate = DateTime.fromMillisecondsSinceEpoch(
        (data['lastSampleDate'] as int?) ?? _stockingDate.millisecondsSinceEpoch,
      );
      _isInitialized = _initialCount > 0;
      _setupComplete = _isInitialized;
      notifyListeners();
    } catch (e) {
      debugPrint('[TankService] _loadTank ERROR: $e');
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
    _batches.clear();
    _harvestHistory.clear();
    notifyListeners();
  }

  // ─── Listeners (flat collections) ──────────────────────────────────

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _samplingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mortalitySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _harvestsSub;

  void _cancelSubscriptions() {
    _batchesSub?.cancel();
    _batchesSub = null;
    _samplingSub?.cancel();
    _samplingSub = null;
    _mortalitySub?.cancel();
    _mortalitySub = null;
    _harvestsSub?.cancel();
    _harvestsSub = null;
  }

  void _parseBatchesFromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <CrayfishBatch>[];
    for (final doc in snap.docs) {
      try {
        final map = Map<String, dynamic>.from(doc.data());
        if (map['batchId'] == null) continue;
        list.add(CrayfishBatch.fromJson(map));
      } catch (e) {
        debugPrint('[TankService] error parsing batch: $e');
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
        _isArchiveView = false;
        _clearState();
        _restoreFromBatchRecord(batch);
        _resubscribeToBatch();
      }
    }
    notifyListeners();
  }

  bool get isArchiveView => _isArchiveView;

  void _clearState() {
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

  void _listenFirebase() {
    // Listen to batches (flat collection)
    _batchesSub = _batchesQ
        .orderBy('stockingDate', descending: true)
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

    _resubscribeToBatch();

    // Listen to harvest records (flat)
    _harvestsSub = _harvestsQ
        .orderBy('timestamp')
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
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

  void _resubscribeToBatch() {
    _samplingSub?.cancel();
    _samplingSub = null;
    _mortalitySub?.cancel();
    _mortalitySub = null;

    if (_selectedBatchId == null) return;

    final batchId = _selectedBatchId!;

    // Listen to sampling_records (flat, filtered by batchId)
    _samplingSub = _samplingQ(batchId)
        .orderBy('date')
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      final entries = <SamplingEntry>[];
      String? lastId;
      DateTime? lastDate;
      for (final doc in snap.docs) {
        final map = doc.data();
        final dateRaw = map['date'];
        if (dateRaw is! num) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt());
        entries.add(SamplingEntry(
          id: doc.id,
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
        if (lastDate == null || date.isAfter(lastDate)) {
          lastDate = date;
          lastId = doc.id;
        }
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      _samplingHistory = entries;
      _lastSamplingDocId = lastId;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _samplingSub error: $e');
    });

    // Listen to mortality_records (flat, filtered by batchId)
    _mortalitySub = _mortalityQ(batchId)
        .orderBy('date')
        .snapshots()
        .listen((snap) {
      if (_isArchiveView) return;
      _mortalityHistory = snap.docs.map((doc) {
        final map = doc.data();
        final dateRaw = map['date'];
        final countRaw = map['count'];
        if (dateRaw is! num || countRaw is! num) return null;
        return MortalityEntry(
          id: doc.id,
          date: DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt()),
          count: countRaw.toInt(),
        );
      }).whereType<MortalityEntry>().toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      _mortality = _mortalityHistory.fold(0, (acc, e) => acc + e.count);
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _mortalitySub error: $e');
    });
  }

  Future<void> selectBatch(String? batchId) async {
    if (batchId == null) {
      _selectedBatchId = null;
      if (_isArchiveView) {
        _isArchiveView = false;
        _clearState();
        final activeBatch = _batches.where((b) => b.status == 'active').firstOrNull;
        if (activeBatch != null) {
          _restoreFromBatchRecord(activeBatch);
        }
        _resubscribeToBatch();
      }
      notifyListeners();
      return;
    }

    final exists = _batches.any((b) => b.batchId == batchId);
    if (!exists) return;
    if (_selectedBatchId == batchId) return;

    _selectedBatchId = batchId;
    final batch = _batches.firstWhere((b) => b.batchId == batchId);

    if (batch.status == 'harvested' || batch.status == 'superseded') {
      _enterArchiveView(batch);
    } else {
      _isArchiveView = false;
      _clearState();
      _restoreFromBatchRecord(batch);
      _resubscribeToBatch();
    }
    notifyListeners();
  }

  void _enterArchiveView(CrayfishBatch batch) {
    _isArchiveView = true;
    _clearState();
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
    _resubscribeToBatch();
    notifyListeners();
  }

  Future<void> _saveConfig() async {
    if (!_setupComplete) return;
    if (_tankOwnerUid.isEmpty) return;
    try {
      await _fs.collection('tanks').doc(_tankOwnerUid).set({
        'initialPopulation': _initialCount,
        'stockingDate': _stockingDate.millisecondsSinceEpoch,
        'lastSampleDate': _lastSampleDate.millisecondsSinceEpoch,
        'lifetimeMortality': _mortality,
        'sampleCount': _sampleCount,
        'initialTotalSampleWeight': _totalSampleWeight,
        'initialTotalSampleLength': _totalSampleLength,
        'lifetimeHarvested': _totalHarvested,
        'currentBatchId': _selectedBatchId ?? '',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TankService] _saveConfig error: $e');
      rethrow;
    }
  }

  Future<void> resetExperiment() async {
    _resetAll();
    // Delete tank doc
    await _fs.collection('tanks').doc(_tankOwnerUid).delete();
    // Delete flat collections
    final batchSnap = await _batchesQ.get();
    for (final d in batchSnap.docs) { await d.reference.delete(); }
    final samplingSnap = await _fs.collection('sampling_records')
        .where('tankId', isEqualTo: _tankOwnerUid).get();
    for (final d in samplingSnap.docs) { await d.reference.delete(); }
    final mortalitySnap = await _fs.collection('mortality_records')
        .where('tankId', isEqualTo: _tankOwnerUid).get();
    for (final d in mortalitySnap.docs) { await d.reference.delete(); }
    final harvestSnap = await _harvestsQ.get();
    for (final d in harvestSnap.docs) { await d.reference.delete(); }
    final deviceSnap = await _fs.collection('device_logs')
        .where('tankId', isEqualTo: _tankOwnerUid).get();
    for (final d in deviceSnap.docs) { await d.reference.delete(); }
    notifyListeners();
  }

  Future<void> initializeGrowOut(int initial, int sampleCount, double totalWeight, double totalLength, DateTime date, {String? batchName}) async {
    if (_tankOwnerUid.isEmpty) {
      throw Exception('User not authenticated. Please sign in and try again.');
    }
    if (initial <= 0) throw ArgumentError('Initial population must be greater than 0');
    if (sampleCount <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (totalWeight < 0 || totalLength < 0) throw ArgumentError('Weight and length must be non-negative');

    // Mark currently active batch as superseded — await the inner set() so
    // the write completes before we overwrite local state below.
    final existingActive = _batches.where((b) => b.status == 'active').firstOrNull;
    if (existingActive != null) {
      try {
        final snap = await _fs.collection('batches')
            .where('tankId', isEqualTo: _tankOwnerUid)
            .where('batchId', isEqualTo: existingActive.batchId)
            .get();
        if (snap.docs.isNotEmpty) {
          await snap.docs.first.reference.set({
            'status': 'superseded',
            'daysInCulture': DateTime.now().difference(existingActive.stockingDate).inDays,
            'finalAbw': _samplingHistory.isNotEmpty ? _samplingHistory.last.abw : existingActive.initialAbw,
            'finalAbl': _samplingHistory.isNotEmpty ? _samplingHistory.last.avgLength : existingActive.initialAbl,
            'totalMortality': _mortality,
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('[TankService] could not mark previous batch as superseded: $e');
      }
    }

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

    await _saveConfig();
    _addActivity('Initialized new grow-out batch with $initial population', 'init', customDate: date);

    final dateStr = "${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}";
    final seq = (_batches.length + 1).toString().padLeft(3, '0');
    final fallbackBid = 'CR-$dateStr-$seq';
    final bid = (batchName != null && batchName.trim().isNotEmpty) ? batchName.trim() : fallbackBid;

    try {
      await _fs.collection('batches').add({
        'batchId': bid,
        'tankId': _tankOwnerUid,
        'status': 'active',
        'stockingDate': _stockingDate.millisecondsSinceEpoch,
        'harvestDate': null,
        'initialCount': _initialCount,
        'currentCount': _initialCount,
        'harvestCount': 0,
        'totalMortality': 0,
        'harvestWeightGrams': null,
        'initialAbw': _initialWeight,
        'initialAbl': _initialLength,
        'finalAbw': 0,
        'finalAbl': 0,
        'daysInCulture': 0,
        'sampleCount': _sampleCount,
        'initialTotalWeight': _totalSampleWeight,
        'initialTotalLength': _totalSampleLength,
      });
    } catch (e) {
      debugPrint('[TankService] Batch push error: $e');
    }

    _batches.insert(0, CrayfishBatch(
      batchId: bid, status: 'active', stockingDate: _stockingDate,
      initialCount: _initialCount, initialAbw: _initialWeight, initialAbl: _initialLength,
      daysInCulture: 0, sampleCount: _sampleCount,
      initialTotalWeight: _totalSampleWeight, initialTotalLength: _totalSampleLength,
    ));
    _selectedBatchId = bid;

    _resubscribeToBatch();
    notifyListeners();
  }

  void addSamplingEntry(int count, double weight, double length) {
    if (count <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (weight < 0 || length < 0) throw ArgumentError('Weight and length must be non-negative');
    if (_selectedBatchId == null) throw ArgumentError('No batch selected');

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
    try {
      _fs.collection('sampling_records').add({
        'batchId': _selectedBatchId!,
        'tankId': _tankOwnerUid,
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
    } catch (e) {
      debugPrint('[TankService] Error saving sampling entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  void updateLastSamplingEntry(int count, double weight, double length) {
    if (_lastSamplingDocId == null || _samplingHistory.isEmpty) return;
    if (_selectedBatchId == null) return;
    if (count <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (weight < 0 || length < 0) throw ArgumentError('Weight and length must be non-negative');

    final abw = weight / count;
    final avgLength = length / count;
    final updated = SamplingEntry(
      id: _lastSamplingDocId!,
      date: _samplingHistory.last.date, abw: abw, avgLength: avgLength,
      sampleSize: count, totalWeight: weight, totalLength: length,
      biomass: inTankCount * abw, liveCount: inTankCount,
    );
    _samplingHistory.last = updated;
    try {
      _fs.collection('sampling_records').doc(_lastSamplingDocId!).update({
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
    } catch (e) {
      debugPrint('[TankService] Error updating sampling entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  void addMortality(int val, {DateTime? date}) {
    if (val <= 0) throw ArgumentError('Mortality count must be greater than 0');
    if (_selectedBatchId == null) throw ArgumentError('No batch selected');

    _mortality += val;
    _setupComplete = true;
    final mEntry = MortalityEntry(date: date ?? DateTime.now(), count: val);
    _mortalityHistory.add(mEntry);
    try {
      _fs.collection('mortality_records').add({
        'batchId': _selectedBatchId!,
        'tankId': _tankOwnerUid,
        'date': mEntry.date.millisecondsSinceEpoch,
        'count': mEntry.count,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _addActivity('Recorded mortality of $val crayfish (Total: $_mortality)', 'mortality', customDate: date);
      _saveConfig();
    } catch (e) {
      debugPrint('[TankService] Error saving mortality entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  void addHarvestRecord({
    required int harvestedCount,
    required double totalWeightKg,
    String? batchId,
  }) {
    if (harvestedCount < 0) throw ArgumentError('Harvested count must be non-negative');
    if (totalWeightKg < 0) throw ArgumentError('Total weight must be non-negative');

    final now = DateTime.now();
    final abwGrams = harvestedCount > 0 ? (totalWeightKg * 1000) / harvestedCount : 0.0;
    _totalHarvested += harvestedCount;
    final sr = _initialCount > 0 ? (liveCount / _initialCount * 100) : 0.0;
    final resolvedBatchId = batchId ?? _selectedBatchId ?? '';

    try {
      _fs.collection('harvest_records').add({
        'tankId': _tankOwnerUid,
        'batchId': resolvedBatchId,
        'totalWeightKg': totalWeightKg,
        'survivalRate': sr,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _fs.collection('batches')
          .where('tankId', isEqualTo: _tankOwnerUid)
          .where('batchId', isEqualTo: resolvedBatchId)
          .get()
          .then((snap) {
        if (snap.docs.isNotEmpty) {
          final existing = snap.docs.first.data();
          final totalH = ((existing['harvestCount'] as num?)?.toInt() ?? 0) + harvestedCount;
          final existingWeight = (existing['harvestWeightGrams'] as num?)?.toDouble() ?? 0;
          snap.docs.first.reference.set({
            'harvestDate': now.millisecondsSinceEpoch,
            'harvestCount': totalH,
            'harvestWeightGrams': existingWeight + (totalWeightKg * 1000),
          }, SetOptions(merge: true));
        }
      });

      _addActivity(
        'Harvested $harvestedCount crayfish, ${totalWeightKg.toStringAsFixed(2)}kg total (ABW: ${abwGrams.toStringAsFixed(1)}g)',
        'harvest',
      );
      _saveConfig();
    } catch (e) {
      debugPrint('[TankService] Error saving harvest record: $e');
      rethrow;
    }
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
  }

  Future<void> completeBatch({required int harvestCount, double? harvestWeightGrams, String? batchId}) async {
    if (!_isInitialized || _isArchiveView) return;
    final now = DateTime.now();
    final activeBatchId = _batches.where((b) => b.status == 'active').firstOrNull?.batchId;
    final resolvedId = batchId ?? activeBatchId ?? 'Batch ${_batches.length + 1}';

    try {
      final batchSnap = await _fs.collection('batches')
          .where('tankId', isEqualTo: _tankOwnerUid)
          .where('batchId', isEqualTo: resolvedId)
          .get();
      if (batchSnap.docs.isNotEmpty) {
        await batchSnap.docs.first.reference.set({
          'status': 'harvested',
          'harvestDate': now.millisecondsSinceEpoch,
          'harvestCount': harvestCount,
          'harvestWeightGrams': harvestWeightGrams,
          'daysInCulture': daysInCulture,
          'totalMortality': _mortality,
          'finalAbw': samplingHistory.isNotEmpty ? samplingHistory.last.abw : _initialWeight,
          'finalAbl': samplingHistory.isNotEmpty ? samplingHistory.last.avgLength : _initialLength,
        }, SetOptions(merge: true));
      }

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
