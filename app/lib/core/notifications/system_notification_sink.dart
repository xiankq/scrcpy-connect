import 'models/system_notice.dart';

export 'models/system_notice.dart';

abstract interface class SystemNotificationSink {
  Stream<String> get activations;
  Future<void> initialize();
  Future<SystemNotificationStatus> status();
  Future<SystemNotificationStatus> requestPermission();
  Future<bool> openSettings();
  Future<void> show(SystemNotice notice);
  Future<void> cancel(int id);
}

class NoopSystemNotificationSink implements SystemNotificationSink {
  const NoopSystemNotificationSink();
  @override
  Stream<String> get activations => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<SystemNotificationStatus> status() async =>
      const SystemNotificationStatus();
  @override
  Future<SystemNotificationStatus> requestPermission() => status();
  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> show(SystemNotice notice) async {}
  @override
  Future<void> cancel(int id) async {}
}
