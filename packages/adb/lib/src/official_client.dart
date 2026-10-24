import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'api.dart';

final class _RetiringConnection {
  _RetiringConnection(this.device, {this.nativeReleased = false});
  final AdbDevice device;
  bool nativeReleased;
}

final class _OfficialAttempt {
  final stop = AdbCancellation();
  final done = Completer<void>();
}

final class _ConnectionSlot {
  _ConnectionSlot(this.serial);
  final String serial;
  int generation = 0;
  AdbDevice? admitted;
  final retiring = <String, _RetiringConnection>{};
  final handshakes = <String>{};
  bool disconnectServer = false;
  bool connectResultUnknown = false;
  Future<AdbDevice>? opening;
  Future<void> tail = Future.value();
}

/// 每个命令都指向明确持有的服务器；数值 -H 禁用缺失监听者时的常规自动启动；版本不匹配仍是独立失败情形。
final class OfficialAdbClient implements AdbClient, AdbTransportDiscovery {
  OfficialAdbClient(this.bindings, this.serverInfo) {
    if (bindings is! NativeAdbServerApi || bindings is! NativeAdbHandshakeApi) {
      throw const AdbException('owned_server_capability_unavailable');
    }
  }

  final NativeAdbApi bindings;
  final AdbServerInfo serverInfo;
  NativeAdbServerApi get _serverApi => bindings as NativeAdbServerApi;
  String get executable => serverInfo.launch.executable;
  int get port => Uri.parse('tcp://${serverInfo.launch.endpoint}').port;
  final _commands = <String>{};
  final _closingCommands = <String, Future<void>>{};
  final _pendingCommands = <Future<void>>{};
  final _attempts = <_OfficialAttempt>{};
  final _closingHandshakes = <String, Future<void>>{};
  bool _closed = false;
  final Map<String, _ConnectionSlot> _connections = {};
  Future<void>? _closing;

  void _check() {
    if (_closed || serverInfo.phase != AdbServerPhase.ready) {
      throw const AdbException('server_closed');
    }
  }

  @override
  late final AdbServices services = AdbServices(
    () => bindings,
    _resolve,
    _check,
  );
  Future<T> _attempt<T>(
    AdbCancellation? cancellation,
    Future<T> Function(AdbCancellation stop) action,
  ) async {
    _check();
    cancellation?.check();
    final attempt = _OfficialAttempt();
    final unwatch = cancellation?.onCancel(attempt.stop.cancel);
    _attempts.add(attempt);
    try {
      return await action(attempt.stop);
    } finally {
      unwatch?.call();
      _attempts.remove(attempt);
      attempt.done.complete();
    }
  }

  void _cancelHandshake(String id) {
    final api = bindings;
    if (api is NativeAdbHandshakeApi) {
      // 通知失败不释放登记；closeHandshake 才确认本机握手已经结束。
      unawaited(
        Future<void>.sync(
          () => (api as NativeAdbHandshakeApi).cancelHandshake(id),
        ).catchError((Object _) {}),
      );
    }
  }

  Future<void> _closeHandshake(_ConnectionSlot slot, String id) =>
      _closingHandshakes.putIfAbsent(id, () {
        final api = bindings as NativeAdbHandshakeApi;
        return Future<void>.sync(() => api.closeHandshake(id))
            .then((_) => slot.handshakes.remove(id))
            .whenComplete(() {
              _closingHandshakes.remove(id);
            });
      });

