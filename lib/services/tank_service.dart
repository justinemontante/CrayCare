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
  String _currentUserUid = '';
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
  /// Biological survivors include animals already harvested; only confirmed
  /// mortality reduces survival. `inTankCount` additionally removes harvests.
  int get liveCount =>
      (_initialCount - _mortality).clamp(0, _initialCount).toInt();
  int get inTankCount => (_initialCount - _mortality - _totalHarvested)
      .clamp(0, _initialCount)
      .toInt();
  double get survivalRate => _initialCount == 0
      ? 0.0
      : (liveCount / _initialCount * 100).clamp(0.0, 100.0).toDouble();
  DateTime get stockingDate => _stockingDate;

  int get daysInCulture {
    if (_isArchiveView) {
      final batch = selectedBatch;
      if (batch != null) return batch.daysInCulture;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today
        .difference(DateTime(_stockingDate.year, _stockingDate.month, _stockingDate.day))
        .inDays
        .clamp(0, 1000000)
        .toInt();
  }

  int get daysSinceLastSampling {
    if (_isArchiveView) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Use the last NON-baseline sampling entry as the anchor for the weekly
    // cadence. The baseline (initial) measurement taken at stocking is NOT a
    // weekly sampling — it's the day-of-setup reference. This makes the first
    // weekly sampling fall 7 calendar days after stocking, regardless of how
    // many hours were left in the setup day (e.g. setup at 11 PM).
    final weekly = _samplingHistory.where((e) => !e.isBaseline).toList();
    if (weekly.isEmpty) {
      final anchor = DateTime(
        _stockingDate.year, _stockingDate.month, _stockingDate.day,
      );
      return today.difference(anchor).inDays.clamp(0, 1000000).toInt();
    }
    final last = weekly.last.date;
    return today
        .difference(DateTime(last.year, last.month, last.day))
        .inDays
        .clamp(0, 1000000)
        .toInt();
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

  // ─── Nested tank/batch collection references ─────────────────────

  DocumentReference<Map<String, dynamic>> get _tankRef =>
      _fs.collection('tanks').doc(_tankOwnerUid);

  CollectionReference<Map<String, dynamic>> get _batchesRef =>
      _tankRef.collection('batches');

  CollectionReference<Map<String, dynamic>> _samplingRef(String batchId) =>
      _batchesRef.doc(batchId).collection('sampling_records');

  CollectionReference<Map<String, dynamic>> _mortalityRef(String batchId) =>
      _batchesRef.doc(batchId).collection('mortality_records');

  CollectionReference<Map<String, dynamic>> _harvestRef(String batchId) =>
      _batchesRef.doc(batchId).collection('harvest_records');

  // ─── Lifecycle ─────────────────────────────────────────────────────

  Future<String> _resolveTankIdForUser(String uid) async {
    try {
      final profileRef = _fs.collection('users').doc(uid);
      final profile = await profileRef.get();
      final data = profile.data();
      final role = data?['role'] as String?;

      // Admins do NOT own a tank. Return empty so the service skips all
      // tank provisioning/listening — otherwise the admin would get a tank
      // auto-created (current_batch_id, sensors, actuators, etc.).
      if (role == 'admin') return '';

      final tankId = data?['tank_id'] as String?;
      if (tankId != null && tankId.isNotEmpty) return tankId;

      // Legacy owner accounts may predate tank provisioning. They can claim
      // only a tank with the same ID as their authenticated UID (enforced by
      // Firestore Rules), then normal tank provisioning can continue.
      //
      // If the profile doc does not exist at all, create a minimal owner
      // profile so the Firestore rules "create" branch (which requires
      // role='owner' and status='active') is satisfied. Otherwise a plain
      // {'tank_id': uid} create would be DENIED and every subsequent tank
      // write would fail with permission-denied.
      final profileExists = profile.exists && data != null;
      await profileRef.set({
        'tank_id': uid,
        if (!profileExists) 'role': 'owner',
        if (!profileExists) 'status': 'active',
      }, SetOptions(merge: true));
      return uid;
    } catch (_) {
      return uid;
    }
  }

  Future<void> refresh() async {
    if (_currentUserUid.isNotEmpty) {
      _tankOwnerUid = await _resolveTankIdForUser(_currentUserUid);
    }
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
      _currentUserUid = initialUid;
      _tankOwnerUid = await _resolveTankIdForUser(initialUid);
      // Admins resolve to an empty tank id — skip tank provisioning/listeners.
      if (_tankOwnerUid.isNotEmpty) {
        await _loadTank();
        await _ensureTankExists();
        _listenFirebase();
      }
    }
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      final uid = user?.uid ?? '';
      debugPrint('[TankService] authStateChanges event: uid="$uid"');
      if (uid.isEmpty) {
        _currentUserUid = '';
        _tankOwnerUid = '';
        _resetAll();
        return;
      }
      if (uid == _currentUserUid) return;
      _currentUserUid = uid;
      _tankOwnerUid = await _resolveTankIdForUser(uid);
      _cancelSubscriptions();
      // Admins resolve to an empty tank id — skip tank provisioning/listeners.
      if (_tankOwnerUid.isEmpty) {
        _resetAll();
        return;
      }
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
    try {
      final writeBatch = _fs.batch();
      var hasWrites = false;
      final tankDoc = await _tankRef.get();
      if (!tankDoc.exists) {
        writeBatch.set(_tankRef, {
          'owner_uid': _currentUserUid.isNotEmpty ? _currentUserUid : _tankOwnerUid,
          'current_batch_id': '',
          'is_initialized': false,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        hasWrites = true;
      }

      const sensorDefaults = {
        'temperature': {'min': 24.0, 'max': 30.0},
        'ph_level': {'min': 7.0, 'max': 8.5},
        'dissolved_oxygen': {'min': 5.0, 'max': 9.0},
        'turbidity': {'min': 0.0, 'max': 25.0},
        'water_level': {'min': 15.0, 'max': 20.0},
      };
      for (final entry in sensorDefaults.entries) {
        final ref = _tankRef.collection('sensors').doc(entry.key);
        if (!(await ref.get()).exists) {
          writeBatch.set(ref, {
            'min_value': entry.value['min'],
            'max_value': entry.value['max'],
            'updated_at': FieldValue.serverTimestamp(),
          });
          hasWrites = true;
        }
      }
      for (final actuatorId in ['pump', 'aerator1', 'aerator2']) {
        final ref = _tankRef.collection('actuators').doc(actuatorId);
        if (!(await ref.get()).exists) {
          writeBatch.set(ref, {
            'control_mode': 'off',
            'current_state': 'off',
            'last_changed': 0,
          });
          hasWrites = true;
        }
      }
      final feederRef = _tankRef.collection('feeder').doc('status');
      if (!(await feederRef.get()).exists) {
        writeBatch.set(feederRef, {
          'status': 'idle',
          'last_dispensed_at': null,
          'last_dispensed_grams': 0.0,
        });
        hasWrites = true;
      }
      if (hasWrites) await writeBatch.commit();
    } catch (e) {
      // A denied read/write here should not kill the whole init chain;
      // the tank page will surface the real error on its first write.
      debugPrint('[TankService] _ensureTankExists error: $e');
    }
  }

  Future<void> _loadTank() async {
    if (_tankOwnerUid.isEmpty) {
      _resetAll();
      return;
    }
    try {
      final doc = await _tankRef.get();
      if (!doc.exists) {
        debugPrint('[TankService] _loadTank: tank doc does NOT exist');
        _resetAll();
        return;
      }
      final data = doc.data() ?? <String, dynamic>{};
      _initialCount = (data['initial_population'] as int?) ?? 0;
      // Mortality/harvest totals are derived from the batch + record
      // listeners (SUM over records), not stored on the tank doc.
      _mortality = 0;
      _totalHarvested = 0;
      _stockingDate = DateTime.fromMillisecondsSinceEpoch(
        (data['stocking_date'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      );
      _sampleCount = (data['sample_count'] as int?) ?? 0;
      _totalSampleWeight =
          (data['initial_total_sample_weight'] as num?)?.toDouble() ?? 0.0;
      _totalSampleLength =
          (data['initial_total_sample_length'] as num?)?.toDouble() ?? 0.0;
      _initialWeight = _sampleCount > 0 ? _totalSampleWeight / _sampleCount : 0.0;
      _initialLength = _sampleCount > 0 ? _totalSampleLength / _sampleCount : 0.0;
      _lastSampleDate = DateTime.fromMillisecondsSinceEpoch(
        (data['last_sample_date'] as int?) ?? _stockingDate.millisecondsSinceEpoch,
      );
      _selectedBatchId = data['current_batch_id'] as String?;
      _isInitialized = (data['is_initialized'] as bool?) ?? _initialCount > 0;
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
    _selectedBatchId = null;
    _isArchiveView = false;
    _samplingHistory.clear();
    _mortalityHistory.clear();
    _activities.clear();
    _harvestRecords.clear();
    _batches.clear();
    _harvestHistory.clear();
    notifyListeners();
  }

  // ─── Listeners (nested collections) ────────────────────────────────

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _batchesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _samplingSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mortalitySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _harvestsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tankSub;

  void _cancelSubscriptions() {
    _batchesSub?.cancel();
    _batchesSub = null;
    _samplingSub?.cancel();
    _samplingSub = null;
    _mortalitySub?.cancel();
    _mortalitySub = null;
    _harvestsSub?.cancel();
    _harvestsSub = null;
    _tankSub?.cancel();
    _tankSub = null;
  }

  void _parseBatchesFromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <CrayfishBatch>[];
    for (final doc in snap.docs) {
      try {
        final map = Map<String, dynamic>.from(doc.data());
        map['batch_id'] ??= doc.id;
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
    _mortality = batch.totalMortality;
    _totalHarvested = batch.harvestCount;
    _isInitialized = true;
    _setupComplete = true;
  }

  void _listenFirebase() {
    // Real-time tank document listener. Reflects external changes instantly:
    //  - tank doc deleted (admin/console)  -> reset state, dashboard shows
    //    "not set up yet"
    //  - is_initialized flipped elsewhere   -> reload tank + batches
    _tankSub?.cancel();
    _tankSub = _tankRef.snapshots().listen((doc) {
      final data = doc.data();
      if (data == null) {
        // Tank document was deleted — treat as "no setup yet".
        if (_isInitialized || _batches.isNotEmpty || _samplingHistory.isNotEmpty) {
          _resetAll();
        }
        return;
      }
      final nowInitialized = data['is_initialized'] == true;
      if (_isInitialized != nowInitialized) {
        // Setup state changed somewhere else (e.g. another device).
        _cancelSubscriptions();
        _loadTank();
        _listenFirebase();
        notifyListeners();
      }
    }, onError: (e) {
      debugPrint('[TankService] _tankSub error: $e');
    });

    // Listen to this tank's nested batches collection.
    _batchesSub = _batchesRef
        .orderBy('stocking_date', descending: true)
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
  }

  void _resubscribeToBatch() {
    _samplingSub?.cancel();
    _samplingSub = null;
    _mortalitySub?.cancel();
    _mortalitySub = null;
    _harvestsSub?.cancel();
    _harvestsSub = null;

    if (_selectedBatchId == null) return;

    final batchId = _selectedBatchId!;

    // Listen to this batch's nested sampling_records subcollection.
    _samplingSub = _samplingRef(batchId)
        .orderBy('sampling_date')
        .snapshots()
        .listen((snap) {
      final entries = <SamplingEntry>[];
      String? lastId;
      DateTime? lastDate;
      for (final doc in snap.docs) {
        final map = doc.data();
        final dateRaw = map['sampling_date'];
        if (dateRaw is! num) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(dateRaw.toInt());
        entries.add(SamplingEntry(
          id: doc.id,
          date: date,
          abw: (map['avg_body_weight'] as num?)?.toDouble() ?? 0.0,
          avgLength: (map['avg_body_length'] as num?)?.toDouble() ?? 0.0,
          sampleSize: (map['sample_size'] as num?)?.toInt() ?? 0,
          totalWeight: (map['total_weight'] as num?)?.toDouble() ?? 0.0,
          totalLength: (map['total_length'] as num?)?.toDouble() ?? 0.0,
          biomass: (map['biomass'] as num?)?.toDouble() ?? 0.0,
          liveCount: (map['live_count'] as num?)?.toInt() ?? 0,
          isBaseline: map['is_baseline'] == true,
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

    // Listen to this batch's nested mortality_records subcollection.
    _mortalitySub = _mortalityRef(batchId)
        .orderBy('mortality_date')
        .snapshots()
        .listen((snap) {
      _mortalityHistory = snap.docs.map((doc) {
        final map = doc.data();
        final dateRaw = map['mortality_date'];
        final countRaw = map['mortality_count'];
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

    // Listen to this batch's nested harvest_records subcollection.
    _harvestsSub = _harvestRef(batchId)
        .orderBy('harvest_date')
        .snapshots()
        .listen((snap) {
      _harvestRecords = snap.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        // Older records were path-scoped but omitted batch_id, causing the
        // filtered harvest list/dashboard weight to appear empty.
        data['batch_id'] ??= batchId;
        return CrayfishHarvestRecord.fromJson(doc.id, data);
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      // The record collection is the source of truth; rebuilding the aggregate
      // keeps another device's dashboard consistent without relying on cache.
      _totalHarvested = _harvestRecords.fold<int>(
        0,
        (total, record) => total + record.harvestedCount,
      );
      notifyListeners();
    }, onError: (e) {
      debugPrint('[TankService] _harvestsSub error: $e');
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
      await _tankRef.set({
        'owner_uid': _currentUserUid.isNotEmpty ? _currentUserUid : _tankOwnerUid,
        'initial_population': _initialCount,
        'stocking_date': _stockingDate.millisecondsSinceEpoch,
        'last_sample_date': _lastSampleDate.millisecondsSinceEpoch,
        'sample_count': _sampleCount,
        'initial_total_sample_weight': _totalSampleWeight,
        'initial_total_sample_length': _totalSampleLength,
        'current_batch_id': _selectedBatchId ?? '',
        'is_initialized': _isInitialized,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[TankService] _saveConfig error: $e');
      rethrow;
    }
  }

  Future<void> initializeGrowOut(
    int initial,
    int sampleCount,
    double totalWeight,
    double totalLength,
    DateTime date, {
    String? batchName,
    bool editExisting = false,
  }) async {
    if (_tankOwnerUid.isEmpty) {
      throw Exception('User not authenticated. Please sign in and try again.');
    }
    if (initial <= 0) throw ArgumentError('Initial population must be greater than 0');
    if (sampleCount <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (sampleCount > initial) throw ArgumentError('Sample count cannot exceed initial population');
    if (totalWeight <= 0 || totalLength <= 0) {
      throw ArgumentError('Sample weight and length must be greater than zero');
    }

    final requestedName = batchName?.trim() ?? '';
    if (requestedName.contains('/') || requestedName.length > 100) {
      throw ArgumentError('Batch name cannot contain "/" and must be 100 characters or fewer');
    }
    final dateStr =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final seq = (_batches.length + 1).toString().padLeft(3, '0');
    final fallbackBid = 'CR-$dateStr-$seq';

    if (editExisting) {
      final currentId = _selectedBatchId;
      final current = selectedBatch;
      if (currentId == null || current == null || current.status != 'active') {
        throw StateError('Only the current active batch can be edited');
      }
      if (requestedName.isNotEmpty && requestedName != currentId) {
        throw ArgumentError('The batch name cannot be changed after initialization');
      }
      if (_samplingHistory.isNotEmpty ||
          _mortalityHistory.isNotEmpty ||
          _harvestRecords.isNotEmpty) {
        throw StateError('Initialization cannot be edited after operational records exist');
      }

      _initialCount = initial;
      _stockingDate = date;
      _lastSampleDate = date;
      _sampleCount = sampleCount;
      _totalSampleWeight = totalWeight;
      _totalSampleLength = totalLength;
      _initialWeight = totalWeight / sampleCount;
      _initialLength = totalLength / sampleCount;
      await _batchesRef.doc(currentId).set({
        'initial_count': initial,
        'current_count': initial,
        'stocking_date': date.millisecondsSinceEpoch,
        'sample_count': sampleCount,
        'initial_total_weight': totalWeight,
        'initial_total_length': totalLength,
        'initial_abw': _initialWeight,
        'initial_abl': _initialLength,
      }, SetOptions(merge: true));
      await _saveConfig();
      notifyListeners();
      return;
    }

    final bid = requestedName.isNotEmpty ? requestedName : fallbackBid;
    if ((await _batchesRef.doc(bid).get()).exists) {
      throw StateError('A batch named "$bid" already exists');
    }

    // Superseding the previous active batch, creating the new batch, and
    // switching the tank pointer are committed atomically below.
    final existingActive =
        _batches.where((b) => b.status == 'active').firstOrNull;
    final previousFinalAbw = _samplingHistory.isNotEmpty
        ? _samplingHistory.last.abw
        : existingActive?.initialAbw ?? 0.0;
    final previousFinalAbl = _samplingHistory.isNotEmpty
        ? _samplingHistory.last.avgLength
        : existingActive?.initialAbl ?? 0.0;
    final previousMortality = _mortality;
    final previousHarvested = _totalHarvested;

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

    _selectedBatchId = bid;

    try {
      final writes = _fs.batch();
      if (existingActive != null) {
        writes.set(_batchesRef.doc(existingActive.batchId), {
          'batch_status': 'superseded',
          'days_in_culture': DateTime.now()
              .difference(existingActive.stockingDate)
              .inDays
              .clamp(0, 1000000),
          'final_abw': previousFinalAbw,
          'final_abl': previousFinalAbl,
          'total_mortality': previousMortality,
          'harvest_count': previousHarvested,
        }, SetOptions(merge: true));
      }
      writes.set(_batchesRef.doc(bid), {
        'batch_id': bid,
        'batch_status': 'active',
        'stocking_date': _stockingDate.millisecondsSinceEpoch,
        'harvest_date': null,
        'initial_count': _initialCount,
        'current_count': _initialCount,
        'harvest_count': 0,
        'total_mortality': 0,
        'harvest_weight_grams': null,
        'initial_abw': _initialWeight,
        'initial_abl': _initialLength,
        'final_abw': 0,
        'final_abl': 0,
        'days_in_culture': 0,
        'sample_count': _sampleCount,
        'initial_total_weight': _totalSampleWeight,
        'initial_total_length': _totalSampleLength,
        'created_at': FieldValue.serverTimestamp(),
      });
      writes.set(_tankRef, {
        'owner_uid': _currentUserUid.isNotEmpty
            ? _currentUserUid
            : _tankOwnerUid,
        'initial_population': _initialCount,
        'stocking_date': _stockingDate.millisecondsSinceEpoch,
        'last_sample_date': _lastSampleDate.millisecondsSinceEpoch,
        'sample_count': _sampleCount,
        'initial_total_sample_weight': _totalSampleWeight,
        'initial_total_sample_length': _totalSampleLength,
        'current_batch_id': bid,
        'is_initialized': true,
      }, SetOptions(merge: true));
      // Persist the initial measurement as a SEPARATE baseline sampling
      // record. It is excluded from the weekly cadence calculation and from
      // the "Week N" counter so the first weekly sampling is always Day 7
      // after stocking.
      if (_sampleCount > 0 && _totalSampleWeight > 0 && _totalSampleLength > 0) {
        final baselineDoc = _samplingRef(bid).doc('baseline');
        writes.set(baselineDoc, {
          'sampling_date': _stockingDate.millisecondsSinceEpoch,
          'avg_body_weight': _initialWeight,
          'avg_body_length': _initialLength,
          'sample_size': _sampleCount,
          'total_weight': _totalSampleWeight,
          'total_length': _totalSampleLength,
          'biomass': _initialCount * _initialWeight,
          'live_count': _initialCount,
          'is_baseline': true,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      await writes.commit();
    } catch (e) {
      debugPrint('[TankService] Atomic batch initialization failed: $e');
      await refresh();
      rethrow;
    }
    _addActivity('Initialized new grow-out batch with $initial population', 'init', customDate: date);

    _resubscribeToBatch();
    notifyListeners();
  }

  Future<void> addSamplingEntry(int count, double weight, double length) async {
    if (count <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (count > inTankCount) throw ArgumentError('Sample count exceeds in-tank population');
    if (weight <= 0 || length <= 0) {
      throw ArgumentError('Sample weight and length must be greater than zero');
    }
    if (_selectedBatchId == null || _selectedBatchId!.isEmpty) {
      throw ArgumentError('No batch selected');
    }

    _setupComplete = true;
    final now = DateTime.now();
    _lastSampleDate = now;
    final abw = weight / count;
    final avgLength = length / count;
    final entry = SamplingEntry(
      date: now, abw: abw, avgLength: avgLength, sampleSize: count,
      totalWeight: weight, totalLength: length, biomass: inTankCount * abw, liveCount: inTankCount,
    );
    try {
      await _samplingRef(_selectedBatchId!).add({
        'sampling_date': entry.date.millisecondsSinceEpoch,
        'avg_body_weight': entry.abw,
        'avg_body_length': entry.avgLength,
        'sample_size': entry.sampleSize,
        'total_weight': entry.totalWeight,
        'total_length': entry.totalLength,
        'biomass': entry.biomass,
        'live_count': entry.liveCount,
        'is_baseline': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      _addActivity('Recorded sampling: ${abw.toStringAsFixed(2)}g ABW, ${avgLength.toStringAsFixed(2)}cm ABL', 'sampling', sampleSize: count, abw: abw, avgLength: avgLength);
      await _saveConfig();
    } catch (e) {
      debugPrint('[TankService] Error saving sampling entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  Future<void> updateLastSamplingEntry(int count, double weight, double length) async {
    if (_lastSamplingDocId == null || _samplingHistory.isEmpty) return;
    if (_selectedBatchId == null) return;
    if (count <= 0) throw ArgumentError('Sample count must be greater than 0');
    if (count > inTankCount) throw ArgumentError('Sample count exceeds in-tank population');
    if (weight <= 0 || length <= 0) {
      throw ArgumentError('Sample weight and length must be greater than zero');
    }

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
      await _samplingRef(_selectedBatchId!).doc(_lastSamplingDocId!).update({
        'avg_body_weight': updated.abw,
        'avg_body_length': updated.avgLength,
        'sample_size': updated.sampleSize,
        'total_weight': updated.totalWeight,
        'total_length': updated.totalLength,
        'biomass': updated.biomass,
        'live_count': updated.liveCount,
        'created_at': FieldValue.serverTimestamp(),
      });
      _saveConfig();
    } catch (e) {
      debugPrint('[TankService] Error updating sampling entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  Future<void> addMortality(int val, {DateTime? date}) async {
    if (val <= 0) throw ArgumentError('Mortality count must be greater than 0');
    if (val > inTankCount) {
      throw ArgumentError('Mortality count exceeds in-tank population ($inTankCount)');
    }
    final batchId = _selectedBatchId;
    if (batchId == null || batchId.isEmpty) throw ArgumentError('No batch selected');

    _setupComplete = true;
    final mEntry = MortalityEntry(date: date ?? DateTime.now(), count: val);
    final batchRef = _batchesRef.doc(batchId);
    final recordRef = _mortalityRef(batchId).doc();
    int committedMortality = _mortality + val;
    try {
      await _fs.runTransaction((transaction) async {
        final batchSnap = await transaction.get(batchRef);
        if (!batchSnap.exists || batchSnap.data() == null) {
          throw StateError('Selected batch does not exist');
        }
        final data = batchSnap.data()!;
        final initial = (data['initial_count'] as num?)?.toInt() ?? _initialCount;
        final batchMortality =
            (data['total_mortality'] as num?)?.toInt() ?? 0;
        // Legacy active batches did not always update this aggregate. Prefer
        // the subscribed record total whenever it is higher.
        final existingMortality =
            batchMortality > _mortality ? batchMortality : _mortality;
        final existingHarvest =
            (data['harvest_count'] as num?)?.toInt() ?? _totalHarvested;
        final available =
            (initial - existingMortality - existingHarvest).clamp(0, initial);
        if (val > available) {
          throw StateError('Mortality count exceeds current in-tank population ($available)');
        }
        committedMortality = existingMortality + val;
        transaction.set(recordRef, {
          'mortality_date': mEntry.date.millisecondsSinceEpoch,
          'mortality_count': mEntry.count,
          'created_at': FieldValue.serverTimestamp(),
        });
        transaction.set(batchRef, {
          'total_mortality': committedMortality,
          'current_count':
              (initial - committedMortality - existingHarvest).clamp(0, initial),
        }, SetOptions(merge: true));
      });
      _mortality = committedMortality;
      _addActivity('Recorded mortality of $val crayfish (Total: $_mortality)', 'mortality', customDate: date);
    } catch (e) {
      debugPrint('[TankService] Error saving mortality entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  /// Updates the MOST RECENT mortality record (same-day rule, mirroring the
  /// sampling edit). Recalculates the total mortality and persists to Firestore.
  Future<void> updateLastMortalityEntry(int newCount) async {
    if (newCount <= 0) throw ArgumentError('Mortality count must be greater than 0');
    if (_mortalityHistory.isEmpty || _selectedBatchId == null) return;
    final last = _mortalityHistory.last;
    if (last.id.isEmpty) return;

    final batchId = _selectedBatchId!;
    final recordRef = _mortalityRef(batchId).doc(last.id);
    final batchRef = _batchesRef.doc(batchId);
    int committedMortality = _mortality - last.count + newCount;

    try {
      await _fs.runTransaction((transaction) async {
        final recordSnap = await transaction.get(recordRef);
        final batchSnap = await transaction.get(batchRef);
        if (!recordSnap.exists || recordSnap.data() == null ||
            !batchSnap.exists || batchSnap.data() == null) {
          throw StateError('Mortality record or batch no longer exists');
        }
        final actualOld =
            (recordSnap.data()!['mortality_count'] as num?)?.toInt() ?? last.count;
        final data = batchSnap.data()!;
        final initial = (data['initial_count'] as num?)?.toInt() ?? _initialCount;
        final batchMortality =
            (data['total_mortality'] as num?)?.toInt() ?? 0;
        // Legacy active batches did not always update this aggregate. Prefer
        // the subscribed record total whenever it is higher.
        final existingMortality =
            batchMortality > _mortality ? batchMortality : _mortality;
        final existingHarvest =
            (data['harvest_count'] as num?)?.toInt() ?? _totalHarvested;
        committedMortality = existingMortality - actualOld + newCount;
        final maxMortality = initial - existingHarvest;
        if (committedMortality < 0 || committedMortality > maxMortality) {
          throw StateError('Updated mortality exceeds available population ($maxMortality)');
        }
        transaction.update(recordRef, {
          'mortality_count': newCount,
          'created_at': FieldValue.serverTimestamp(),
        });
        transaction.set(batchRef, {
          'total_mortality': committedMortality,
          'current_count':
              (initial - committedMortality - existingHarvest).clamp(0, initial),
        }, SetOptions(merge: true));
      });
      _mortality = committedMortality;
      _mortalityHistory.last = MortalityEntry(
        id: last.id,
        date: last.date,
        count: newCount,
      );
      _addActivity('Updated last mortality record to $newCount (Total: $_mortality)', 'mortality');
    } catch (e) {
      debugPrint('[TankService] Error updating mortality entry: $e');
      rethrow;
    }
    notifyListeners();
  }

  Future<void> addHarvestRecord({
    required int harvestedCount,
    required double totalWeightKg,
    String? batchId,
    DateTime? date,
  }) async {
    if (harvestedCount <= 0) throw ArgumentError('Harvested count must be greater than 0');
    if (totalWeightKg <= 0) throw ArgumentError('Total harvest weight must be greater than zero');
    final resolvedBatchId = batchId ?? _selectedBatchId ?? '';
    if (resolvedBatchId.isEmpty) throw ArgumentError('No batch selected');
    if (harvestedCount > inTankCount) {
      throw ArgumentError('Harvest count exceeds in-tank population ($inTankCount)');
    }

    final now = date ?? DateTime.now();
    final abwGrams = (totalWeightKg * 1000) / harvestedCount;
    final batchRef = _batchesRef.doc(resolvedBatchId);
    final recordRef = _harvestRef(resolvedBatchId).doc();
    int committedTotal = _totalHarvested + harvestedCount;

    try {
      await _fs.runTransaction((transaction) async {
        final batchSnap = await transaction.get(batchRef);
        if (!batchSnap.exists || batchSnap.data() == null) {
          throw StateError('Selected batch does not exist');
        }
        final existing = batchSnap.data()!;
        final initial = (existing['initial_count'] as num?)?.toInt() ?? _initialCount;
        final batchDeaths =
            (existing['total_mortality'] as num?)?.toInt() ?? 0;
        final deaths = batchDeaths > _mortality ? batchDeaths : _mortality;
        final existingHarvest = (existing['harvest_count'] as num?)?.toInt() ?? 0;
        final available = (initial - deaths - existingHarvest).clamp(0, initial);
        if (harvestedCount > available) {
          throw StateError('Harvest count exceeds current available population ($available)');
        }
        committedTotal = existingHarvest + harvestedCount;
        final existingWeight =
            (existing['harvest_weight_grams'] as num?)?.toDouble() ?? 0.0;
        transaction.set(recordRef, {
          'batch_id': resolvedBatchId,
          'harvest_date': now.millisecondsSinceEpoch,
          'harvest_count': harvestedCount,
          'total_weight_kg': totalWeightKg,
          'abw_grams': abwGrams,
          'created_at': FieldValue.serverTimestamp(),
        });
        transaction.set(batchRef, {
          'harvest_date': now.millisecondsSinceEpoch,
          'harvest_count': committedTotal,
          'current_count': (initial - deaths - committedTotal).clamp(0, initial),
          'harvest_weight_grams': existingWeight + (totalWeightKg * 1000),
        }, SetOptions(merge: true));
      });

      _totalHarvested = committedTotal;
      _addActivity(
        'Harvested $harvestedCount crayfish, ${totalWeightKg.toStringAsFixed(2)}kg total (ABW: ${abwGrams.toStringAsFixed(1)}g)',
        'harvest',
      );
    } catch (e) {
      debugPrint('[TankService] Error saving harvest record: $e');
      rethrow;
    }
    notifyListeners();
  }

  /// Updates the MOST RECENT harvest record (same-day rule). Recalculates the
  /// running harvest totals and persists the batch-level aggregates.
  Future<void> updateLastHarvestRecord({
    required int harvestedCount,
    required double totalWeightKg,
  }) async {
    if (harvestedCount <= 0) throw ArgumentError('Harvested count must be greater than 0');
    if (totalWeightKg <= 0) throw ArgumentError('Total harvest weight must be greater than zero');
    if (_harvestRecords.isEmpty) return;
    final last = _harvestRecords.last;
    if (last.id.isEmpty) return;

    final resolvedBatchId =
        last.batchId.isNotEmpty ? last.batchId : (_selectedBatchId ?? '');
    if (resolvedBatchId.isEmpty) throw ArgumentError('No batch selected');
    final abwGrams = (totalWeightKg * 1000) / harvestedCount;
    final recordRef = _harvestRef(resolvedBatchId).doc(last.id);
    final batchRef = _batchesRef.doc(resolvedBatchId);
    int committedTotal = _totalHarvested;

    try {
      await _fs.runTransaction((transaction) async {
        final recordSnap = await transaction.get(recordRef);
        final batchSnap = await transaction.get(batchRef);
        if (!recordSnap.exists || recordSnap.data() == null ||
            !batchSnap.exists || batchSnap.data() == null) {
          throw StateError('Harvest record or batch no longer exists');
        }
        final recordData = recordSnap.data()!;
        final batchData = batchSnap.data()!;
        final actualOldCount =
            (recordData['harvest_count'] as num?)?.toInt() ?? last.harvestedCount;
        final actualOldWeight =
            (recordData['total_weight_kg'] as num?)?.toDouble() ?? last.totalWeightKg;
        final initial = (batchData['initial_count'] as num?)?.toInt() ?? _initialCount;
        final batchDeaths =
            (batchData['total_mortality'] as num?)?.toInt() ?? 0;
        final deaths = batchDeaths > _mortality ? batchDeaths : _mortality;
        final existingHarvest =
            (batchData['harvest_count'] as num?)?.toInt() ?? _totalHarvested;
        committedTotal = existingHarvest - actualOldCount + harvestedCount;
        final maxSurvivors = (initial - deaths).clamp(0, initial);
        if (committedTotal < 0 || committedTotal > maxSurvivors) {
          throw StateError('Updated harvest exceeds available population ($maxSurvivors)');
        }
        final previousWeight =
            (batchData['harvest_weight_grams'] as num?)?.toDouble() ?? 0.0;
        final newWeight = previousWeight - (actualOldWeight * 1000) +
            (totalWeightKg * 1000);

        transaction.update(recordRef, {
          'batch_id': resolvedBatchId,
          'harvest_count': harvestedCount,
          'total_weight_kg': totalWeightKg,
          'abw_grams': abwGrams,
          'created_at': FieldValue.serverTimestamp(),
        });
        transaction.set(batchRef, {
          'harvest_count': committedTotal,
          'current_count': (initial - deaths - committedTotal).clamp(0, initial),
          'harvest_weight_grams': newWeight.clamp(0.0, double.infinity),
        }, SetOptions(merge: true));
      });

      _totalHarvested = committedTotal;
      _harvestRecords.last = CrayfishHarvestRecord(
        id: last.id,
        batchId: resolvedBatchId,
        date: last.date,
        harvestedCount: harvestedCount,
        totalWeightKg: totalWeightKg,
        abwGrams: abwGrams,
      );
      _addActivity(
        'Updated last harvest to $harvestedCount crayfish, ${totalWeightKg.toStringAsFixed(2)}kg total',
        'harvest',
      );
    } catch (e) {
      debugPrint('[TankService] Error updating harvest record: $e');
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
      final batchRef = _batchesRef.doc(resolvedId);
      final batchSnap = await batchRef.get();
      if (batchSnap.exists) {
        await batchRef.set({
          'batch_status': 'harvested',
          'harvest_date': now.millisecondsSinceEpoch,
          'harvest_count': harvestCount,
          'harvest_weight_grams': harvestWeightGrams,
          'days_in_culture': daysInCulture,
          'total_mortality': _mortality,
          'final_abw': samplingHistory.isNotEmpty ? samplingHistory.last.abw : _initialWeight,
          'final_abl': samplingHistory.isNotEmpty ? samplingHistory.last.avgLength : _initialLength,
        }, SetOptions(merge: true));
      }

      await _tankRef.set({
        'current_batch_id': '',
        'initial_population': 0,
        'last_sample_date': 0,
        'sample_count': 0,
        'initial_total_sample_weight': 0,
        'initial_total_sample_length': 0,
        'is_initialized': false,
      }, SetOptions(merge: true));

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
