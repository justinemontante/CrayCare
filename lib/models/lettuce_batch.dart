class LettuceGrowthEntry {
  final DateTime date;
  final double? plantHeightCm;
  final int? leafCount;
  final double? avgLeafSize;
  final String? color;
  final String notes;
  final String? batchId;

  LettuceGrowthEntry({
    required this.date,
    this.plantHeightCm,
    this.leafCount,
    this.avgLeafSize,
    this.color,
    this.notes = '',
    this.batchId,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.millisecondsSinceEpoch,
      if (plantHeightCm != null) 'plantHeightCm': plantHeightCm,
      if (leafCount != null) 'leafCount': leafCount,
      if (avgLeafSize != null) 'avgLeafSize': avgLeafSize,
      if (color != null) 'color': color,
      'notes': notes,
      if (batchId != null) 'batchId': batchId,
    };
  }

  factory LettuceGrowthEntry.fromJson(Map<String, dynamic> json) {
    return LettuceGrowthEntry(
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      plantHeightCm: (json['plantHeightCm'] as num?)?.toDouble(),
      leafCount: json['leafCount'] as int?,
      avgLeafSize: (json['avgLeafSize'] as num?)?.toDouble(),
      color: json['color'] as String?,
      notes: (json['notes'] as String?) ?? '',
      batchId: json['batchId'] as String?,
    );
  }
}

class LettuceSamplingEntry {
  final DateTime date;
  final int sampleSize;
  final double totalHeight;
  final int totalLeafCount;
  final double avgHeight;
  final double avgLeafCount;

  LettuceSamplingEntry({
    required this.date,
    required this.sampleSize,
    required this.totalHeight,
    required this.totalLeafCount,
    required this.avgHeight,
    required this.avgLeafCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.millisecondsSinceEpoch,
      'sampleSize': sampleSize,
      'totalHeight': totalHeight,
      'totalLeafCount': totalLeafCount,
      'avgHeight': avgHeight,
      'avgLeafCount': avgLeafCount,
    };
  }

  factory LettuceSamplingEntry.fromJson(Map<String, dynamic> json) {
    return LettuceSamplingEntry(
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      sampleSize: json['sampleSize'] as int,
      totalHeight: (json['totalHeight'] as num).toDouble(),
      totalLeafCount: json['totalLeafCount'] as int,
      avgHeight: (json['avgHeight'] as num).toDouble(),
      avgLeafCount: (json['avgLeafCount'] as num).toDouble(),
    );
  }
}

class LettuceMortalityRecord {
  final DateTime date;
  final int count;
  final String? batchId;

  LettuceMortalityRecord({
    required this.date,
    required this.count,
    this.batchId,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.millisecondsSinceEpoch,
      'count': count,
      if (batchId != null) 'batchId': batchId,
    };
  }

  factory LettuceMortalityRecord.fromJson(Map<String, dynamic> json) {
    return LettuceMortalityRecord(
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      count: json['count'] as int,
      batchId: json['batchId'] as String?,
    );
  }
}

class LettuceBatch {
  final String batchId;
  final String? batchNumber;
  final String status;
  final DateTime plantingDate;
  final int initialQuantity;
  final int currentQuantity;
  final int harvestedQuantity;
  final DateTime? harvestDate;
  final double? harvestWeightKg;
  final Map<String, dynamic>? archivedGrowth;
  final Map<String, dynamic>? archivedMortality;
  final int totalMortality;

  LettuceBatch({
    required this.batchId,
    this.batchNumber,
    this.status = 'active',
    required this.plantingDate,
    required this.initialQuantity,
    required this.currentQuantity,
    this.harvestedQuantity = 0,
    this.harvestDate,
    this.harvestWeightKg,
    this.archivedGrowth,
    this.archivedMortality,
    this.totalMortality = 0,
  });

  bool get isHarvested => status == 'harvested';

  double? get harvestWeightGrams =>
      harvestWeightKg != null ? harvestWeightKg! * 1000 : null;

  Map<String, dynamic> toJson() {
    return {
      'batchId': batchId,
      if (batchNumber != null) 'batchNumber': batchNumber,
      'status': status,
      'plantingDate': plantingDate.millisecondsSinceEpoch,
      'initialQuantity': initialQuantity,
      'currentQuantity': currentQuantity,
      'harvestedQuantity': harvestedQuantity,
      'harvestDate': harvestDate?.millisecondsSinceEpoch,
      'isHarvested': isHarvested,
      if (harvestWeightKg != null) 'harvestWeightKg': harvestWeightKg,
      if (archivedGrowth != null) 'archivedGrowth': archivedGrowth,
      if (archivedMortality != null) 'archivedMortality': archivedMortality,
      'totalMortality': totalMortality,
    };
  }

  factory LettuceBatch.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String?;
    final isHarvested = (json['isHarvested'] as bool?) ?? false;

    double? harvestWeightKg;
    if (json['harvestWeightKg'] != null) {
      harvestWeightKg = (json['harvestWeightKg'] as num).toDouble();
    } else if (json['harvestWeightGrams'] != null) {
      harvestWeightKg = (json['harvestWeightGrams'] as num).toDouble() / 1000;
    }

    return LettuceBatch(
      batchId: json['batchId'] as String,
      batchNumber: json['batchNumber'] as String?,
      status: status ?? (isHarvested ? 'harvested' : 'active'),
      plantingDate: DateTime.fromMillisecondsSinceEpoch(
          json['plantingDate'] as int),
      initialQuantity: json['initialQuantity'] as int,
      currentQuantity: json['currentQuantity'] as int,
      harvestedQuantity: (json['harvestedQuantity'] as int?) ?? 0,
      harvestDate: json['harvestDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['harvestDate'] as int)
          : null,
      harvestWeightKg: harvestWeightKg,
      archivedGrowth: json['archivedGrowth'] as Map<String, dynamic>?,
      archivedMortality: json['archivedMortality'] as Map<String, dynamic>?,
      totalMortality: (json['totalMortality'] as int?) ?? 0,
    );
  }
}

class LettuceHarvestRecord {
  final String id;
  final String batchId;
  final DateTime date;
  final int harvestedCount;
  final double totalWeightKg;
  final double avgWeightGrams;

  LettuceHarvestRecord({
    required this.id,
    required this.batchId,
    required this.date,
    required this.harvestedCount,
    required this.totalWeightKg,
    required this.avgWeightGrams,
  });

  Map<String, dynamic> toJson() => {
    'batchId': batchId,
    'date': date.millisecondsSinceEpoch,
    'harvestedCount': harvestedCount,
    'totalWeightKg': totalWeightKg,
    'avgWeightGrams': avgWeightGrams,
  };

  factory LettuceHarvestRecord.fromJson(String id, Map<String, dynamic> json) => LettuceHarvestRecord(
    id: id,
    batchId: json['batchId'] as String? ?? '',
    date: DateTime.fromMillisecondsSinceEpoch((json['date'] as num?)?.toInt() ?? 0),
    harvestedCount: (json['harvestedCount'] as num?)?.toInt() ?? 0,
    totalWeightKg: (json['totalWeightKg'] as num?)?.toDouble() ?? 0,
    avgWeightGrams: (json['avgWeightGrams'] as num?)?.toDouble() ?? 0,
  );
}