  Future<T> _serial<T>(_ConnectionSlot slot, Future<T> Function() action) {
    final result = slot.tail.then((_) => action());
    slot.tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _revoke(_ConnectionSlot slot) {
    slot.generation++;
    slot.opening = null;
    for (final id in slot.handshakes) {
      _cancelHandshake(id);
    }
    final previous = slot.admitted;
    slot.admitted = null;
    if (previous != null) {
      slot.retiring[previous.id] = _RetiringConnection(
        previous,
        nativeReleased: false,
      );
    }
  }

  void _checkGeneration(_ConnectionSlot slot, int generation) {
    _check();
    if (generation != slot.generation) {
      throw const AdbException('connection_invalidated');
    }
  }

  AdbException _unknownConnect([Object? failure]) => AdbException(
    'official_connect_result_unknown',
    '官方服务器在途建连结果未知；断开请求不能证明它已结束，请关闭原服务器并准备新宿主。'
        '${failure == null ? '' : ' 本机回收结果：$failure'}',
  );

  void _checkConnectionAdmission() {
    // target 的 IP、主机名和 mDNS 别名不能证明资源独立；未知状态覆盖本客户端全部新准入。
    if (serverInfo.transportStateUnknown ||
        _connections.values.any((slot) => slot.connectResultUnknown)) {
      throw _unknownConnect();
    }
  }

  Future<void> _drain(_ConnectionSlot slot) async {
    Object? failure;
    StackTrace? failureStack;
    for (final id in slot.handshakes.toList()) {
      try {
        await _closeHandshake(slot, id);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    for (final retirement in slot.retiring.values.toList()) {
      try {
        if (!retirement.nativeReleased) {
          await bindings.disconnect(retirement.device.id);
          retirement.nativeReleased = true;
        }
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
    if (slot.disconnectServer) {
      if (await _ownsServer()) {
        try {
          final result = await _run(
            ['disconnect', slot.serial],
            const Duration(seconds: 10),
            cleanup: true,
          );
          if (result.exitCode != 0) {
            throw const AdbException('disconnect_failed');
          }
        } catch (_) {
          // 未知服务器状态只能由宿主终止其服务器来收敛；不阻止外层继续关闭服务器。
          // 已知精确连接和握手的释放失败仍在上方抛出，不受此例外影响。
          if (_closed && slot.connectResultUnknown) return;
          rethrow;
        }
      }
      slot.disconnectServer = false;
    }
    slot.retiring.clear();
  }

  Future<AdbDevice> _open(
    _ConnectionSlot slot,
    int generation, {
    AdbCancellation? cancellation,
  }) async {
    _checkGeneration(slot, generation);
    _checkConnectionAdmission();
    cancellation?.check();
    final api = bindings;
    String? handshakeId;
    void Function()? unwatch;
    try {
      if (api is NativeAdbHandshakeApi) {
        handshakeId = await _serverApi.createServerHandshake(
          serverInfo.leaseId,
        );
        slot.handshakes.add(handshakeId);
        final id = handshakeId;
        unwatch = cancellation?.onCancel(() => _cancelHandshake(id));
      }
      _checkGeneration(slot, generation);
      _checkConnectionAdmission();
      cancellation?.check();
      final opened = await api.connectServer(
        '127.0.0.1:$port',
        slot.serial,
        15000,
        handshakeId: handshakeId,
      );
      final fixed = AdbDevice(
        id: opened.id,
        serial: opened.serial,
        state: opened.state,
        features: opened.features,
        nativeOwner: bindings,
      );
      // 即使握手 close 失败，也必须先保留已分配连接的精确回收权。
      slot.retiring[fixed.id] = _RetiringConnection(fixed);
      _checkGeneration(slot, generation);
      _checkConnectionAdmission();
      cancellation?.check();
      if (handshakeId != null) await _closeHandshake(slot, handshakeId);
      _checkGeneration(slot, generation);
      _checkConnectionAdmission();
      cancellation?.check();
      slot.retiring.remove(fixed.id);
      slot.disconnectServer = false;
      slot.admitted = fixed;
      return fixed;
    } catch (error, stack) {
      if (handshakeId != null) _cancelHandshake(handshakeId);
      await _drain(slot);
      Error.throwWithStackTrace(error, stack);
    } finally {
      unwatch?.call();
    }
  }

  Future<AdbDevice> _resolve(
    AdbDevice device, {
    AdbCancellation? cancellation,
  }) {
    _check();
    cancellation?.check();
    _checkDevice(device);
    if (device.id != device.serial) {
      for (final slot in _connections.values) {
        if (slot.admitted?.id == device.id) {
          return Future.value(slot.admitted!);
        }
      }
      throw const AdbException('unknown_connection');
    }
    final slot = _connections.putIfAbsent(
      device.serial,
      () => _ConnectionSlot(device.serial),
    );
    if (slot.admitted case final admitted?) return Future.value(admitted);
    _checkConnectionAdmission();
    if (slot.opening case final opening?) return opening;
    final generation = slot.generation;
    return _ownOpening(slot, () async {
      _checkConnectionAdmission();
      await _drain(slot);
      return _open(slot, generation, cancellation: cancellation);
    });
  }

  Future<AdbDevice> _ownOpening(
    _ConnectionSlot slot,
    Future<AdbDevice> Function() action,
  ) {
    late final Future<AdbDevice> opening;
    opening = _serial(slot, () async {
      try {
        return await action();
      } finally {
        if (identical(slot.opening, opening)) slot.opening = null;
      }
    });
    slot.opening = opening;
    return opening;
  }

  void _checkDevice(AdbDevice device) {
    if (device.nativeOwner != null &&
        !identical(device.nativeOwner, bindings)) {
      throw const AdbException('foreign_native_host');
    }
  }

  @override
  AdbCapabilities get capabilities => const AdbCapabilities(
    officialServer: true,
    suppressAuthorizationPrompt: false,
    forceTlsWithoutMdns: false,
    androidUsbFd: false,
  );

  Future<bool> _ownsServer() async => (await _serverApi.listServers()).any(
    (entry) =>
        entry.leaseId == serverInfo.leaseId &&
        entry.phase == AdbServerPhase.ready,
  );

  Future<void> _closeCommand(String id) => _closingCommands.putIfAbsent(id, () {
    return Future<void>.sync(() => _serverApi.closeServerCommand(id))
        .then((_) {
          _commands.remove(id);
        })
        .whenComplete(() {
          _closingCommands.remove(id);
        });
  });

  Future<T> _withCommand<T>(
    List<String> arguments,
    Duration timeout,
    Future<T> Function(AdbServerCommandResult result, String id) interpret, {
    List<int>? input,
    AdbCancellation? cancellation,
    bool cleanup = false,
    bool mayCreateTransport = false,
    bool preserveSuccess = false,
    void Function()? onStart,
    void Function()? onStartFailed,
  }) {
    final timeoutMs = adbTimeoutMillis(timeout);
    if (!cleanup) _check();
    cancellation?.check();
    final settled = Completer<void>();
    _pendingCommands.add(settled.future);
    return () async {
      String? id;
      void Function()? unwatch;
      var succeeded = false;
      try {
        id = await _serverApi.createServerCommand(
          serverInfo.leaseId,
          AdbServerCommandSpec(
            executable: executable,
            arguments: ['-H', '127.0.0.1', '-P', '$port', ...arguments],
            input: Uint8List.fromList(input ?? const []),
            timeoutMs: timeoutMs,
            mayCreateTransport: mayCreateTransport,
          ),
        );
        // 先登记迟到返回的精确句柄，关闭和取消都不能丢弃它。
        _commands.add(id);
        if (!cleanup) _check();
        cancellation?.check();
        final command = id;
        unwatch = cancellation?.onCancel(() {
          unawaited(
            _serverApi.cancelServerCommand(command).catchError((Object _) {}),
          );
        });
        onStart?.call();
        final result = await _serverApi.runServerCommand(id);
        if (result.status == AdbServerCommandStatus.startFailed) {
          onStartFailed?.call();
        }
        if (result.status != AdbServerCommandStatus.exited) {
          throw AdbException(switch (result.status) {
            AdbServerCommandStatus.cancelled => 'cancelled',
            AdbServerCommandStatus.timedOut => 'timeout',
            AdbServerCommandStatus.outputLimit => 'output_limit',
            AdbServerCommandStatus.startFailed => 'command_start_failed',
            AdbServerCommandStatus.ioFailed => 'command_io_failed',
            AdbServerCommandStatus.exited => 'invalid_command_result',
          }, result.errorMessage ?? '');
        }
        final value = await interpret(result, id);
        succeeded = true;
        return value;
      } finally {
        unwatch?.call();
        try {
          if (id != null) await _closeCommand(id);
        } catch (_) {
          // 已确认的配对是对端事实；保留失败登记，由 close 重试，不伪造配对失败。
          if (!preserveSuccess || !succeeded) rethrow;
        } finally {
          _pendingCommands.remove(settled.future);
          settled.complete();
        }
      }
    }();
  }

  Future<AdbServerCommandResult> _run(
    List<String> arguments,
    Duration timeout, {
    List<int>? input,
    AdbCancellation? cancellation,
    bool cleanup = false,
  }) => _withCommand(
    arguments,
    timeout,
    (result, _) async => result,
    input: input,
    cancellation: cancellation,
    cleanup: cleanup,
  );

  @override
  Future<List<AdbDevice>> devices() => _devices();

  @override
  Future<List<AdbTransport>> transports({
    Duration timeout = const Duration(seconds: 3),
    AdbCancellation? cancellation,
  }) async {
    _checkConnectionAdmission();
    final result = await _run(
      ['devices', '-l'],
      timeout,
      cancellation: cancellation,
    );
    _checkConnectionAdmission();
    cancellation?.check();
    if (result.exitCode != 0) throw const AdbException('devices_failed');
    return _parseTransports(result.stdout);
  }

  Future<List<AdbDevice>> _devices({AdbCancellation? cancellation}) async {
    final listed = await transports(
      timeout: const Duration(seconds: 10),
      cancellation: cancellation,
    );
    return Future.wait(
      listed.map((transport) {
        final device = AdbDevice(
          id: transport.serial,
          serial: transport.serial,
          state: transport.state,
        );
        return device.state == 'device'
            ? _resolve(device, cancellation: cancellation)
            : Future.value(device);
      }),
    );
  }

  /// 取消 CLI 不确认服务器在途建连已退出；本客户端拒绝全部新连接与设备解析，须关闭原服务器。
  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions? directOptions,
    AdbCancellation? cancellation,
  }) async {
    if (directOptions != null) {
      throw const AdbException('official_adb_controls_connection_options');
    }
    validateAdbPath(address);
    adbTimeoutMillis(timeout);
    return _attempt(cancellation, (stop) async {
      _checkConnectionAdmission();
      // 官方 adb 决定 TLS 握手，不能禁止授权对话框或提供明文降级策略。
      final target = requireTls
          ? await _tlsService(address, timeout, cancellation: stop)
          : address;
      stop.check();
      if (!authorize) {
        final existing = (await _devices(cancellation: stop))
            .where((d) => d.serial == target && d.state == 'device');
        stop.check();
        if (existing.isNotEmpty) return existing.first;
        throw const AdbException('official_adb_cannot_suppress_authorization');
      }
      _check();
      final slot = _connections.putIfAbsent(
        target,
        () => _ConnectionSlot(target),
      );
      _checkConnectionAdmission();
      _revoke(slot);
      final generation = slot.generation;
      return _ownOpening(slot, () async {
        _checkConnectionAdmission();
        await _drain(slot);
        _checkGeneration(slot, generation);
        _checkConnectionAdmission();
        stop.check();
        var issued = false;
        var confirmed = false;
        try {
          await _withCommand<void>(
            ['connect', target],
            timeout,
            (result, commandId) async {
              final message = utf8
                  .decode(result.stdout, allowMalformed: true)
                  .trim();
              if (result.exitCode != 0 ||
                  (!message.startsWith('connected to ') &&
                      !message.startsWith('already connected to '))) {
                throw const AdbException('connect_failed');
              }
              if (message.startsWith('already connected to ')) {
                final state = await _run(
                  ['-s', target, 'get-state'],
                  timeout,
                  cancellation: stop,
                );
                if (state.exitCode != 0 ||
                    utf8.decode(state.stdout).trim() != 'device') {
                  throw const AdbException('official_transport_not_active');
                }
              }
              stop.check();
              await _serverApi.confirmServerCommand(commandId);
              confirmed = true;
            },
            cancellation: stop,
            mayCreateTransport: true,
            onStart: () {
              // CLI 退出不代表服务器在途建连已退出；发起前登记断开请求的回收责任。
              issued = true;
              slot.disconnectServer = true;
            },
            onStartFailed: () {
              // 原生明确未创建 Child，不得把未发出的请求记为服务器未知。
              issued = false;
              slot.disconnectServer = false;
            },
          );
          _checkGeneration(slot, generation);
          _checkConnectionAdmission();
          stop.check();
        } catch (error, stack) {
          if (issued && !confirmed) slot.connectResultUnknown = true;
          try {
            await _drain(slot);
          } catch (cleanupError) {
            if (slot.connectResultUnknown) throw _unknownConnect(cleanupError);
            rethrow;
          }
          if (slot.connectResultUnknown) throw _unknownConnect(error);
          Error.throwWithStackTrace(error, stack);
        }
        return _open(slot, generation, cancellation: stop);
      });
    });
  }

  Future<String> _tlsService(
    String address,
    Duration timeout, {
    AdbCancellation? cancellation,
  }) async {
    final result = await _run(
      ['mdns', 'services'],
      timeout,
      cancellation: cancellation,
    );
    if (result.exitCode != 0) {
      throw const AdbException('secure_mdns_unavailable');
    }
    final services = <String>{};
    final endpoint = Uri.tryParse('tcp://$address');
    final candidates = <String>{};
    if (endpoint != null && endpoint.hasPort && endpoint.host.isNotEmpty) {
      for (final ip in await InternetAddress.lookup(endpoint.host)) {
        candidates.add('${ip.address}:${endpoint.port}');
      }
    }
    for (final line in LineSplitter.split(utf8.decode(result.stdout))) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 3 ||
          fields[1].replaceFirst(RegExp(r'\.$'), '') !=
              '_adb-tls-connect._tcp') {
        continue;
      }
      final fullname = '${fields[0]}._adb-tls-connect._tcp';
      if (candidates.contains(fields[2]) ||
          address.replaceFirst(RegExp(r'\.$'), '') == fullname) {
        services.add(fullname);
      }
    }
    if (services.length != 1) {
      throw const AdbException('secure_mdns_unavailable');
    }
    return services.single;
  }

  @override
  Future<void> disconnect(AdbDevice device) async {
    _check();
    _checkDevice(device);
    _ConnectionSlot? selected;
    {
      for (final slot in _connections.values) {
        if (slot.admitted?.id == device.id) {
          selected = slot;
          break;
        }
        if (slot.retiring.containsKey(device.id)) {
          // 此调用只重试旧句柄的释放，不能撤销已排队后继的代次。
          return _serial(slot, () async {
            // 前面的替换可能已完成旧句柄回收，届时不能再按 serial 断开服务器。
            if (slot.retiring.containsKey(device.id)) await _drain(slot);
          });
        }
      }
    }
    if (selected == null) throw const AdbException('unknown_connection');
    final slot = selected;
    // 在任何 await 前撤销旧准入；旧精确句柄不能按 serial 找到后继连接。
    _revoke(slot);
    slot.disconnectServer = true;
    return _serial(slot, () => _drain(slot));
  }

  /// 取消或失败只结束本机配对命令，不撤销对端可能已经建立的信任。
  @override
  Future<String> pair(
    String address,
    String password, {
    Duration timeout = const Duration(seconds: 30),
    AdbCancellation? cancellation,
  }) async {
    validateAdbPath(address);
    if (password.isEmpty ||
        password.contains('\n') ||
        password.contains('\r') ||
        password.length > 1024) {
      throw ArgumentError('Invalid pairing password');
    }
    adbTimeoutMillis(timeout);
    return _attempt(cancellation, (stop) async {
      try {
        return await _withCommand<String>(
          ['pair', address],
          timeout,
          (result, _) async {
            final guid = RegExp(r'\[guid=([^\]]+)\]')
                .firstMatch(utf8.decode(result.stdout, allowMalformed: true))
                ?.group(1);
            if (result.exitCode != 0 || guid == null || guid.isEmpty) {
              throw const AdbException('pair_failed', '对端可能已建立信任，请核验后再重试。');
            }
            return guid;
          },
          input: utf8.encode('$password\n'),
          cancellation: stop,
          preserveSuccess: true,
        );
      } catch (error) {
        if (error is AdbException && error.code == 'cancelled') {
          throw const AdbException('cancelled', '配对已取消；对端可能已建立信任，此操作不撤销授权。');
        }
        throw AdbException(
          error is AdbException ? error.code : 'pair_result_unknown',
          '配对未获完整确认；对端可能已建立信任，请核验后再重试。',
        );
      }
    });
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

  /// 只确认本实例已知本机资源结束；建连结果未知时仍须由 AdbHost 终止其服务器。
  @override
  Future<void> close() {
    if (_closing case final closing?) return closing;
    _closed = true;
    for (final attempt in _attempts) {
      attempt.stop.cancel();
    }
    for (final id in _commands.toList()) {
      unawaited(_serverApi.cancelServerCommand(id).catchError((Object _) {}));
    }
    for (final slot in _connections.values) {
      _revoke(slot);
    }
    late final Future<void> closing;
    closing = _close().catchError((Object error, StackTrace stack) {
      if (identical(_closing, closing)) _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _closing = closing;
  }

  Future<void> _close() async {
    // 独立回收各所有者，即使一个阶段失败也不跳过其他已持有的资源。
    // 服务器进程由 AdbHost 持有，此处只等待本客户端的命令和原生资源退出。
    await Future.wait<void>([
      services.close(),
      ..._pendingCommands,
      for (final attempt in _attempts.toList()) attempt.done.future,
      for (final slot in _connections.values) _serial(slot, () => _drain(slot)),
    ]);
    await Future.wait(_commands.toList().map(_closeCommand));
    // 保留未知目标的事实，成功的定向 disconnect 也不能撤销该准入栅栏。
    _connections.removeWhere((_, slot) => !slot.connectResultUnknown);
  }
}

List<AdbTransport> _parseTransports(Uint8List bytes) {
  Never invalid() => throw const AdbException('invalid_devices_response');
  late final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    invalid();
  }
  if (text.runes.any(
    (c) => c < 32 && c != 9 && c != 10 && c != 13 || c == 127,
  )) {
    invalid();
  }
  final lines = LineSplitter.split(text).iterator;
  if (!lines.moveNext() || lines.current.trim() != 'List of devices attached') {
    invalid();
  }
  final serials = <String>{};
  final ids = <int>{};
  final result = <AdbTransport>[];
  while (lines.moveNext()) {
    final line = lines.current.trim();
    if (line.isEmpty) continue;
    final fields = line.split(RegExp(r'\s+'));
    if (fields.length < 2 || !serials.add(fields.first)) invalid();
    final serial = fields.first;
    var state = fields[1];
    var offset = 2;
    if (state == 'no' && fields.length > 2 && fields[2] == 'permissions') {
      // AOSP 在此状态内插入宿主权限帮助文本；它不是设备元数据。
      state = 'no permissions';
      offset = 3;
    } else if (!const {
      'offline',
      'bootloader',
      'device',
      'host',
      'recovery',
      'rescue',
      'sideload',
      'unauthorized',
      'authorizing',
      'connecting',
      'detached',
      'any',
    }.contains(state)) {
      invalid();
    }
    final metadata = <String, String>{};
    for (final field in fields.skip(offset)) {
      final colon = field.indexOf(':');
      if (colon < 1 || colon == field.length - 1) {
        if (state == 'no permissions') continue;
        invalid();
      }
      final key = field.substring(0, colon);
      if (!const {
        'usb',
        'product',
        'model',
        'device',
        'transport_id',
      }.contains(key)) {
        // 允许后续版本扩展键值字段，不把它们猜作 USB 或现有字段。
        continue;
      }
      if (metadata.containsKey(key)) invalid();
      metadata[key] = field.substring(colon + 1);
    }
    int? transportId;
    if (metadata['transport_id'] case final value?) {
      if (!RegExp(r'^[0-9]+$').hasMatch(value)) invalid();
      transportId = int.tryParse(value);
      if (transportId == null || transportId < 1 || !ids.add(transportId)) {
        invalid();
      }
    }
    result.add(
      AdbTransport(
        serial: serial,
        state: state,
        usbPath: metadata['usb'],
        product: metadata['product'],
        model: metadata['model'],
        device: metadata['device'],
        transportId: transportId,
      ),
    );
  }
  return List.unmodifiable(result);
}
