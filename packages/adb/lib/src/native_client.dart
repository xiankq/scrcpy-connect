import 'dart:async';
import 'dart:io';

import 'api.dart';

/// 单次连接尝试的本机资源责任，不拥有共享客户端或已经交付的连接。
/// 成功后原始平台 USB 句柄须随连接一起移交，保持到该连接实际断开；
/// 未成功交付时则必须保留到 [close] 确认本次清理完成。
final class NativeAdbConnectionAttempt {
  NativeAdbConnectionAttempt._(this._client);
  final NativeAdbClient _client;
  final _stop = AdbCancellation();
  final _settled = Completer<void>();
  String? _handshakeId, _allocatedId;
  bool _delivered = false;
  Future<void>? _closing;

  /// 成功后连接的关闭责任交给调用方；尝试句柄此后不能关闭该连接。
  Future<AdbDevice> get result => _result;
  late final Future<AdbDevice> _result;

  void _start(
    Future<AdbDevice> Function() action,
    AdbCancellation? cancellation,
  ) {
    final unwatch = cancellation?.onCancel(_stop.cancel);
    _result = Future<AdbDevice>.sync(action);
    // 即使调用方先关闭而未读取 result，也保留实际结果并接收失败，避免遗失清理责任。
    unawaited(
      result.then<void>(
        (_) {
          unwatch?.call();
          _settled.complete();
        },
        onError: (Object _, StackTrace _) {
          unwatch?.call();
          _settled.complete();
        },
      ),
    );
  }

  /// 调用即取消本次尝试，等待迟到登记退出后精确回收；失败保留同一责任，可重试。
  /// 已成功交付的连接仍由接收方持有，本方法不替代其 disconnect。
  Future<void> close() {
    _stop.cancel();
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await _settled.future;
      Object? failure;
      StackTrace? trace;
      Future<void> release(Future<void> Function() action) async {
        try {
          await action();
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      }

      final handshake = _handshakeId;
      if (handshake != null && _client._handshakes.contains(handshake)) {
        await release(() => _client._closeHandshake(handshake));
      }
      final allocated = _allocatedId;
      if (!_delivered &&
          allocated != null &&
          (_client._connections.contains(allocated) ||
              _client._retiringConnections.contains(allocated))) {
        await release(() => _client._disconnect(allocated));
      }
      if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }
}

final class NativeAdbClient implements AdbClient, AdbConnectionClaims {
  NativeAdbClient(
    this.api,
    this.identityPath, {
    Object? nativeOwner,
    this.admissionScope,
    this.ownsAdmissionScope = true,
  }) : nativeOwner = nativeOwner ?? api {
    if (admissionScope != null &&
        (api is! NativeAdbAdmissionApi || api is! NativeAdbHandshakeApi)) {
      throw const AdbException('admission_scope_capability_unavailable');
    }
  }
  final NativeAdbApi api;
  final String identityPath;

  /// 显式使用已接管的准入权限，释放责任由 [ownsAdmissionScope] 指定。
  final AdbAdmissionScopeInfo? admissionScope;

  /// 借用共享准入域时，close 只排空本客户端资源，由外部唯一所有者关闭域。
  final bool ownsAdmissionScope;

  Future<void> _checkAdmissionScope() async {
    final scope = admissionScope;
    if (scope == null) return;
    final current = await (api as NativeAdbAdmissionApi).inspectAdmissionScope(
      scope.scopeKey,
    );
    if (current == null ||
        current.scopeId != scope.scopeId ||
        !current.accepting) {
      throw const AdbException('adb_admission_scope_stale');
    }
  }

  AdbIdentities get identities {
    _check();
    final bindings = api;
    if (bindings is AdbIdentities) return bindings as AdbIdentities;
    throw const AdbException('identity_capability_unavailable');
  }

