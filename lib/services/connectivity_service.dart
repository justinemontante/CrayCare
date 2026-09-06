import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  Timer? _verificationTimer;
  bool _verificationInProgress = false;
  bool _initialized = false;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final List<VoidCallback> _onConnectCallbacks = [];

  void addOnConnectCallback(VoidCallback callback) {
    if (!_onConnectCallbacks.contains(callback)) {
      _onConnectCallbacks.add(callback);
    }
  }

  void removeOnConnectCallback(VoidCallback callback) {
    _onConnectCallbacks.remove(callback);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _isOnline = await _checkConnectivity();
      _subscription = _connectivity.onConnectivityChanged.listen(
        (ConnectivityResult result) async {
          await _refreshStatus(networkResult: result);
        },
      );

      // A Wi-Fi/mobile connection can remain enabled even after its internet
      // access is lost (for example, when mobile data has no remaining load).
      // Recheck periodically while the app is running so that state is detected.
      _verificationTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(_refreshStatus()),
      );
    } catch (_) {
      // Initialization did not complete; allow a later retry instead of
      // permanently leaving the singleton marked initialized.
      _initialized = false;
      rethrow;
    }
  }

  Future<bool> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (result == ConnectivityResult.none) return false;
    return _hasInternetAccess();
  }

  Future<bool> _hasInternetAccess() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      return response.statusCode == HttpStatus.noContent ||
          (response.statusCode >= 200 && response.statusCode < 400);
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _refreshStatus({ConnectivityResult? networkResult}) async {
    if (_verificationInProgress) return;
    _verificationInProgress = true;
    try {
      final hasNetwork = networkResult != null
          ? networkResult != ConnectivityResult.none
          : await _connectivity.checkConnectivity() != ConnectivityResult.none;
      final isOnline = hasNetwork && await _hasInternetAccess();
      if (isOnline == _isOnline) return;

      final wasOffline = !_isOnline;
      _isOnline = isOnline;
      notifyListeners();

      if (wasOffline && isOnline) {
        debugPrint(
          '[ConnectivityService] Internet restored — triggering refresh callbacks',
        );
        for (final callback in List.of(_onConnectCallbacks)) {
          try {
            callback();
          } catch (e) {
            debugPrint('[ConnectivityService] Callback error: $e');
          }
        }
      }
    } finally {
      _verificationInProgress = false;
    }
  }

  Future<bool> checkConnectivity() async {
    await _refreshStatus();
    return _isOnline;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
    _verificationInProgress = false;
    _initialized = false;
    _onConnectCallbacks.clear();
    super.dispose();
  }
}
