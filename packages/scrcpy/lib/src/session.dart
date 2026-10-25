import 'dart:async';

import 'package:adb/adb.dart';

import 'control.dart';
import 'event_observer.dart';
import 'models.dart';
import 'api.dart';

/// 用注入的原生传输创建捕获；不拥有或关闭调用方的 ADB 连接。
final class ScrcpyClient {
  const ScrcpyClient(this.api, {this._nativeOwner});
  final Object? _nativeOwner;
  final NativeScrcpyApi api;

  Future<ScrcpySession> createSession(
    AdbDevice device, {
    ScrcpyOptions options = const ScrcpyOptions(),
    AdbCancellation? cancellation,
  }) async {
    _checkCancellation(cancellation);
    _checkDeviceOwner(device);
    final id = await api.createSession(
      connectionId: device.id,
      options: options,
    );
    final session = ScrcpySession._(api, id);
    if (cancellation?.isCancelled ?? false) {
      try {
        await session.close();
      } catch (error) {
        throw ScrcpyCreationCleanupFailure(session, error);
      }
      throw const ScrcpyException('cancelled');
    }
    return session;
  }

  /// 按当前连接权限排空既有捕获，供宿主重建后回收失去 Dart 所有者的来源。
  /// 不关闭 ADB 连接；并发新建的捕获需要由调用方另行管理准入。
  Future<void> drainConnection(AdbDevice device) async {
    _checkDeviceOwner(device);
    if (api case final NativeScrcpyConnectionApi native) {
      await native.drainConnection(device.id);
      return;
    }
    throw const ScrcpyException(
      'connection_recovery_unavailable',
      '注入的传输未提供连接级捕获排空能力。',
    );
  }

  /// 查询原生 sink 接纳事实；连接认领后须传入新操作句柄。
  Future<ScrcpySourceStatus> sourceStatus(
    AdbDevice device, {
    required String captureRef,
    required String sourceId,
  }) async {
    _checkDeviceOwner(device);
    if (api case final NativeScrcpySourceStatusApi native) {
      final status = await native.sourceStatus(
        connectionId: device.id,
        captureRef: captureRef,
        sourceId: sourceId,
      );
      if (status.captureRef != captureRef || status.sourceId != sourceId) {
        throw const ScrcpyException('stale_source', '来源回执与请求身份不一致。');
      }
      return status;
    }
    throw const ScrcpyException(
      'source_status_unavailable',
      '注入的传输未提供原生来源状态事实。',
    );
  }

  void _checkDeviceOwner(AdbDevice device) {
    if (_nativeOwner != null && !identical(device.nativeOwner, _nativeOwner)) {
      throw const ScrcpyException('foreign_connection', '设备连接属于另一原生宿主。');
    }
  }

  /// 附着宿主已启动的精确捕获；关闭此对象仅释放观察，停止权仍属于原所有者。
  Future<ScrcpySession> attach(String captureRef, {int generation = 1}) async {
    final info = await api.inspect(captureRef, generation: generation);
    if (info.id != captureRef) throw const ScrcpyException('stale_capture');
    return ScrcpySession._(api, captureRef, ownsCapture: false, info: info);
  }
}

/// 登记取消后的清理失败；调用者仍拥有 [session]，应重试 close 以释放唯一捕获句柄。
final class ScrcpyCreationCleanupFailure implements Exception {
  const ScrcpyCreationCleanupFailure(this.session, this.cause);
  final ScrcpySession session;
  final Object cause;

  @override
  String toString() => 'ScrcpyCreationCleanupFailure(${session.id}, $cause)';
}

/// 单次捕获所有者。启动与关闭可以并发，关闭后永不重新准入控制或启动。
final class ScrcpySession {
  ScrcpySession._(this._api, this.id, {this._ownsCapture = true, this._info});
  final NativeScrcpyApi _api;
  final String id;
  final bool _ownsCapture;
  ScrcpySessionInfo? _info;
  ScrcpySessionInfo? get info => _info;
  bool _closed = false;
  bool _captureReleased = false;
  Future<void>? _closing;
  Future<ScrcpySessionInfo>? _starting;
  Future<ScrcpySessionInfo>? _controlStarting;
  final _observers = <ScrcpyEventObserver>{};

  /// 每次获取返回独立的单订阅观察流；失败关闭权保留到实际释放确认。
  Stream<ScrcpyEvent> get events {
    _checkOpen();
    final observer = _api.openEvents(id);
    _observers.add(observer);
    unawaited(
      observer.whenClosed.then((_) {
        _observers.remove(observer);
      }),
    );
    return observer.stream;
  }

