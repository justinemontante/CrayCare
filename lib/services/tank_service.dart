import 'package:flutter/foundation.dart';

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

  SamplingEntry({
    required this.date,
    required this.abw,
    required this.avgLength,
    required this.sampleSize,
    required this.totalWeight,
    required this.totalLength,
    required this.biomass,
    required this.liveCount,
  });
}

class TankActivity {
  final String action;
  final String date;
  final String time;
  final String type; // 'init', 'mortality', 'edit', 'sampling'

  TankActivity({
    required this.action,
    required this.date,
    required this.time,
    required this.type,
  });
}

class TankService extends ChangeNotifier {
  static final TankService instance = TankService._();
  TankService._();

  int _initialCount = 0;
  int _mortality = 0;
  bool _isInitialized = false;
  DateTime _stockingDate = DateTime.now();

  // Baseline Sampling Data
  int _sampleCount = 0;
  double _initialWeight = 0.0;
  double _initialLength = 0.0;

  final List<SamplingEntry> _samplingHistory = [];
  final List<TankActivity> _activities = [];

  // Track mortality entries for the graph in Trends tab
  List<double> _mortalityHistory = [];

  bool get isInitialized => _isInitialized;
  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get liveCount => _initialCount - _mortality;
  double get survivalRate =>
      _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;
  int get daysInCulture => DateTime.now().difference(_stockingDate).inDays;

  int get sampleCount => _sampleCount;
  double get initialWeight => _initialWeight;
  double get initialLength => _initialLength;

  List<SamplingEntry> get samplingHistory =>
      List.unmodifiable(_samplingHistory);
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);
  List<double> get mortalityHistory => List.unmodifiable(_mortalityHistory);

  GrowthStage get currentGrowthStage {
    final latest = _samplingHistory.isNotEmpty ? _samplingHistory.last : null;
    final abw = latest?.abw ?? _initialWeight;
    if (abw < 5) return GrowthStage.earlyJuvenile;
    if (abw < 15) return GrowthStage.advancedJuvenile;
    if (abw < 50) return GrowthStage.growOut;
    return GrowthStage.marketSize;
  }

  void addSamplingEntry(int count, double weight, double length) {
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
    _addActivity(
      'Recorded sampling: ${abw.toStringAsFixed(2)}g ABW',
      'sampling',
    );
    notifyListeners();
  }

  void updateInitialCount(int val) {
    _initialCount = val;
    _addActivity('Updated initial stocking count to $val', 'edit');
    notifyListeners();
  }

  void addMortality(int val, {DateTime? date}) {
    _mortality += val;
    _mortalityHistory.add(val.toDouble()); // Push new point for the graph!
    _addActivity(
      'Recorded mortality of $val crayfish (Total: $_mortality)',
      'mortality',
      customDate: date,
    );
    notifyListeners();
  }

  void updateStockingDate(DateTime date) {
    _stockingDate = date;
    final dateStr = '${date.month}/${date.day}/${date.year}';
    _addActivity('Updated stocking date to $dateStr', 'edit');
    notifyListeners();
  }

  void clearSession() {
    _initialCount = 0;
    _mortality = 0;
    _isInitialized = false;
    _stockingDate = DateTime.now();
    _sampleCount = 0;
    _initialWeight = 0.0;
    _initialLength = 0.0;
    _samplingHistory.clear();
    _activities.clear();
    _mortalityHistory.clear();
    notifyListeners();
  }

  void initializeGrowOut(
    int initial,
    int sampleCount,
    double totalWeight,
    double totalLength,
    DateTime date,
  ) {
    _initialCount = initial;
    _mortality = 0;
    _stockingDate = date;
    _sampleCount = sampleCount;
    // Computes average beautifully
    _initialWeight = sampleCount > 0 ? (totalWeight / sampleCount) : 0.0;
    _initialLength = sampleCount > 0 ? (totalLength / sampleCount) : 0.0;
    _isInitialized = true;

    _samplingHistory.clear();
    _activities.clear();
    _mortalityHistory = [0.0]; // Set base initial as zero mortalities

    _addActivity(
      'Initialized grow-out with $initial population',
      'init',
      customDate: date,
    );
    notifyListeners();
  }

  void _addActivity(String action, String type, {DateTime? customDate}) {
    final now = customDate ?? DateTime.now();
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

    _activities.add(
      TankActivity(action: action, date: dateStr, time: timeStr, type: type),
    );
  }
}
