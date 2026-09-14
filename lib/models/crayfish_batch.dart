import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/prediction_timestamp.dart';

DateTime _readProductionDate(dynamic value) =>
    parsePredictionTimestamp(value)?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

class CrayfishHarvestRecord {
  final String id;
  final String batchId;
  final DateTime date;
  final int harvestedCount;
  final double totalWeightKg;
  double get abwGrams =>
      harvestedCount > 0 ? totalWeightKg * 1000 / harvestedCount : 0.0;

  CrayfishHarvestRecord({
    required this.id,
    required this.batchId,
    required this.date,
    required this.harvestedCount,
    required this.totalWeightKg,
  });

  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'harvest_date': Timestamp.fromDate(date.toUtc()),
    'harvest_count': harvestedCount,
    'total_weight_kg': totalWeightKg,
  };

  factory CrayfishHarvestRecord.fromJson(
    String id,
    Map<String, dynamic> json,
  ) => CrayfishHarvestRecord(
    id: id,
    batchId: json['batch_id'] as String? ?? '',
    date: _readProductionDate(json['harvest_date']),
    harvestedCount: (json['harvest_count'] as num?)?.toInt() ?? 0,
    totalWeightKg: (json['total_weight_kg'] as num?)?.toDouble() ?? 0,
  );
}

class CrayfishBatch {
  final String batchId;
  final String status;
  final DateTime stockingDate;
  final DateTime? harvestDate;
  final DateTime? endedAt;
  final int initialCount;
  final int harvestCount;
  final int totalMortality;
  final double? harvestWeightGrams;
  final double initialAbw;
  final double initialAbl;
  final double finalAbw;
  final double finalAbl;
  final int sampleCount;
  final double initialTotalWeight;
  final double initialTotalLength;
  final Map<String, dynamic>? archivedSampling;
  final Map<String, dynamic>? archivedMortality;

