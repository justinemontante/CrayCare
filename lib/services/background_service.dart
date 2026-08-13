import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

const String _legacyTaskName = 'com.craycare.feeding';

/// Reminder delivery is now server-owned (Cloud Functions + FCM), while the
/// ESP32 executes feeding schedules locally. Cancel the old periodic Android
/// task so upgraded installations do not keep producing duplicate reminders or
/// enqueueing duplicate feed work.
Future<void> initializeWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().cancelByUniqueName(_legacyTaskName);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundService] Ignoring retired task: $task');
    return true;
  });
}
