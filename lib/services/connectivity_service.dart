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
  bool _verificationQueued = false;
  Completer<void>? _verificationCompleter;
  bool _initialized = false;
  bool _initialConnectivityCheckComplete = false;

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  bool get hasCompletedInitialConnectivityCheck =>
      _initialConnectivityCheckComplete;

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
      _initialConnectivityCheckComplete = true;
      _subscription = _connectivity.onConnectivityChanged.listen((_) async {
        await _refreshStatus();
      });

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
      _initialConnectivityCheckComplete = false;
      rethrow;
    }
  }

  Future<bool> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    if (result == ConnectivityResult.none) return false;
    if (await _hasInternetAccess()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (await _connectivity.checkConnectivity() == ConnectivityResult.none) {
      return false;
    }
    return _hasInternetAccess();
  }

  Future<bool> _hasInternetAccess() async {
    // Some networks block Google's connectivity-check host while allowing
    // Firebase traffic. Probe both paths in parallel and consider the device
    // online when either endpoint responds. A captive portal's HTTP 200 page
    // is not accepted as a successful Google 204 response.
    final results = await Future.wait([
      _probeInternetEndpoint(
        Uri.parse('https://clients3.google.com/generate_204'),
        acceptResponse: (status) => status == HttpStatus.noContent,
      ),
      _probeInternetEndpoint(
        Uri.parse('https://firestore.googleapis.com/'),
        // The API root normally returns 404 without a resource path. That is
        // still proof that the app can reach Firebase over the internet.
        // Avoid treating a captive portal's 200/redirect page as online.
        acceptResponse: (status) => status >= 400 && status < 600,
      ),
    ]);
    return results.any((reachable) => reachable);
  }

  Future<bool> _probeInternetEndpoint(
    Uri uri, {
    required bool Function(int statusCode) acceptResponse,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>();
      return acceptResponse(response.statusCode);
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _refreshStatus() async {
    if (_verificationInProgress) {
      // Don't drop a resume check or a newer network event while a previous
      // probe is still running. The queued pass re-reads the current route.
      _verificationQueued = true;
      await _verificationCompleter?.future;
      return;
    }
    _verificationInProgress = true;
    final completer = Completer<void>();
    _verificationCompleter = completer;
    try {
      do {
        _verificationQueued = false;
        // Read the current route instead of trusting a potentially stale
        // stream event (for example, one emitted during device wake-up).
        final hasNetwork =
            await _connectivity.checkConnectivity() != ConnectivityResult.none;
        var isOnline = hasNetwork && await _hasInternetAccess();
        // Mobile/Wi-Fi can briefly report a route before internet access is
        // ready again after the phone wakes. Confirm a failed probe once before
        // exposing an offline state; a successful probe still returns at once.
        if (!isOnline) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final stillHasNetwork =
              await _connectivity.checkConnectivity() !=
              ConnectivityResult.none;
          if (stillHasNetwork) isOnline = await _hasInternetAccess();
        }
        if (isOnline != _isOnline) {
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
        }
      } while (_verificationQueued);
    } finally {
      _verificationInProgress = false;
      if (identical(_verificationCompleter, completer)) {
        _verificationCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
      if (_verificationQueued) unawaited(_refreshStatus());
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
    _verificationQueued = false;
    _verificationCompleter = null;
    _initialized = false;
    _initialConnectivityCheckComplete = false;
    _onConnectCallbacks.clear();
    super.dispose();
  }
}