  CrayfishBatch({
    required this.batchId,
    this.status = 'harvested',
    required this.stockingDate,
    this.harvestDate,
    this.endedAt,
    this.initialCount = 0,
    this.harvestCount = 0,
    this.totalMortality = 0,
    this.harvestWeightGrams,
    this.initialAbw = 0,
    this.initialAbl = 0,
    this.finalAbw = 0,
    this.finalAbl = 0,
    this.sampleCount = 0,
    this.initialTotalWeight = 0,
    this.initialTotalLength = 0,
    this.archivedSampling,
    this.archivedMortality,
  });

  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'batch_status': status,
    'stocking_date': Timestamp.fromDate(stockingDate.toUtc()),
    'harvest_date': harvestDate == null
        ? null
        : Timestamp.fromDate(harvestDate!.toUtc()),
    if (endedAt != null) 'ended_at': Timestamp.fromDate(endedAt!.toUtc()),
    'initial_count': initialCount,
    'harvest_count': harvestCount,
    'total_mortality': totalMortality,
    'harvest_weight_grams': harvestWeightGrams,
    'sample_count': sampleCount,
    'initial_total_weight': initialTotalWeight,
    'initial_total_length': initialTotalLength,
    if (archivedSampling != null) 'archived_sampling': archivedSampling,
    if (archivedMortality != null) 'archived_mortality': archivedMortality,
  };

  factory CrayfishBatch.fromJson(Map<String, dynamic> json) {
    // Firebase nested maps come as Map<Object?, Object?>, which can't
    // be directly cast to Map<String, dynamic> — convert safely here.
    Map<String, dynamic>? safeMap(dynamic v) {
      if (v is Map) return v.map<String, dynamic>((k, v) => MapEntry('$k', v));
      return null;
    }

    final rawSampling =
        safeMap(json['archived_sampling']) ?? safeMap(json['archivedSampling']);
    final legacyInitialAbw = (json['initial_abw'] as num?)?.toDouble();
    final legacyInitialAbl = (json['initial_abl'] as num?)?.toDouble();

    int fallbackSampleCount = 0;
    if (rawSampling != null && rawSampling.isNotEmpty) {
      final sortedEntries =
          rawSampling.values.map((v) {
            if (v is Map) {
              return v.map<String, dynamic>(
                (k, val) => MapEntry(k.toString(), val),
              );
            }
            return <String, dynamic>{};
          }).toList()..sort((a, b) {
            final da = _readProductionDate(a['sampling_date']);
            final db = _readProductionDate(b['sampling_date']);
            return da.compareTo(db);
          });
      if (sortedEntries.isNotEmpty) {
        fallbackSampleCount =
            (sortedEntries.first['sample_size'] as num?)?.toInt() ?? 0;
      }
    }

    final sampleCount =
        (json['sample_count'] as num?)?.toInt() ?? fallbackSampleCount;
    final initialTotalWeight =
        (json['initial_total_weight'] as num?)?.toDouble() ??
        ((legacyInitialAbw ?? 0) * sampleCount);
    final initialTotalLength =
        (json['initial_total_length'] as num?)?.toDouble() ??
        ((legacyInitialAbl ?? 0) * sampleCount);
    final initialAbw = sampleCount > 0 && initialTotalWeight > 0
        ? initialTotalWeight / sampleCount
        : legacyInitialAbw ?? 0.0;
    final initialAbl = sampleCount > 0 && initialTotalLength > 0
        ? initialTotalLength / sampleCount
        : legacyInitialAbl ?? 0.0;

    return CrayfishBatch(
      batchId: json['batch_id'] as String? ?? 'Unknown',
      status: json['batch_status'] as String? ?? 'harvested',
      stockingDate: _readProductionDate(json['stocking_date']),
      harvestDate: json['harvest_date'] == null
          ? null
          : _readProductionDate(json['harvest_date']),
      endedAt: json['ended_at'] == null
          ? null
          : _readProductionDate(json['ended_at']),
      initialCount: (json['initial_count'] as num?)?.toInt() ?? 0,
      harvestCount: (json['harvest_count'] as num?)?.toInt() ?? 0,
      totalMortality: (json['total_mortality'] as num?)?.toInt() ?? 0,
      harvestWeightGrams: (json['harvest_weight_grams'] as num?)?.toDouble(),
      initialAbw: initialAbw,
      initialAbl: initialAbl,
      // Read legacy snapshots for compatibility. TankService hydrates these
      // values from the latest sampling record whenever source records exist.
      finalAbw: (json['final_abw'] as num?)?.toDouble() ?? 0,
      finalAbl: (json['final_abl'] as num?)?.toDouble() ?? 0,
      sampleCount: sampleCount,
      initialTotalWeight: initialTotalWeight,
      initialTotalLength: initialTotalLength,
      archivedSampling: rawSampling,
      archivedMortality:
          safeMap(json['archived_mortality']) ??
          safeMap(json['archivedMortality']),
    );
  }

  /// Calendar days elapsed since stocking, recalculated whenever the model is
  /// read. Completed batches stop at their harvest date; active batches use
  /// today's local calendar date.
  int get daysInCulture {
    final end = harvestDate ?? endedAt ?? DateTime.now();
    final startDay = DateTime(
      stockingDate.year,
      stockingDate.month,
      stockingDate.day,
    );
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(startDay).inDays.clamp(0, 1000000).toInt();
  }

  CrayfishBatch withFinalSamplingAverages({
    required double abw,
    required double abl,
  }) => CrayfishBatch(
    batchId: batchId,
    status: status,
    stockingDate: stockingDate,
    harvestDate: harvestDate,
    endedAt: endedAt,
    initialCount: initialCount,
    harvestCount: harvestCount,
    totalMortality: totalMortality,
    harvestWeightGrams: harvestWeightGrams,
    initialAbw: initialAbw,
    initialAbl: initialAbl,
    finalAbw: abw,
    finalAbl: abl,
    sampleCount: sampleCount,
    initialTotalWeight: initialTotalWeight,
    initialTotalLength: initialTotalLength,
    archivedSampling: archivedSampling,
    archivedMortality: archivedMortality,
  );
}
