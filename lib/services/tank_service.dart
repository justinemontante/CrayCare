import 'package:flutter/foundation.dart';

class TankActivity {
  final String action;
  final String date;
  final String time;
  final String type; // 'init', 'mortality', 'edit'

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
    // Add some initial history
    _activities.add(TankActivity(
      action: 'Initialized grow-out with 68 population',
      date: 'May 12, 2026',
      time: '08:00 AM',
      type: 'init',
    ));
    _activities.add(TankActivity(
      action: 'Recorded mortality of 2 crayfish',
      date: 'May 15, 2026',
      time: '02:30 PM',
      type: 'mortality',
    ));
    _activities.add(TankActivity(
      action: 'Recorded mortality of 3 crayfish',
      date: 'May 17, 2026',
      time: '09:15 AM',
      type: 'mortality',
    ));
  }

  int _initialCount = 68;
  int _mortality = 5;
  DateTime _stockingDate = DateTime.now().subtract(const Duration(days: 45));
  final List<TankActivity> _activities = [];

  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get liveCount => _initialCount - _mortality;
  double get survivalRate => _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;
  int get daysInCulture => DateTime.now().difference(_stockingDate).inDays;
  List<TankActivity> get activities => List.unmodifiable(_activities.reversed);

  void updateInitialCount(int val) {
    _initialCount = val;
    _addActivity('Updated initial stocking count to $val', 'edit');
    notifyListeners();
  }

  void addMortality(int val) {
    _mortality += val;
    _addActivity('Recorded mortality of $val crayfish (Total: $_mortality)', 'mortality');
    notifyListeners();
  }

  void updateStockingDate(DateTime date) {
    _stockingDate = date;
    final dateStr = '${date.month}/${date.day}/${date.year}';
    _addActivity('Updated stocking date to $dateStr', 'edit');
    notifyListeners();
  }

  void initializeGrowOut(int initial, int sampleCount, double weight, double length, DateTime date) {
    _initialCount = initial;
    _mortality = 0;
    _stockingDate = date;
    _activities.clear();
    _addActivity('Initialized grow-out with $initial population', 'init');
    notifyListeners();
  }

  void _addActivity(String action, String type) {
    final now = DateTime.now();
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
