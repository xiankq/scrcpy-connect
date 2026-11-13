enum SystemNotificationKind { notification, call }

const systemNotificationIdMin = 100000;
const systemNotificationIdMax = 199999;

class SystemNotificationStatus {
  const SystemNotificationStatus({
    this.supported = false,
    this.permissionGranted,
    this.notificationChannelEnabled,
    this.callChannelEnabled,
    this.canRequest = false,
    this.canOpenSettings = false,
    this.reason = '',
  });
  final bool supported;
  final bool? permissionGranted;
  final bool? notificationChannelEnabled;
  final bool? callChannelEnabled;
  final bool canRequest;
  final bool canOpenSettings;
  final String reason;
}

class SystemNotice {
  const SystemNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.payload,
  });
  final int id;
  final SystemNotificationKind kind;
  final String title;
  final String body;
  final String payload;
}
