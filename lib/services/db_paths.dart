import 'package:firebase_database/firebase_database.dart';

class DbPaths {
  static DatabaseReference _ref(String path) =>
      FirebaseDatabase.instance.ref(path);

  static String prod(String uid) => 'production/$uid';

  static String crayfish(String uid) => 'production/$uid/crayfish';
  static DatabaseReference crayfishConfig(String uid) =>
      _ref('${crayfish(uid)}/config');
  static DatabaseReference crayfishBatches(String uid) =>
      _ref('${crayfish(uid)}/batches');
  static DatabaseReference crayfishSampling(String uid) =>
      _ref('${crayfish(uid)}/sampling');
  static DatabaseReference crayfishMortality(String uid) =>
      _ref('${crayfish(uid)}/mortality');
  static DatabaseReference crayfishActivities(String uid) =>
      _ref('${crayfish(uid)}/activities');
  static DatabaseReference crayfishHarvests(String uid) =>
      _ref('${crayfish(uid)}/harvests');

  static DatabaseReference userProfile(String uid) =>
      _ref('users/$uid/profile');
  static DatabaseReference userNotifications(String uid) =>
      _ref('users/$uid/notifications');
  static DatabaseReference userNotifPrefs(String uid) =>
      _ref('users/$uid/notifPrefs');
  static DatabaseReference userNotifMarkers(String uid) =>
      _ref('users/$uid/notifications/markers');
  static DatabaseReference userGrowthStage(String uid) =>
      _ref('users/$uid/growth_stage');

  static DatabaseReference sensorLatest() =>
      _ref('sensor_readings/latest');
  static DatabaseReference sensorHistory() =>
      _ref('sensor_readings/history');
  static DatabaseReference sensorConfig() =>
      _ref('sensor_readings/config');

  static DatabaseReference feederSchedules() =>
      _ref('feeder/schedules');
  static DatabaseReference feederLogs() =>
      _ref('feeder/logs');
  static DatabaseReference feederCommands() =>
      _ref('feeder/commands');
  static DatabaseReference feederStatus() =>
      _ref('feeder/status');
  static DatabaseReference feederDispatched(String dateKey, String scheduleKey) =>
      _ref('feeder/dispatched/$dateKey/$scheduleKey');

  static DatabaseReference deviceModes() =>
      _ref('devices/modes');
  static DatabaseReference deviceLogs(String deviceId) =>
      _ref('devices/logs/$deviceId');
}