  /// 配套协议能力可以共享此身份，设备句柄仍只能在同一个原生宿主内使用。
  final Object nativeOwner;
  bool _closed = false;
  Future<void>? _closing;
  final Set<String> _connections = {};
  final Set<String> _retiringConnections = {};
  final Set<AdbCancellation> _handshakeStops = {};
  final Set<Future<void>> _pendingAdmissions = {};
  final Set<String> _handshakes = {};
  final Map<String, Future<void>> _closingHandshakes = {};
  final Map<String, Future<void>> _disconnecting = {};
  Future<AdbDevice> _ownConnection(
    Future<AdbDevice> opening,
    AdbCancellation stop,
  ) async {
    final AdbDevice device;
    try {
      device = await opening;
    } catch (error) {
      if (error is AdbException && error.code == 'adb_cleanup_unconfirmed') {
        rethrow;
      }
      stop.check();
      rethrow;
    }
    // 即使准入已经撤销，也先保留实际句柄；失败的迟到回收仍由 close 重试。
    _connections.add(device.id);
    if (_closed || stop.isCancelled) {
      await _disconnect(device.id);
      stop.check();
      throw const AdbException('closed');
    }
    return _bindDevice(device);
  }

  Future<void> _closeHandshake(String id) =>
      _closingHandshakes.putIfAbsent(id, () {
        final bindings = api as NativeAdbHandshakeApi;
        return Future<void>.sync(() => bindings.closeHandshake(id))
            .then((_) => _handshakes.remove(id))
            .whenComplete(() {
              _closingHandshakes.remove(id);
            });
      });

  Future<T> _withHandshake<T>(
    Future<T> Function(String? id, AdbCancellation stop) action,
    AdbCancellation? cancellation, {
    bool preserveSuccess = false,
    NativeAdbConnectionAttempt? attempt,
  }) {
    cancellation?.check();
    final bindings = api;
    if (cancellation != null && bindings is! NativeAdbHandshakeApi) {
      throw const AdbException('handshake_cancellation_unavailable');
    }
    final stop = AdbCancellation();
    final unwatch = cancellation?.onCancel(stop.cancel);
    _handshakeStops.add(stop);
    final operation = () async {
      String? id;
      var succeeded = false;
      void Function()? unwatchNative;
      try {
        if (bindings is NativeAdbHandshakeApi) {
          final handshake = bindings as NativeAdbHandshakeApi;
          id = admissionScope == null
              ? await handshake.createHandshake()
              : await (bindings as NativeAdbAdmissionApi).createScopedHandshake(
                  admissionScope!.scopeId,
                );
          _handshakes.add(id);
          attempt?._handshakeId = id;
          final handle = id;
          unwatchNative = stop.onCancel(() {
            // 通知不能代替回收证明；finally 与 close 保留确认和重试责任。
            unawaited(
              Future<void>.sync(() => handshake.cancelHandshake(handle))
                  .catchError((Object _) {}),
            );
          });
        }
        stop.check();
        final result = await action(id, stop);
        succeeded = true;
        return result;
      } finally {
        unwatchNative?.call();
        unwatch?.call();
        try {
          if (id != null) await _closeHandshake(id);
        } catch (_) {
          // 配对成功是已发生的对端事实；失败登记仍由本 Client.close 精确重试。
          if (!preserveSuccess || !succeeded) rethrow;
        } finally {
          _handshakeStops.remove(stop);
        }
      }
    }();
    return operation;
  }

  Future<T> _trackAdmission<T>(Future<T> Function() action) {
    // 先登记再执行，close 必须等待迟到资源完成登记与精确回收。
    final settled = Completer<void>();
    _pendingAdmissions.add(settled.future);
    void complete() {
      _pendingAdmissions.remove(settled.future);
      settled.complete();
    }

    final Future<T> operation;
    try {
      operation = action();
    } catch (_) {
      complete();
      rethrow;
    }
    unawaited(
      operation.then<void>(
        (_) {
          complete();
        },
        onError: (Object _, StackTrace _) {
          complete();
        },
      ),
    );
    return operation;
  }

