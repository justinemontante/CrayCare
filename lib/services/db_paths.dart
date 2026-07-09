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

  static String lettuce(String uid) => 'production/$uid/lettuce';
  static DatabaseReference lettuceBatches(String uid) =>
      _ref('${lettuce(uid)}/batches');
  static DatabaseReference lettuceGrowth(String uid, {String? batchId}) =>
      batchId != null
          ? _ref('${lettuce(uid)}/growth/$batchId')
          : _ref('${lettuce(uid)}/growth');
  static DatabaseReference lettuceActivities(String uid) =>
      _ref('${lettuce(uid)}/activities');
  static DatabaseReference lettuceMortality(String uid) =>
      _ref('${lettuce(uid)}/mortality');
  static DatabaseReference lettuceMortalityForBatch(String uid, String batchId) =>
      _ref('${lettuce(uid)}/mortality/$batchId');
  static DatabaseReference lettuceSampling(String uid) =>
      _ref('${lettuce(uid)}/sampling');
  static DatabaseReference lettuceHarvests(String uid) =>
      _ref('${lettuce(uid)}/harvests');
  static DatabaseReference lettuceSamplingForBatch(String uid, String batchId) =>
      _ref('${lettuce(uid)}/sampling/$batchId');

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
