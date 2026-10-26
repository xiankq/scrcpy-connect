part of 'api.dart';

/// 探测实际经过的协议层；官方服务器响应不等于直接收到 adbd 分帧。
enum AdbOpenProbeLayer { directAdb, officialServer }

enum AdbOpenProbeOutcome {
  okay,
  rejected,
  timedOut,
  notWritten,
  localCapacity,
  cancelled,
  transportClosed,
  io,
  protocol,
}

/// 单次 OPEN 的执行事实；不是产品健康结论，也不保证本机关闭帧已经排空。
final class AdbOpenProbeFacts {
  const AdbOpenProbeFacts({
    required this.layer,
    required this.openWritten,
    required this.outcome,
    required this.inboundActivity,
  });
  final AdbOpenProbeLayer layer;

  /// directAdb 表示 OPEN 帧已写出，officialServer 表示服务请求已写给服务器；
  /// 后者不能作为服务器已把请求写到 adbd 的证明。
  final bool openWritten;
  final AdbOpenProbeOutcome outcome;

  /// 不透明入站活动标记，只能比较相等，不是时间戳或数据包数量。
  final String inboundActivity;
}

/// 可选的原生 OPEN 探测能力；不要求旧适配器伪造支持。
abstract interface class NativeAdbOpenProbeApi {
  Future<String> createOpenProbe(
    String connectionId,
    String service,
    int timeoutMs,
  );
  Future<AdbOpenProbeFacts> openProbeResult(String probeId);

  /// 取消并等待本次操作的本机流释放；失败保留原句柄，供同句柄重试。
  Future<void> closeOpenProbe(String probeId, int timeoutMs);
}

/// 创建期间已撤销交付，但精确探针回收尚未确认；调用方可保留 [probe] 单独重试。
/// [cause] 是原始关闭错误，不会替换为取消错误或关闭共享服务来掩盖。
final class AdbOpenProbeCleanupFailure implements Exception {
  const AdbOpenProbeCleanupFailure(this.probe, this.cause);
  final AdbOpenProbe probe;
  final Object cause;
  @override
  String toString() => 'AdbOpenProbeCleanupFailure(${probe.id}, $cause)';
}

/// 单次可取消的 OPEN；调用方必须显式关闭，不能用 [result] 终态代替回收确认。
final class AdbOpenProbe extends _AdbOperation {
  AdbOpenProbe._(this._api, this.id, super._owner) {
    result = Future.sync(() => _api.openProbeResult(id));
    // 调用方可以先关闭再读取结果；保留原 Future 的错误，同时避免迟到错误无人观察。
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final NativeAdbOpenProbeApi _api;
  final String id;
  late final Future<AdbOpenProbeFacts> result;
  Future<void>? _closing;
  bool _released = false;

  /// 只回收本次探针，不关闭共享 Client；关闭失败时保持原句柄并允许重试。
  @override
  Future<void> close({Duration timeout = const Duration(seconds: 7)}) {
    final timeoutMs = adbTimeoutMillis(timeout);
    if (_released) return Future.value();
    return _closing ??= _close(timeoutMs);
  }

  Future<void> _close(int timeoutMs) async {
    _unsubscribe?.call();
    _unsubscribe = null;
    try {
      await _api.closeOpenProbe(id, timeoutMs);
      _released = true;
      _onClosed();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}
