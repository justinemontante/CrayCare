import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

@pragma('vm:entry-point')
class ForegroundService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: foregroundServiceOnStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: 'craycare_background',
        initialNotificationTitle: 'CrayCare',
        initialNotificationContent: 'Monitoring active',
        foregroundServiceNotificationId: 999,
        foregroundServiceTypes: [AndroidForegroundType.specialUse],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: foregroundServiceOnStart,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    foregroundServiceOnStart(service);
  }
}

@pragma('vm:entry-point')
void foregroundServiceOnStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'CrayCare',
        content: 'Monitoring sensors...',
      );
    }
  });

  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}
