import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/lettuce_batch.dart';
import 'db_paths.dart';

enum LettuceGrowthStage {
  seedling('Seedling', '0–14 days', Icons.eco_rounded, Color(0xFF81C784), 'Young plants establishing roots'),
  vegetative('Vegetative', '15–35 days', Icons.eco_rounded, Color(0xFF4CAF50), 'Active leaf and root growth'),
  mature('Mature / Harvest', '35–50 days', Icons.agriculture_rounded, Color(0xFF2E7D32), 'Ready for harvest');

  final String label;
  final String range;
  final IconData icon;
  final Color color;
  final String description;

  const LettuceGrowthStage(this.label, this.range, this.icon, this.color, this.description);
}

class LettuceService extends ChangeNotifier {
  static final LettuceService instance = LettuceService._();
  LettuceService._();

  static Map<String, dynamic> _convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  String _tankOwnerUid = '';
  bool _isInitialized = false;
  List<LettuceBatch> _batches = [];
  List<LettuceBatch> _harvestHistory = [];
  String? _selectedBatchId;

  final Map<String, List<LettuceGrowthEntry>> _growthLogs = {};
  final Map<String, List<LettuceMortalityRecord>> _mortalityLogs = {};
  final Map<String, List<LettuceSamplingEntry>> _samplingHistory = {};
  List<Map<String, dynamic>> _activities = [];
  List<LettuceHarvestRecord> _harvestRecords = [];

  DatabaseReference get _batchesRef =>
      DbPaths.lettuceBatches(_tankOwnerUid);
  DatabaseReference get _growthRef =>
      DbPaths.lettuceGrowth(_tankOwnerUid);
  DatabaseReference get _activitiesRef =>
      DbPaths.lettuceActivities(_tankOwnerUid);
  DatabaseReference get _mortalityRef =>
      DbPaths.lettuceMortality(_tankOwnerUid);
  DatabaseReference get _samplingRef =>
      DbPaths.lettuceSampling(_tankOwnerUid);
  DatabaseReference get _harvestsRef =>
      DbPaths.lettuceHarvests(_tankOwnerUid);

  bool get isInitialized => _isInitialized;
  List<LettuceBatch> get batches => List.unmodifiable(_batches);
  List<LettuceBatch> get activeBatches =>
      _batches.where((b) => b.status == 'active').toList();
  LettuceBatch? get selectedBatch =>
      _selectedBatchId != null
          ? _batches.cast<LettuceBatch?>().firstWhere(
              (b) => b?.batchId == _selectedBatchId,
              orElse: () => null,
            )
          : activeBatches.isNotEmpty ? activeBatches.first : null;
  String? get selectedBatchId => _selectedBatchId;
  List<LettuceBatch> get harvestHistory => List.unmodifiable(_harvestHistory);
  List<Map<String, dynamic>> get activities => List.unmodifiable(_activities.reversed);
  List<LettuceHarvestRecord> get harvestRecords => List.unmodifiable(_harvestRecords.reversed);

  bool get hasActiveBatch => activeBatches.isNotEmpty;
  int get currentQuantity => selectedBatch?.currentQuantity ?? 0;
  int get initialQuantity => selectedBatch?.initialQuantity ?? 0;
  String get batchId => selectedBatch?.batchId ?? '';
  DateTime get plantingDate => selectedBatch?.plantingDate ?? DateTime.now();

  List<LettuceGrowthEntry> get growthHistory {
    final sid = _selectedBatchId;
    if (sid == null || !_growthLogs.containsKey(sid)) return [];
    return List.unmodifiable(_growthLogs[sid]!);
  }

  List<LettuceMortalityRecord> get mortalityHistory {
    final sid = _selectedBatchId;
    if (sid == null || !_mortalityLogs.containsKey(sid)) return [];
    return List.unmodifiable(_mortalityLogs[sid]!);
  }

  List<LettuceGrowthEntry> getGrowthLogsForBatch(String batchId) {
    if (!_growthLogs.containsKey(batchId)) return [];
    return List.unmodifiable(_growthLogs[batchId]!);
  }

  List<LettuceMortalityRecord> getMortalityLogsForBatch(String batchId) {
    if (!_mortalityLogs.containsKey(batchId)) return [];
    return List.unmodifiable(_mortalityLogs[batchId]!);
  }

