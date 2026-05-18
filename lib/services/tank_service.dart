import 'package:flutter/foundation.dart';

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
  TankService._() {
    _activities.add(TankActivity(
      action: 'Initialized grow-out with 68 population',
      date: 'May 12, 2026',
      time: '08:00 AM',
      type: 'init',
    ));
  }

  int _initialCount = 68;
  int _mortality = 5;
  DateTime _stockingDate = DateTime.now().subtract(const Duration(days: 45));
  
  // Baseline Sampling Data
  int _sampleCount = 30;
  double _initialWeight = 45.2;
  double _initialLength = 12.8;

  final List<SamplingEntry> _samplingHistory = [];
  final List<TankActivity> _activities = [];

  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get liveCount => _initialCount - _mortality;
  double get survivalRate => _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;
  int get daysInCulture => DateTime.now().difference(_stockingDate).inDays;
  
  int get sampleCount => _sampleCount;
  double get initialWeight => _initialWeight;
  double get initialLength => _initialLength;

  List<SamplingEntry> get samplingHistory => List.unmodifiable(_samplingHistory);
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);

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
    _addActivity('Recorded sampling: ${abw.toStringAsFixed(2)}g ABW', 'sampling');
    notifyListeners();
  }

  void updateInitialCount(int val) {
    _initialCount = val;
    _addActivity('Updated initial stocking count to $val', 'edit');
    notifyListeners();
  }

  void addMortality(int val, {DateTime? date}) {
    _mortality += val;
    _addActivity('Recorded mortality of $val crayfish (Total: $_mortality)', 'mortality', customDate: date);
    notifyListeners();
  }

  void updateStockingDate(DateTime date) {
    _stockingDate = date;
    final dateStr = '${date.month}/${date.day}/${date.year}';
    _addActivity('Updated stocking date to $dateStr', 'edit');
    notifyListeners();
  }

  void updateBaselineSampling({int? sampleCount, double? weight, double? length}) {
    if (sampleCount != null) _sampleCount = sampleCount;
    if (weight != null) _initialWeight = weight;
    if (length != null) _initialLength = length;
    _addActivity('Updated baseline sampling data', 'edit');
    notifyListeners();
  }

  void initializeGrowOut(int initial, int sampleCount, double weight, double length, DateTime date) {
    _initialCount = initial;
    _mortality = 0;
    _stockingDate = date;
    _sampleCount = sampleCount;
    _initialWeight = weight;
    _initialLength = length;
    
    _samplingHistory.clear();
    _activities.clear();
    _addActivity('Initialized grow-out with $initial population', 'init', customDate: date);
    notifyListeners();
  }

  void _addActivity(String action, String type, {DateTime? customDate}) {
    final now = customDate ?? DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    
    _activities.add(TankActivity(
      action: action,
      date: dateStr,
      time: timeStr,
      type: type,
    ));
  }
}