  Future<AdbDevice> _connectHandshake(
    Future<AdbDevice> Function(String? id) open,
    AdbCancellation? cancellation, {
    NativeAdbConnectionAttempt? attempt,
  }) => _trackAdmission(() {
    AdbDevice? allocated;
    final opening = _withHandshake(
      (id, stop) {
        return _ownConnection(
          open(id).then((device) {
            allocated = device;
            attempt?._allocatedId = device.id;
            return device;
          }),
          stop,
        ).then((device) async {
          if (admissionScope != null) {
            await (api as NativeAdbAdmissionApi).confirmHandshakeConnection(
              id!,
              device.id,
            );
          }
          return device;
        });
      },
      cancellation,
      attempt: attempt,
    );
    return opening
        .then((device) async {
          // 结束原生登记也会异步等待；交付前再次核对整个调用的准入。
          _check();
          cancellation?.check();
          await _checkAdmissionScope();
          _check();
          cancellation?.check();
          attempt?._delivered = true;
          return device;
        })
        .catchError((Object error, StackTrace stack) async {
          // 握手已成功但结束登记失败时，仍须精确回收未交给调用方的连接。
          final device = allocated;
          if (device != null &&
              _connections.contains(device.id) &&
              !_retiringConnections.contains(device.id)) {
            await _disconnect(device.id);
          }
          Error.throwWithStackTrace(error, stack);
        });
  });

  Future<void> _disconnect(String id) => _disconnecting.putIfAbsent(id, () {
    _retiringConnections.add(id);
    return Future<void>.sync(() => api.disconnect(id))
        .then((_) {
          _connections.remove(id);
          _retiringConnections.remove(id);
        })
        .whenComplete(() {
          _disconnecting.remove(id);
        });
  });

  @override
  late final AdbServices services = AdbServices(() => api, (device) async {
    _check();
    _checkDevice(device);
    return device;
  }, _check);
  @override
  AdbCapabilities get capabilities => AdbCapabilities(
    officialServer: false,
    suppressAuthorizationPrompt: true,
    forceTlsWithoutMdns: true,
    androidUsbFd: Platform.isAndroid,
  );
  void _check() {
    if (_closed) throw const AdbException('closed');
  }

  AdbDevice _bindDevice(AdbDevice device) => AdbDevice(
    id: device.id,
    serial: device.serial,
    state: device.state,
    features: device.features,
    nativeOwner: nativeOwner,
  );

  void _checkDevice(AdbDevice device, {bool cleanup = false}) {
    if (device.nativeOwner != null &&
        !identical(device.nativeOwner, nativeOwner)) {
      throw const AdbException('foreign_native_host');
    }
    if (!cleanup && _retiringConnections.contains(device.id)) {
      throw const AdbException('connection_retiring');
    }
  }