  List<LettuceSamplingEntry> get samplingHistory {
    final sid = _selectedBatchId;
    if (sid == null || !_samplingHistory.containsKey(sid)) return [];
    return List.unmodifiable(_samplingHistory[sid]!);
  }

  List<LettuceSamplingEntry> getSamplingForBatch(String batchId) {
    if (!_samplingHistory.containsKey(batchId)) return [];
    return List.unmodifiable(_samplingHistory[batchId]!);
  }

  int get daysSinceLastLettuceSampling {
    final history = samplingHistory;
    if (history.isEmpty) return daysInCultivation;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = history.last.date;
    return today.difference(DateTime(last.year, last.month, last.day)).inDays;
  }

  bool get hasSamplingThisWeek {
    final history = samplingHistory;
    if (history.isEmpty) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = today.add(Duration(days: 7 - today.weekday));
    for (final entry in history) {
      final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
      if (!entryDate.isBefore(monday) && !entryDate.isAfter(sunday)) return true;
    }
    return false;
  }

  bool get canSampleLettuce => daysSinceLastLettuceSampling >= 7 && !hasSamplingThisWeek;
  int get daysUntilNextLettuceSampling {
    final remaining = 7 - daysSinceLastLettuceSampling;
    return remaining < 0 ? 0 : remaining;
  }

