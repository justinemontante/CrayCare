class CrayfishHarvestRecord {
  final String id;
  final String batchId;
  final DateTime date;
  final int harvestedCount;
  final double totalWeightKg;
  final double abwGrams;

  CrayfishHarvestRecord({
    required this.id,
    required this.batchId,
    required this.date,
    required this.harvestedCount,
    required this.totalWeightKg,
    required this.abwGrams,
  });

  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'harvest_date': date.millisecondsSinceEpoch,
    'harvest_count': harvestedCount,
    'total_weight_kg': totalWeightKg,
    'abw_grams': abwGrams,
  };

  factory CrayfishHarvestRecord.fromJson(String id, Map<String, dynamic> json) => CrayfishHarvestRecord(
    id: id,
    batchId: json['batch_id'] as String? ?? '',
    date: DateTime.fromMillisecondsSinceEpoch((json['harvest_date'] as num?)?.toInt() ?? 0),
    harvestedCount: (json['harvest_count'] as num?)?.toInt() ?? 0,
    totalWeightKg: (json['total_weight_kg'] as num?)?.toDouble() ?? 0,
    abwGrams: (json['abw_grams'] as num?)?.toDouble() ?? 0,
  );
}

class CrayfishBatch {
  final String batchId;
  final String status;
  final DateTime stockingDate;
  final DateTime? harvestDate;
  final int initialCount;
  final int harvestCount;
  final int totalMortality;
  final double? harvestWeightGrams;
  final double initialAbw;
  final double initialAbl;
  final double finalAbw;
  final double finalAbl;
  final int daysInCulture;
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
    this.initialCount = 0,
    this.harvestCount = 0,
    this.totalMortality = 0,
    this.harvestWeightGrams,
    this.initialAbw = 0,
    this.initialAbl = 0,
    this.finalAbw = 0,
    this.finalAbl = 0,
    this.daysInCulture = 0,
    this.sampleCount = 0,
    this.initialTotalWeight = 0,
    this.initialTotalLength = 0,
    this.archivedSampling,
    this.archivedMortality,
  });

  Map<String, dynamic> toJson() => {
    'batch_id': batchId,
    'batch_status': status,
    'stocking_date': stockingDate.millisecondsSinceEpoch,
    'harvest_date': harvestDate?.millisecondsSinceEpoch,
    'initial_count': initialCount,
    'harvest_count': harvestCount,
    'total_mortality': totalMortality,
    'harvest_weight_grams': harvestWeightGrams,
    'initial_abw': initialAbw,
    'initial_abl': initialAbl,
    'final_abw': finalAbw,
    'final_abl': finalAbl,
    'days_in_culture': daysInCulture,
    'sample_count': sampleCount,
    'initial_total_weight': initialTotalWeight,
    'initial_total_length': initialTotalLength,
    if (archivedSampling != null) 'archivedSampling': archivedSampling,
    if (archivedMortality != null) 'archivedMortality': archivedMortality,
  };

  factory CrayfishBatch.fromJson(Map<String, dynamic> json) {
    // Firebase nested maps come as Map<Object?, Object?>, which can't
    // be directly cast to Map<String, dynamic> — convert safely here.
    Map<String, dynamic>? safeMap(dynamic v) {
      if (v is Map) return v.map<String, dynamic>((k, v) => MapEntry('$k', v));
      return null;
    }
    final rawSampling = safeMap(json['archivedSampling']);
    final initialAbw = (json['initial_abw'] as num?)?.toDouble() ?? 0.0;
    final initialAbl = (json['initial_abl'] as num?)?.toDouble() ?? 0.0;

    int fallbackSampleCount = 0;
    if (rawSampling != null && rawSampling.isNotEmpty) {
      final sortedEntries = rawSampling.values.map((v) {
        if (v is Map) {
          return v.map<String, dynamic>((k, val) => MapEntry(k.toString(), val));
        }
        return <String, dynamic>{};
      }).toList()..sort((a, b) {
        final da = a['sampling_date'] as num? ?? 0;
        final db = b['sampling_date'] as num? ?? 0;
        return da.compareTo(db);
      });
      if (sortedEntries.isNotEmpty) {
        fallbackSampleCount = (sortedEntries.first['sample_size'] as num?)?.toInt() ?? 0;
      }
    }

    final sampleCount = (json['sample_count'] as num?)?.toInt() ?? fallbackSampleCount;
    final initialTotalWeight = (json['initial_total_weight'] as num?)?.toDouble() ?? (initialAbw * sampleCount);
    final initialTotalLength = (json['initial_total_length'] as num?)?.toDouble() ?? (initialAbl * sampleCount);

    return CrayfishBatch(
      batchId: json['batch_id'] as String? ?? 'Unknown',
      status: json['batch_status'] as String? ?? 'harvested',
      stockingDate: DateTime.fromMillisecondsSinceEpoch(
        (json['stocking_date'] as num?)?.toInt() ?? 0,
      ),
      harvestDate: json['harvest_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['harvest_date'] as num).toInt())
          : null,
      initialCount: (json['initial_count'] as num?)?.toInt() ?? 0,
      harvestCount: (json['harvest_count'] as num?)?.toInt() ?? 0,
      totalMortality: (json['total_mortality'] as num?)?.toInt() ?? 0,
      harvestWeightGrams: (json['harvest_weight_grams'] as num?)?.toDouble(),
      initialAbw: initialAbw,
      initialAbl: initialAbl,
      finalAbw: (json['final_abw'] as num?)?.toDouble() ?? 0,
      finalAbl: (json['final_abl'] as num?)?.toDouble() ?? 0,
      daysInCulture: (json['days_in_culture'] as num?)?.toInt() ?? 0,
      sampleCount: sampleCount,
      initialTotalWeight: initialTotalWeight,
      initialTotalLength: initialTotalLength,
      archivedSampling: rawSampling,
      archivedMortality: safeMap(json['archivedMortality']),
    );
  }
}