  @override
  Future<List<AdbDevice>> devices() async {
    _check();
    return (await api.devices()).map(_bindDevice).toList(growable: false);
  }

  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions? directOptions,
    AdbCancellation? cancellation,
  }) {
    _check();
    final options = directOptions ?? const AdbConnectOptions();
    options.validate();
    final timeoutMs = adbTimeoutMillis(timeout);
    return _connectHandshake(
      (id) => api.connect(
        address,
        identityPath,
        requireTls,
        authorize,
        timeoutMs,
        options: options,
        handshakeId: id,
      ),
      cancellation,
    );
  }

  /// Android 授权申请仍由平台负责。
  Future<AdbDevice> connectUsbFd(
    int fd,
    String serial, {
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions options = const AdbConnectOptions(),
    AdbCancellation? cancellation,
  }) {
    _check();
    options.validate();
    final timeoutMs = adbTimeoutMillis(timeout);
    return _connectHandshake(
      (id) => api.connectUsbFd(
        fd,
        serial,
        identityPath,
        authorize,
        timeoutMs,
        options: options,
        handshakeId: id,
      ),
      cancellation,
    );
  }

  /// 同步取得本次 USB 握手的关闭权，先保留此句柄再等待 result。
  /// 失败后须重试同一 attempt.close，不能关闭共享客户端代替本次清理。
  /// [fd] 仍由平台所有；原始 UsbDeviceConnection 不能在本次回收确认前释放。
  NativeAdbConnectionAttempt beginUsbFdConnection(
    int fd,
    String serial, {
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions options = const AdbConnectOptions(),
    AdbCancellation? cancellation,
  }) {
    _check();
    options.validate();
    final timeoutMs = adbTimeoutMillis(timeout);
    if (fd < 0) throw ArgumentError.value(fd, 'fd');
    if (api is! NativeAdbHandshakeApi) {
      throw const AdbException('handshake_cancellation_unavailable');
    }
    final attempt = NativeAdbConnectionAttempt._(this);
    attempt._start(
      () => _connectHandshake(
        (id) => api.connectUsbFd(
          fd,
          serial,
          identityPath,
          authorize,
          timeoutMs,
          options: options,
          handshakeId: id,
        ),
        attempt._stop,
        attempt: attempt,
      ),
      cancellation,
    );
    return attempt;
  }

  @override
  Future<AdbDevice> claimConnection(AdbDevice device) {
    _check();
    _checkDevice(device);
    final bindings = api;
    if (admissionScope != null) {
      return _connectHandshake(
        (handshake) => (bindings as NativeAdbAdmissionApi)
            .claimScopedConnection(device.id, handshake!),
        null,
      );
    }
    if (bindings is! NativeAdbConnectionApi) {
      throw const AdbException('connection_claim_unavailable');
    }
    return _trackAdmission(
      () => _ownConnection(
        (bindings as NativeAdbConnectionApi).claimConnection(device.id),
        AdbCancellation(),
      ),
    );
  }

  @override
  Future<void> disconnect(AdbDevice device) {
    _check();
    _checkDevice(device, cleanup: true);
    return _disconnect(device.id);
  }

  @override
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
    AdbCancellation? cancellation,
  }) {
    _check();
    final timeoutMs = adbTimeoutMillis(timeout);
    return _trackAdmission(
      () => _withHandshake(
        (id, stop) async {
          try {
            return await api.pair(
              address,
              password,
              identityPath,
              timeoutMs,
              handshakeId: id,
            );
          } catch (error) {
            if (error is AdbException &&
                const {
                  'pairing_result_unknown',
                  'adb_cleanup_unconfirmed',
                }.contains(error.code)) {
              rethrow;
            }
            if (stop.isCancelled) {
              throw const AdbException('cancelled', '配对已停止等待；对端可能已保存信任。');
            }
            rethrow;
          }
        },
        cancellation,
        preserveSuccess: true,
      ),
    );
  }

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) => services.shellEvents(
    device,
    command,
    timeout: timeout,
    cancellation: cancellation,
  );

  @override
  Future<int> push(
    AdbDevice device,
    File source,
    String remotePath, {
    int maxBytes = 1 << 40,
    int permissions = 420,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) => services
      .sync(device)
      .pushFile(
        AdbPath(remotePath),
        source,
        maxBytes: maxBytes,
        permissions: permissions,
        timeout: timeout,
        cancellation: cancellation,
      );

  @override
  Future<int> pull(
    AdbDevice device,
    String remotePath,
    File destination, {
    int maxBytes = 1 << 40,
    Duration timeout = const Duration(minutes: 30),
    AdbCancellation? cancellation,
  }) => services
      .sync(device)
      .pullFile(
        AdbPath(remotePath),
        destination,
        maxBytes: maxBytes,
        timeout: timeout,
        cancellation: cancellation,
      );

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final stop in _handshakeStops.toList()) {
      stop.cancel();
    }
    Object? failure;
    StackTrace? failureStack;
    Future<void> release(Future<void> operation) async {
      try {
        await operation;
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    try {
      await Future.wait<void>([
        // 连接、配对与认领共用完整准入等待，排空迟到资源的回收后才继续关闭。
        ..._pendingAdmissions,
        if (admissionScope case final scope? when ownsAdmissionScope)
          release(
            (api as NativeAdbAdmissionApi).closeAdmissionScope(scope.scopeId),
          ),
        release(services.close()),
      ]);
      await Future.wait<void>([
        ..._handshakes.toList().map((id) => release(_closeHandshake(id))),
        // 显式断开借用句柄也会产生清理责任，不能只重试本实例创建的连接。
        ...{
          ..._connections,
          ..._retiringConnections,
        }.map((id) => release(_disconnect(id))),
      ]);
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
    } catch (_) {
      // 准入保持关闭，但同一所有者仍可重试未确认的资源。
      _closing = null;
      rethrow;
    }
  }
}