  int get daysInCultivation {
    final batch = selectedBatch;
    if (batch == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planted = batch.plantingDate;
    return today.difference(DateTime(planted.year, planted.month, planted.day)).inDays;
  }

  int get daysUntilHarvest {
    final passed = daysInCultivation;
    final remaining = 30 - passed;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isReadyToHarvest => daysInCultivation >= 30;

  LettuceGrowthStage get growthStage {
    final days = daysInCultivation;
    if (days <= 14) return LettuceGrowthStage.seedling;
    if (days <= 35) return LettuceGrowthStage.vegetative;
    return LettuceGrowthStage.mature;
  }

  bool _migrationDone = false;

  void init() {
    final initialUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    debugPrint('[LettuceService] init() currentUser.uid="$initialUid"');
    if (initialUid.isNotEmpty) {
      _tankOwnerUid = initialUid;
      _initializeForUid();
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid ?? '';
      debugPrint('[LettuceService] authStateChanges event: uid="$uid"');
      if (uid.isEmpty) {
        _resetAll();
        return;
      }
      if (uid == _tankOwnerUid) return;
      _tankOwnerUid = uid;
      _cancelSubscriptions();
      _initializeForUid();
    });
  }

  Future<void> _initializeForUid() async {
    _migrationDone = false;
    try {
      await _migrateIfNeeded();
      await _loadConfig();
      _listenFirebase();
    } catch (e) {
      debugPrint('[LettuceService] _initializeForUid error: $e');
    }
  }

  Future<void> _migrateIfNeeded() async {
    if (_migrationDone) return;
    try {
      final db = FirebaseDatabase.instance;

      final oldBatchRef = db.ref('tank_data/$_tankOwnerUid/lettuce_batch');
      final oldHistoryRef = db.ref('tank_data/$_tankOwnerUid/lettuce_history');
      final oldGrowthRef = db.ref('tank_data/$_tankOwnerUid/lettuce_growth');
      final oldBatchSnap = await oldBatchRef.get();
      final oldHistorySnap = await oldHistoryRef.get();
      final hasOldBatch = oldBatchSnap.exists;
      final hasOldHistory = oldHistorySnap.exists;

      if (hasOldBatch) {
        final data = _convertMap(oldBatchSnap.value as Map);
        data['status'] = 'active';
        data['harvestedQuantity'] = data['harvestedQuantity'] ?? 0;
        await _batchesRef.push().set(data);

        final oldGrowthSnap = await oldGrowthRef.get();
        if (oldGrowthSnap.exists) {
          final batchId = data['batchId'] as String;
          final gData = _convertMap(oldGrowthSnap.value as Map);
          for (final entry in gData.entries) {
            final map = _convertMap(entry.value as Map);
            map['batchId'] = batchId;
            await _growthRef.child(batchId).child(entry.key).set(map);
          }
        }
        await oldBatchRef.remove();
        await oldGrowthRef.remove();
      }

      if (hasOldHistory) {
        final hData = _convertMap(oldHistorySnap.value as Map);
        for (final entry in hData.entries) {
          final map = _convertMap(entry.value as Map);
          map['status'] = 'harvested';
          await _batchesRef.push().set(map);
        }
        await oldHistoryRef.remove();
      }

      final oldLogsRef = db.ref('tank_data/$_tankOwnerUid/logs');
      final oldLogsSnap = await oldLogsRef.get();
      if (oldLogsSnap.exists && oldLogsSnap.value != null) {
        final lData = _convertMap(oldLogsSnap.value as Map);
        for (final entry in lData.entries) {
          final map = _convertMap(entry.value as Map);
          if (map['type'] == 'lettuce') {
            await _activitiesRef.child(entry.key).set(entry.value);
          }
        }
      }

      final newBatchesSnap = await _batchesRef.get();
      if (!newBatchesSnap.exists || newBatchesSnap.value == null) {
        final oldLettuceBatchesRef = db.ref('tank_data/$_tankOwnerUid/lettuce_batches');
        final oldLBatchSnap = await oldLettuceBatchesRef.get();
        if (oldLBatchSnap.exists && oldLBatchSnap.value != null) {
          final data = _convertMap(oldLBatchSnap.value as Map);
          for (final entry in data.entries) {
            await _batchesRef.child(entry.key).set(entry.value);
          }
        }

        final oldLettuceGrowthRef = db.ref('tank_data/$_tankOwnerUid/lettuce_growth');
        final oldLGrowthSnap = await oldLettuceGrowthRef.get();
        if (oldLGrowthSnap.exists && oldLGrowthSnap.value != null) {
          final gData = _convertMap(oldLGrowthSnap.value as Map);
          for (final batchEntry in gData.entries) {
            final batchId = batchEntry.key;
            final logsData = _convertMap(batchEntry.value as Map);
            for (final logEntry in logsData.entries) {
              await _growthRef.child(batchId).child(logEntry.key).set(logEntry.value);
            }
          }
        }
      }

      await _migrateActivityBatchIds();

      _migrationDone = true;
      debugPrint('[LettuceService] Migration complete');
    } catch (e) {
      debugPrint('[LettuceService] Migration error: $e');
    }
  }

  Future<void> _migrateActivityBatchIds() async {
    try {
      final snap = await _activitiesRef.get();
      if (!snap.exists || snap.value == null) return;
      final data = _convertMap(snap.value as Map);
      for (final entry in data.entries) {
        final key = entry.key;
        final map = _convertMap(entry.value as Map);
        if (map['batchId'] != null || map['type'] != 'lettuce') continue;

        String? batchId;
        final action = map['action'] as String? ?? '';
        final initMatch = RegExp(r'Initialized new lettuce batch \(([^)]+)\)').firstMatch(action);
        if (initMatch != null) {
          batchId = initMatch.group(1);
        }
        if (batchId == null) {
          final harvestMatch = RegExp(r'Harvested lettuce batch \(([^)]+)\)').firstMatch(action);
          if (harvestMatch != null) {
            batchId = harvestMatch.group(1);
          }
        }
        if (batchId == null) {
          final mortalityMatch = RegExp(r'in batch ([^.]+)\.?$').firstMatch(action);
          if (mortalityMatch != null) {
            batchId = mortalityMatch.group(1)?.trim();
          }
        }
        if (batchId != null) {
          await _activitiesRef.child(key).child('batchId').set(batchId);
        }
      }
      debugPrint('[LettuceService] Activity batchId migration complete');
    } catch (e) {
      debugPrint('[LettuceService] Activity batchId migration error: $e');
    }
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await _batchesRef.get();
      if (!snap.exists || snap.value == null) {
        _batches = [];
        _harvestHistory = [];
        _isInitialized = false;
        notifyListeners();
        return;
      }
      if (snap.value != null) {
        final data = _convertMap(snap.value as Map);
        _parseBatchMap(data);
      }
    } catch (e) {
      debugPrint('[LettuceService] _loadConfig error: $e');
    }
  }

  void _parseBatches(DatabaseEvent e) {
    if (!e.snapshot.exists || e.snapshot.value == null) {
      _batches = [];
      _harvestHistory = [];
      _isInitialized = false;
      notifyListeners();
      return;
    }
    final data = _convertMap(e.snapshot.value as Map);
    _parseBatchMap(data);
  }

