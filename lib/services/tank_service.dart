import 'package:flutter/foundation.dart';

class TankService extends ChangeNotifier {
  static final TankService instance = TankService._();
  TankService._();

  int _initialCount = 68;
  int _mortality = 5;
  DateTime _stockingDate = DateTime.now().subtract(const Duration(days: 45));

  int get initialCount => _initialCount;
  int get mortality => _mortality;
  int get liveCount => _initialCount - _mortality;
  double get survivalRate => _initialCount == 0 ? 0 : (liveCount / _initialCount * 100);
  DateTime get stockingDate => _stockingDate;
  int get daysInCulture => DateTime.now().difference(_stockingDate).inDays;

  void updateInitialCount(int val) {
    _initialCount = val;
    notifyListeners();
  }

  void addMortality(int val) {
    _mortality += val;
    notifyListeners();
  }

  void updateStockingDate(DateTime date) {
    _stockingDate = date;
    notifyListeners();
  }
}
