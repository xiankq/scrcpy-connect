/// 应用控制窗口的执行期限；超时撤销精确捕获，仍等待实际执行和回收结束。
final class SessionPolicy {
  const SessionPolicy({
    this.startupTimeout = const Duration(seconds: 20),
    this.controlTimeout = const Duration(seconds: 10),
    this.shellTimeout = const Duration(seconds: 15),
    this.qualityHandoffTimeout = const Duration(seconds: 30),
    this.qualityQueueTimeout = const Duration(seconds: 30),
    this.displayIdentityTimeout = const Duration(seconds: 10),
  });
  final Duration startupTimeout;
  final Duration controlTimeout;
  final Duration shellTimeout;
  final Duration qualityHandoffTimeout;
  final Duration qualityQueueTimeout;
  final Duration displayIdentityTimeout;

  void validate() {
    for (final duration in [
      startupTimeout,
      controlTimeout,
      shellTimeout,
      qualityHandoffTimeout,
      qualityQueueTimeout,
      displayIdentityTimeout,
    ]) {
      if (duration <= Duration.zero || duration > const Duration(minutes: 5)) {
        throw ArgumentError.value(duration, 'duration', '会话期限须为正数且不超过五分钟');
      }
    }
  }
}