  void _parseBatchMap(Map<String, dynamic> raw) {
    if (raw.isEmpty) {
      _batches = [];
      _harvestHistory = [];
      _isInitialized = false;
      notifyListeners();
      return;
    }
    final list = <LettuceBatch>[];
    for (final val in raw.values) {
      final map = _convertMap(val as Map);
      list.add(LettuceBatch.fromJson(map));
    }
    list.sort((a, b) => b.plantingDate.compareTo(a.plantingDate));
    _batches = list;
    _harvestHistory = list.where((b) => b.status == 'harvested').toList();
    _isInitialized = list.isNotEmpty;

    if (_selectedBatchId != null && !list.any((b) => b.batchId == _selectedBatchId)) {
      final active = list.where((b) => b.status == 'active');
      _selectedBatchId = active.isNotEmpty ? active.first.batchId : null;
    }
    notifyListeners();
  }

  void _resetAll() {
    _isInitialized = false;
    _batches = [];
    _harvestHistory = [];
    _growthLogs.clear();
    _mortalityLogs.clear();
    _samplingHistory.clear();
    _harvestRecords.clear();
    _activities.clear();
    _selectedBatchId = null;
    notifyListeners();
  }

  StreamSubscription<DatabaseEvent>? _batchesSub;
  StreamSubscription<DatabaseEvent>? _growthSub;
  StreamSubscription<DatabaseEvent>? _mortalitySub;
  StreamSubscription<DatabaseEvent>? _samplingSub;
  StreamSubscription<DatabaseEvent>? _harvestsSub;
  StreamSubscription<DatabaseEvent>? _activitiesSub;

  void _cancelSubscriptions() {
    _batchesSub?.cancel();
    _growthSub?.cancel();
    _mortalitySub?.cancel();
    _samplingSub?.cancel();
    _harvestsSub?.cancel();
    _activitiesSub?.cancel();
    _batchesSub = null;
    _growthSub = null;
    _mortalitySub = null;
    _samplingSub = null;
    _harvestsSub = null;
    _activitiesSub = null;
  }

  void _listenFirebase() {
    _batchesSub = _batchesRef.onValue.listen(_parseBatches);

    _growthSub = _growthRef.onValue.listen((e) {
      _growthLogs.clear();
      if (!e.snapshot.exists || e.snapshot.value == null) {
        notifyListeners();
        return;
      }
      final data = _convertMap(e.snapshot.value as Map);
      for (final batchEntry in data.entries) {
        final batchId = batchEntry.key;
        final logsData = _convertMap(batchEntry.value as Map);
        final logs = <LettuceGrowthEntry>[];
        for (final val in logsData.values) {
          final map = _convertMap(val as Map);
          logs.add(LettuceGrowthEntry.fromJson(map));
        }
        logs.sort((a, b) => a.date.compareTo(b.date));
        _growthLogs[batchId] = logs;
      }
      notifyListeners();
    });

    _samplingSub = _samplingRef.onValue.listen((e) {
      _samplingHistory.clear();
      if (!e.snapshot.exists || e.snapshot.value == null) {
        notifyListeners();
        return;
      }
      final data = _convertMap(e.snapshot.value as Map);
      for (final batchEntry in data.entries) {
        final batchId = batchEntry.key;
        final logsData = _convertMap(batchEntry.value as Map);
        final list = <LettuceSamplingEntry>[];
        for (final val in logsData.values) {
          final map = _convertMap(val as Map);
          list.add(LettuceSamplingEntry.fromJson(map));
        }
        list.sort((a, b) => a.date.compareTo(b.date));
        _samplingHistory[batchId] = list;
      }
      notifyListeners();
    });

    _mortalitySub = _mortalityRef.onValue.listen((e) {
      _mortalityLogs.clear();
      if (!e.snapshot.exists || e.snapshot.value == null) {
        notifyListeners();
        return;
      }
      final data = _convertMap(e.snapshot.value as Map);
      for (final batchEntry in data.entries) {
        final batchId = batchEntry.key;
        final logsData = _convertMap(batchEntry.value as Map);
        final logs = <LettuceMortalityRecord>[];
        for (final val in logsData.values) {
          final map = _convertMap(val as Map);
          logs.add(LettuceMortalityRecord.fromJson(map));
        }
        logs.sort((a, b) => a.date.compareTo(b.date));
        _mortalityLogs[batchId] = logs;
      }
      notifyListeners();
    });

    _harvestsSub = _harvestsRef.onValue.listen((e) {
      _harvestRecords.clear();
      if (!e.snapshot.exists || e.snapshot.value == null) {
        notifyListeners();
        return;
      }
      final hData = _convertMap(e.snapshot.value as Map);
      _harvestRecords = hData.entries.map((entry) =>
        LettuceHarvestRecord.fromJson(entry.key, _convertMap(entry.value as Map))
      ).toList()..sort((a, b) => a.date.compareTo(b.date));
      notifyListeners();
    });

    _activitiesSub = _activitiesRef.onValue.listen((e) {
      _activities.clear();
      if (!e.snapshot.exists || e.snapshot.value == null) {
        notifyListeners();
        return;
      }
      final aData = _convertMap(e.snapshot.value as Map);
      _activities = aData.values.map((e) => _convertMap(e as Map)).toList();
      notifyListeners();
    });
  }

