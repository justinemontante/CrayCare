import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final List<VoidCallback> _onConnectCallbacks = [];

  void addOnConnectCallback(VoidCallback callback) {
    _onConnectCallbacks.add(callback);
  }

  void removeOnConnectCallback(VoidCallback callback) {
    _onConnectCallbacks.remove(callback);
  }

  Future<void> init() async {
    _isOnline = await _checkConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) async {
        final wasOffline = !_isOnline;
        _isOnline = result != ConnectivityResult.none;
        notifyListeners();

        if (wasOffline && _isOnline) {
          debugPrint('[ConnectivityService] Internet restored — triggering refresh callbacks');
          for (final callback in List.of(_onConnectCallbacks)) {
            try {
              callback();
            } catch (e) {
              debugPrint('[ConnectivityService] Callback error: $e');
            }
          }
        }
      },
    );
  }

  Future<bool> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<bool> checkConnectivity() async {
    _isOnline = await _checkConnectivity();
    return _isOnline;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _onConnectCallbacks.clear();
    super.dispose();
  }
}
