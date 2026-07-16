class CrayfishHarvestRecord {
  final String id;
  final String batchId;
  final DateTime date;
  final int harvestedCount;
  final double totalWeightKg;
  final double abwGrams;
  final double survivalRate;

  CrayfishHarvestRecord({
    required this.id,
    required this.batchId,
    required this.date,
    required this.harvestedCount,
    required this.totalWeightKg,
    required this.abwGrams,
    required this.survivalRate,
  });

  Map<String, dynamic> toJson() => {
    'batchId': batchId,
    'date': date.millisecondsSinceEpoch,
    'harvestedCount': harvestedCount,
    'totalWeightKg': totalWeightKg,
    'abwGrams': abwGrams,
    'survivalRate': survivalRate,
  };

  factory CrayfishHarvestRecord.fromJson(String id, Map<String, dynamic> json) => CrayfishHarvestRecord(
    id: id,
    batchId: json['batchId'] as String? ?? '',
    date: DateTime.fromMillisecondsSinceEpoch((json['date'] as num?)?.toInt() ?? 0),
    harvestedCount: (json['harvestedCount'] as num?)?.toInt() ?? 0,
    totalWeightKg: (json['totalWeightKg'] as num?)?.toDouble() ?? 0,
    abwGrams: (json['abwGrams'] as num?)?.toDouble() ?? 0,
    survivalRate: (json['survivalRate'] as num?)?.toDouble() ?? 0,
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
    'batchId': batchId,
    'status': status,
    'stockingDate': stockingDate.millisecondsSinceEpoch,
    'harvestDate': harvestDate?.millisecondsSinceEpoch,
    'initialCount': initialCount,
    'harvestCount': harvestCount,
    'totalMortality': totalMortality,
    'harvestWeightGrams': harvestWeightGrams,
    'initialAbw': initialAbw,
    'initialAbl': initialAbl,
    'finalAbw': finalAbw,
    'finalAbl': finalAbl,
    'daysInCulture': daysInCulture,
    'sampleCount': sampleCount,
    'initialTotalWeight': initialTotalWeight,
    'initialTotalLength': initialTotalLength,
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
    final initialAbw = (json['initialAbw'] as num?)?.toDouble() ?? 0.0;
    final initialAbl = (json['initialAbl'] as num?)?.toDouble() ?? 0.0;

    int fallbackSampleCount = 0;
    if (rawSampling != null && rawSampling.isNotEmpty) {
      final sortedEntries = rawSampling.values.map((v) {
        if (v is Map) {
          return v.map<String, dynamic>((k, val) => MapEntry(k.toString(), val));
        }
        return <String, dynamic>{};
      }).toList()..sort((a, b) {
        final da = a['date'] as num? ?? 0;
        final db = b['date'] as num? ?? 0;
        return da.compareTo(db);
      });
      if (sortedEntries.isNotEmpty) {
        fallbackSampleCount = (sortedEntries.first['sampleSize'] as num?)?.toInt() ?? 0;
      }
    }

    final sampleCount = (json['sampleCount'] as num?)?.toInt() ?? fallbackSampleCount;
    final initialTotalWeight = (json['initialTotalWeight'] as num?)?.toDouble() ?? (initialAbw * sampleCount);
    final initialTotalLength = (json['initialTotalLength'] as num?)?.toDouble() ?? (initialAbl * sampleCount);

    return CrayfishBatch(
      batchId: json['batchId'] as String? ?? 'Unknown',
      status: json['status'] as String? ?? 'harvested',
      stockingDate: DateTime.fromMillisecondsSinceEpoch(
        (json['stockingDate'] as num?)?.toInt() ?? 0,
      ),
      harvestDate: json['harvestDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['harvestDate'] as num).toInt())
          : null,
      initialCount: (json['initialCount'] as num?)?.toInt() ?? 0,
      harvestCount: (json['harvestCount'] as num?)?.toInt() ?? 0,
      totalMortality: (json['totalMortality'] as num?)?.toInt() ?? 0,
      harvestWeightGrams: (json['harvestWeightGrams'] as num?)?.toDouble(),
      initialAbw: initialAbw,
      initialAbl: initialAbl,
      finalAbw: (json['finalAbw'] as num?)?.toDouble() ?? 0,
      finalAbl: (json['finalAbl'] as num?)?.toDouble() ?? 0,
      daysInCulture: (json['daysInCulture'] as num?)?.toInt() ?? 0,
      sampleCount: sampleCount,
      initialTotalWeight: initialTotalWeight,
      initialTotalLength: initialTotalLength,
      archivedSampling: rawSampling,
      archivedMortality: safeMap(json['archivedMortality']),
    );
  }
}