  void selectBatch(String? batchId) {
    if (batchId == null) {
      _selectedBatchId = null;
      notifyListeners();
      return;
    }
    if (_batches.any((b) => b.batchId == batchId)) {
      _selectedBatchId = batchId;
      notifyListeners();
    }
  }

  Future<void> initializeBatch({
    required int quantity,
    double totalHeight = 0,
    int totalLeafCount = 0,
    String? batchNumber,
  }) async {
    if (_tankOwnerUid.isEmpty) {
      final fallbackUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (fallbackUid.isNotEmpty) {
        debugPrint('[LettuceService] _tankOwnerUid was empty, recovering from currentUser: "$fallbackUid"');
        _tankOwnerUid = fallbackUid;
        _cancelSubscriptions();
        _migrationDone = false;
        await _migrateIfNeeded();
        await _loadConfig();
        _listenFirebase();
      } else {
        debugPrint('[LettuceService] Cannot initialize: _tankOwnerUid is empty and currentUser is null');
        throw Exception('User not authenticated. Please sign in and try again.');
      }
    }
    debugPrint('[LettuceService] initializeBatch: _tankOwnerUid="$_tankOwnerUid"');
    final now = DateTime.now();
    final batchNum = batchNumber ?? 'Batch ${_batches.length + 1}';

    final batch = LettuceBatch(
      batchId: batchNum,
      batchNumber: batchNumber,
      status: 'active',
      plantingDate: now,
      initialQuantity: quantity,
      initialTotalHeight: totalHeight,
      initialTotalLeafCount: totalLeafCount,
      currentQuantity: quantity,
    );

    final path = _batchesRef.toString();
    debugPrint('[LettuceService] Writing batch to Firebase path: $path');
    _batchesRef.push().set(batch.toJson()).catchError((e) {
      debugPrint('[LettuceService] Batch push error (non-fatal): $e');
    });
    _selectedBatchId = batchNum;
    _batches.insert(0, batch);
    notifyListeners();

    try {
      final logKey = _activitiesRef.push().key ?? now.millisecondsSinceEpoch.toString();
      await _activitiesRef.child(logKey).set({
        'action': 'Initialized new lettuce batch ($batchNum) with $quantity seedlings (H: ${totalHeight}cm, L: $totalLeafCount).',
        'type': 'lettuce',
        'batchId': batchNum,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[LettuceService] initializeBatch activity log error: $e');
    }
  }

  Future<void> addGrowthLog({
    required double plantHeightCm,
    String? forBatchId,
  }) async {
    final batchId = forBatchId ?? _selectedBatchId;
    if (batchId == null) return;
    final now = DateTime.now();
    final entry = LettuceGrowthEntry(
      date: now,
      plantHeightCm: plantHeightCm,
      batchId: batchId,
    );

    try {
      await _growthRef.child(batchId).push().set(entry.toJson());

      final actKey = _activitiesRef.push().key ?? now.millisecondsSinceEpoch.toString();
      await _activitiesRef.child(actKey).set({
        'action': 'Logged lettuce growth: ${plantHeightCm}cm height.',
        'type': 'lettuce',
        'batchId': batchId,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[LettuceService] addGrowthLog error: $e');
      rethrow;
    }
  }

  Future<void> addLettuceSampling({
    required int sampleSize,
    required double totalHeight,
    required int totalLeafCount,
    String? forBatchId,
  }) async {
    final batchId = forBatchId ?? _selectedBatchId;
    if (batchId == null) return;
    final now = DateTime.now();
    final avgHeight = totalHeight / sampleSize;
    final avgLeafCount = totalLeafCount / sampleSize;
    final entry = LettuceSamplingEntry(
      date: now,
      sampleSize: sampleSize,
      totalHeight: totalHeight,
      totalLeafCount: totalLeafCount,
      avgHeight: avgHeight,
      avgLeafCount: avgLeafCount,
    );

    try {
      await _samplingRef.child(batchId).push().set(entry.toJson());

      final actKey = _activitiesRef.push().key ?? now.millisecondsSinceEpoch.toString();
      await _activitiesRef.child(actKey).set({
        'action': 'Sampled lettuce: ${sampleSize} plants, avg ${avgHeight.toStringAsFixed(1)}cm height, ${avgLeafCount.toStringAsFixed(0)} leaves.',
        'type': 'lettuce',
        'batchId': batchId,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[LettuceService] addLettuceSampling error: $e');
      rethrow;
    }
  }

  Future<void> addMortality({
    required int count,
    String? forBatchId,
  }) async {
    final batchId = forBatchId ?? _selectedBatchId;
    if (batchId == null) return;
    final now = DateTime.now();

    final record = LettuceMortalityRecord(
      date: now,
      count: count,
      batchId: batchId,
    );

    try {
      await _mortalityRef.child(batchId).push().set(record.toJson());

      final batch = _batches.firstWhere(
        (b) => b.batchId == batchId,
        orElse: () => throw Exception('Batch $batchId not found'),
      );
      final newCurrent = (batch.currentQuantity - count).clamp(0, batch.currentQuantity);

      final snap = await _batchesRef.orderByChild('batchId').equalTo(batchId).get();
      if (snap.exists && snap.value != null) {
        final data = _convertMap(snap.value as Map);
        final pushKey = data.keys.first;
        await _batchesRef.child(pushKey).child('currentQuantity').set(newCurrent);

        final existingMortality = (data.values.first as Map)['totalMortality'] as int? ?? 0;
        await _batchesRef.child(pushKey).child('totalMortality').set(existingMortality + count);
      }

      final actKey = _activitiesRef.push().key ?? now.millisecondsSinceEpoch.toString();
      await _activitiesRef.child(actKey).set({
        'action': 'Logged plant loss: $count dead/wilted plants in batch $batchId.',
        'type': 'lettuce',
        'batchId': batchId,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[LettuceService] addMortality error: $e');
      rethrow;
    }
  }

  Future<void> addLettuceHarvestRecord({
    required int harvestedCount,
    required double totalWeightKg,
    String? batchId,
  }) async {
    final now = DateTime.now();
    final avgWeight = harvestedCount > 0 ? (totalWeightKg * 1000) / harvestedCount : 0.0;
    await _harvestsRef.push().set({
      'batchId': batchId ?? _selectedBatchId ?? '',
      'harvestedCount': harvestedCount,
      'totalWeightKg': totalWeightKg,
      'avgWeightGrams': avgWeight,
      'timestamp': now.millisecondsSinceEpoch,
    });

    final resolvedBatchId = batchId ?? _selectedBatchId;
    if (resolvedBatchId != null) {
      try {
        final snap = await _batchesRef.orderByChild('batchId').equalTo(resolvedBatchId).get();
        if (snap.exists && snap.value != null) {
          final data = _convertMap(snap.value as Map);
          final pushKey = data.keys.first;
          final batchData = _convertMap(data.values.first as Map);
          final currentQty = (batchData['currentQuantity'] as num?)?.toInt() ?? 0;
          final newCurrent = (currentQty - harvestedCount).clamp(0, currentQty);
          await _batchesRef.child(pushKey).child('currentQuantity').set(newCurrent);
        }
      } catch (e) {
        debugPrint('[LettuceService] addLettuceHarvestRecord batch update error: $e');
      }
    }

    notifyListeners();
  }

  Future<void> harvestBatch({
    required String batchId,
    required int harvestedCount,
    double? weightKg,
  }) async {
    final batch = _batches.firstWhere(
      (b) => b.batchId == batchId,
      orElse: () => throw Exception('Batch $batchId not found'),
    );
    final now = DateTime.now();
    try {
      final growthSnap = await _growthRef.child(batchId).get();
      Map<String, dynamic>? archivedGrowth;
      if (growthSnap.exists && growthSnap.value != null) {
        archivedGrowth = _convertMap(growthSnap.value as Map);
      }

      final mortalitySnap = await _mortalityRef.child(batchId).get();
      Map<String, dynamic>? archivedMortality;
      if (mortalitySnap.exists && mortalitySnap.value != null) {
        archivedMortality = _convertMap(mortalitySnap.value as Map);
      }

      final harvestedBatch = LettuceBatch(
        batchId: batch.batchId,
        batchNumber: batch.batchNumber,
        status: 'harvested',
        plantingDate: batch.plantingDate,
        initialQuantity: batch.initialQuantity,
        currentQuantity: batch.currentQuantity,
        harvestedQuantity: harvestedCount,
        harvestDate: now,
        harvestWeightKg: weightKg,
        archivedGrowth: archivedGrowth,
        archivedMortality: archivedMortality,
        totalMortality: batch.totalMortality,
      );

      final snap = await _batchesRef.orderByChild('batchId').equalTo(batchId).get();
      if (snap.exists && snap.value != null) {
        final data = _convertMap(snap.value as Map);
        final pushKey = data.keys.first;
        await _batchesRef.child(pushKey).set(harvestedBatch.toJson());
      }

      await _growthRef.child(batchId).remove();
      await _mortalityRef.child(batchId).remove();

      final idx = _batches.indexWhere((b) => b.batchId == batchId);
      if (idx >= 0) {
        _batches[idx] = harvestedBatch;
      }
      _harvestHistory = _batches.where((b) => b.status == 'harvested').toList();

      if (_selectedBatchId == batchId) {
        _selectedBatchId = null;
      }

      final weightStr = weightKg != null ? '${weightKg.toStringAsFixed(2)}kg' : 'N/A';
      final actKey = _activitiesRef.push().key ?? now.millisecondsSinceEpoch.toString();
      await _activitiesRef.child(actKey).set({
        'action': 'Harvested lettuce batch (${harvestedBatch.batchId}): $harvestedCount plants, $weightStr.',
        'type': 'lettuce',
        'batchId': batchId,
        'timestamp': now.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[LettuceService] harvestBatch error: $e');
      rethrow;
    }
  }

  Future<List<LettuceGrowthEntry>> getArchivedBatchDetails(String batchId) async {
    try {
      final snap = await _batchesRef.orderByChild('batchId').equalTo(batchId).limitToLast(1).get();
      if (!snap.exists || snap.value == null) return [];

      final data = _convertMap(snap.value as Map);
      final entry = data.values.first;
      final map = _convertMap(entry as Map);

      final rawGrowth = map['archivedGrowth'];
      if (rawGrowth == null || rawGrowth is! Map) return [];

      final List<LettuceGrowthEntry> archivedGrowth = [];
      final gData = _convertMap(rawGrowth);
      for (final v in gData.values) {
        final gMap = _convertMap(v as Map);
        archivedGrowth.add(LettuceGrowthEntry.fromJson(gMap));
      }
      archivedGrowth.sort((a, b) => a.date.compareTo(b.date));
      return archivedGrowth;
    } catch (e) {
      debugPrint('[LettuceService] getArchivedBatchDetails error: $e');
      return [];
    }
  }

  Future<List<LettuceMortalityRecord>> getArchivedMortalityDetails(String batchId) async {
    try {
      final snap = await _batchesRef.orderByChild('batchId').equalTo(batchId).limitToLast(1).get();
      if (!snap.exists || snap.value == null) return [];

      final data = _convertMap(snap.value as Map);
      final entry = data.values.first;
      final map = _convertMap(entry as Map);

      final rawMortality = map['archivedMortality'];
      if (rawMortality == null || rawMortality is! Map) return [];

      final List<LettuceMortalityRecord> archivedMortality = [];
      final mData = _convertMap(rawMortality);
      for (final v in mData.values) {
        final mMap = _convertMap(v as Map);
        archivedMortality.add(LettuceMortalityRecord.fromJson(mMap));
      }
      archivedMortality.sort((a, b) => a.date.compareTo(b.date));
      return archivedMortality;
    } catch (e) {
      debugPrint('[LettuceService] getArchivedMortalityDetails error: $e');
      return [];
    }
  }
}
