import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'background_helper.dart';

const String _feedTaskName = 'com.craycare.feeding';

Future<void> initializeWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _feedTaskName,
    _feedTaskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: const Duration(minutes: 1),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
    ),
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundService] Task: $task');
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (task == _feedTaskName) {
        // The ESP32 is the single source of truth for executing stored feeding
        // schedules (including while the phone is offline). Do not enqueue a
        // second feed command here: that used to race the ESP-local scheduler
        // and could physically dispense twice. Background work is reminders only.
        await BackgroundHelper.showPendingNotifications();
        await BackgroundHelper.checkSamplingReminders();
      }
      return true;
    } catch (e) {
      debugPrint('[BackgroundService] Error in $task: $e');
      return false;
    }
  });
}
