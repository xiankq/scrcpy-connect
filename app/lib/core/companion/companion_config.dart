import 'package:adb/adb.dart';

/// 调用方明确选定的执行期限与资源边界，不包含功能默认值或观察策略。
final class CompanionConfig {
  const CompanionConfig({
    required this.startupTimeout,
    required this.requestTimeout,
    required this.cleanupTimeout,
    required this.sessionTimeout,
    this.maximumMessageBytes = 1024 * 1024,
    this.maximumPendingRequests = 32,
    this.maximumQueuedEvents = 32,
  });
  final Duration startupTimeout, requestTimeout, cleanupTimeout, sessionTimeout;
  final int maximumMessageBytes, maximumPendingRequests, maximumQueuedEvents;
  void validate() {
    for (final duration in [
      startupTimeout,
      requestTimeout,
      cleanupTimeout,
      sessionTimeout,
    ]) {
      adbTimeoutMillis(duration);
    }
    if (maximumMessageBytes <= 0 ||
        maximumMessageBytes > 1024 * 1024 ||
        maximumPendingRequests <= 0 ||
        maximumPendingRequests > 32 ||
        maximumQueuedEvents <= 0 ||
        maximumQueuedEvents > 1024) {
      throw ArgumentError('互联服务容量超出协议边界。');
    }
  }
}
