import 'dart:async';

/// VM 服务失去回执时结束本次等待；停止轮询后仍须等检查任务收尾再恢复设备。
Future<T> driverRpc<T>(
  Future<T> request, {
  Duration timeout = const Duration(seconds: 5),
}) => request.timeout(timeout);

/// 顺序尝试全部恢复动作；收尾失败同时保留原始失败及其堆栈。
/// 每个动作负责限制自身等待，不能用外层超时丢弃仍在执行的恢复。
Future<void> withDriverCleanup(
  Future<void> Function() operation,
  Map<String, FutureOr<void> Function()> Function() steps,
) async {
  Object? primaryError;
  StackTrace? primaryStack;
  try {
    await operation();
  } catch (error, stack) {
    primaryError = error;
    primaryStack = stack;
  }
  final failures = <DriverCleanupFailure>[];
  for (final step in steps().entries) {
    try {
      await step.value();
    } catch (error, stack) {
      failures.add(DriverCleanupFailure(step.key, error, stack));
    }
  }
  if (failures.isNotEmpty) {
    Error.throwWithStackTrace(
      DriverCleanupException(primaryError, primaryStack, failures),
      primaryStack ?? failures.first.stack,
    );
  }
  if (primaryError != null) {
    Error.throwWithStackTrace(primaryError, primaryStack!);
  }
}

class DriverCleanupFailure {
  const DriverCleanupFailure(this.step, this.error, this.stack);

  final String step;
  final Object error;
  final StackTrace stack;
}

class DriverCleanupException implements Exception {
  DriverCleanupException(
    this.primaryError,
    this.primaryStack,
    List<DriverCleanupFailure> failures,
  ) : failures = List.unmodifiable(failures);

  final Object? primaryError;
  final StackTrace? primaryStack;
  final List<DriverCleanupFailure> failures;

  @override
  String toString() => [
    if (primaryError != null) 'Driver failed: $primaryError',
    for (final failure in failures)
      'Cleanup ${failure.step} failed: ${failure.error}',
  ].join('\n');
}
