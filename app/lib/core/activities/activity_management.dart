import 'package:scrcpy_connect/core/activities/models/activity.dart';

export 'package:scrcpy_connect/core/activities/models/activity.dart';

abstract interface class ActivityManagement {
  Future<ActivityCollection> readActivities({String? deviceId});
  Future<void> stopActivity(ActivityTarget target);
}