  Future<ScrcpySessionInfo> start({AdbCancellation? cancellation}) {
    _checkOpen();
    _checkCancellation(cancellation);
    if (!_ownsCapture) return Future.value(_info!);
    final starting = _starting ??= _start();
    return _withCancellation(starting, cancellation);
  }

  /// 接纳控制通道后返回，视频可尚无首帧；此后可发送 START_APP。
  Future<ScrcpySessionInfo> startControl({AdbCancellation? cancellation}) {
    _checkOpen();
    _checkCancellation(cancellation);
    if (!_ownsCapture) return Future.value(_info!);
    final native = _staged();
    return _withCancellation(
      _controlStarting ??= _accept(Future.sync(() => native.startControl(id))),
      cancellation,
    );
  }

  /// 等待同一捕获的媒体格式和首关键帧，不占用控制调用的执行通道。
  Future<ScrcpySessionInfo> awaitMedia({
    int generation = 1,
    AdbCancellation? cancellation,
  }) {
    _checkOpen();
    _checkCancellation(cancellation);
    final native = _staged();
    return _withCancellation(() async {
      if (_ownsCapture) await startControl();
      return _accept(
        Future.sync(() => native.awaitMedia(id, generation: generation)),
      );
    }(), cancellation);
  }

  Future<ScrcpyProcessInfo> processInfo() {
    _checkOpen();
    return _staged().processInfo(id);
  }

  NativeScrcpyStagedApi _staged() {
    if (_api case final NativeScrcpyStagedApi native) return native;
    throw const ScrcpyException('staged_start_unavailable');
  }

  Future<ScrcpySessionInfo> _withCancellation(
    Future<ScrcpySessionInfo> starting,
    AdbCancellation? cancellation,
  ) {
    if (cancellation == null) return starting;
    final result = Completer<ScrcpySessionInfo>();
    final remove = cancellation.onCancel(() {
      if (result.isCompleted) return;
      final closing = close();
      result.completeError(const ScrcpyException('cancelled'));
      unawaited(
        closing.catchError((Object _) {
          // 原生回收失败仍由同一 session 保留，调用方可显式重试 close。
        }),
      );
    });
    starting.then(
      (info) {
        remove();
        if (!result.isCompleted) result.complete(info);
      },
      onError: (Object error, StackTrace stack) {
        remove();
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }

  Future<ScrcpySessionInfo> _start() async {
    if (_api is NativeScrcpyStagedApi) {
      await startControl();
      return awaitMedia();
    }
    return _accept(Future.sync(() => _api.startSession(id)));
  }

  Future<ScrcpySessionInfo> _accept(Future<ScrcpySessionInfo> operation) async {
    try {
      final result = await operation;
      _checkOpen();
      if (result.id != id) throw const ScrcpyException('stale_capture');
      _info = result;
      return result;
    } catch (_) {
      // 原生启动失败仍可能持有本机登记，关闭失败交由调用方重试。
      if (!_closed) {
        try {
          await close();
        } catch (_) {
          /* 保留原始启动异常。 */
        }
      }
      rethrow;
    }
  }

  Future<ScrcpyControlReceipt> sendControl(ScrcpyControlMessage message) {
    _checkOpen();
    return _api.sendControl(id, message);
  }

  /// 立即关闭准入，再等待本机回收与受监督主进程退出；失败保留同一捕获重试。
  /// 观察者附着仅释放自身观察，不取得主进程停止或恢复设置的权限。
  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      // 原生停止须在首个等待点之前发出；观察者清理失败也不能阻止撤销捕获。
      // 捕获与观察者分别确认释放，重试观察者时不能再次停止已移除登记的捕获。
      final stopping = _ownsCapture && !_captureReleased
          ? Future<void>.sync(() => _api.stopSession(id)).then<void>((_) {
              _captureReleased = true;
            })
          : Future<void>.value();
      final cancelling = [
        for (final observer in _observers.toList()) observer.close(),
      ];
      await Future.wait([stopping, ...cancelling]);
      _observers.clear();
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }

  void _checkOpen() {
    if (_closed) throw const ScrcpyException('closed');
  }
}

void _checkCancellation(AdbCancellation? cancellation) {
  if (cancellation?.isCancelled ?? false) {
    throw const ScrcpyException('cancelled');
  }
}
