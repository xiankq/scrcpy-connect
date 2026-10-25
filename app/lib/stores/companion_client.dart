import 'package:scrcpy_connect/models/companion_exception.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

import 'package:scrcpy_connect/services/companion_process.dart';
import 'package:scrcpy_connect/services/companion_protocol.dart';

export 'package:scrcpy_connect/services/companion_process.dart'
    show CompanionDeploymentIdentity, cleanupCompanionDeployment;
export 'package:scrcpy_connect/models/companion_exception.dart';

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

final class _Request {
  _Request(this.id, this.bytes, this.mutation);
  final String id;
  final Uint8List bytes;
  final bool mutation;
  final completion = Completer<Object?>();
  bool sent = false, written = false;
  Timer? timer;
  void Function()? unsubscribe;
}

/// 一次精确连接上的部署与 RPC 所有者；构造后即由调用者负责 finally close。
/// start 失败也保留本对象，以便重试关闭；close 不断开共享 ADB 连接。
/// 事件为单订阅、无历史重放；暂停期间有界缓存，溢出使本连接失败而非静默丢事实。
final class CompanionClient {
  CompanionClient({
    required this.connection,
    required Uint8List serverBytes,
    required this.config,
  }) : _serverBytes = Uint8List.fromList(serverBytes) {
    config.validate();
    if (serverBytes.isEmpty) throw ArgumentError('已核验的互联服务 JAR 不能为空。');
    _ready.future.ignore();
    _events = StreamController<Map<String, Object?>>(
      sync: true,
      onPause: () => _eventsPaused = true,
      onResume: () {
        _eventsPaused = false;
        _flushEvents();
      },
      onCancel: () {
        _queuedEvents.clear();
      },
    );
  }
  final DeviceConnection connection;
  final CompanionConfig config;
  final Uint8List _serverBytes;
  final _lifetime = AdbCancellation();
  final _sessionCancellation = <void Function()>[];
  final _pending = <String, _Request>{};
  final _queuedEvents = Queue<Map<String, Object?>>();
  late final StreamController<Map<String, Object?>> _events;
  final _ready = Completer<Map<String, Object?>>();
  Future<Map<String, Object?>>? _starting;
  Future<void>? _closing, _rpcReader, _shellDrain;
  Future<void> _writeTail = Future.value();
  AdbServiceSession? _upload, _process, _socket;
  Future<void>? _uploadCompletion;
  StreamIterator<Uint8List>? _shellLines;
  CompanionDeploymentIdentity? _identity;
  String? _jar;
  Object? _failure;
  Object? _eventFailure;
  bool _closed = false, _started = false, _eventsPaused = false;
  bool _launchIssued = false;
  bool _mediaMayExist = false, _eventsFinished = false;
  Stream<Map<String, Object?>> get events => _events.stream;
  CompanionDeploymentIdentity? get deploymentIdentity => _identity;

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _operationId() {
    final hex = _randomHex(16);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _check() {
    if (_closed) throw const CompanionException('closed', '互联服务已停止准入。');
    if (_failure case final failure?) throw failure;
  }

  /// 上传调用方已核验的字节；只接受认证后 protocol=1、uid=2000 的启动事实。
  Future<Map<String, Object?>> start({AdbCancellation? cancellation}) {
    _check();
    cancellation?.check();
    return _starting ??= _start(cancellation);
  }

  Future<Map<String, Object?>> _start(AdbCancellation? cancellation) async {
    // 在任何异步失败前安装处理器，仍由实际 await 报告原错误。
    _ready.future.ignore();
    final unsubscribe = cancellation?.onCancel(_lifetime.cancel);
    final deadline = Timer(
      config.startupTimeout,
      () => _fault(const CompanionException('timeout', '互联服务启动超时。')),
    );
    try {
      final socketName = 'interop-companion-${_randomHex(16)}';
      final secret = _randomHex(32);
      final jar = _jar = '/data/local/tmp/$socketName.jar';
      _lifetime.check();
      await _pushServer(jar);
      _check();
      _lifetime.check();
      _launchIssued = true;
      _process = await connection.client.services.exec(
        connection.device,
        companionLaunchCommand(jar, socketName, secret),
        timeout: config.sessionTimeout,
      );
      _watch(_process!);
      _lifetime.check();
      _shellLines = StreamIterator(
        companionLines(
          _process!.events.map((event) => event.bytes),
          maximumBytes: 8192,
        ),
      );
      var startupBytes = 0;
      var ready = false;
      while (await _shellLines!.moveNext()) {
        final bytes = _shellLines!.current;
        startupBytes += bytes.length + 1;
        if (startupBytes > 8192) {
          throw const CompanionException('companion_startup', '启动输出超过限制。');
        }
        final line = utf8.decode(bytes);
        if (_identity == null) {
          final match = RegExp(r'^__INTEROP_PID__([0-9]+):([0-9]+)$')
              .firstMatch(line);
          if (match == null) {
            throw const CompanionException('process_identity', '启动标识缺失。');
          }
          _identity = CompanionDeploymentIdentity(
            pid: int.parse(match[1]!),
            started: int.parse(match[2]!),
            jarPath: jar,
          );
        } else if (line == 'INTEROP_COMPANION_READY ${_identity!.pid}') {
          ready = true;
          break;
        }
      }
      if (!ready) {
        throw const CompanionException('companion_startup', '互联服务未返回启动回执。');
      }
      _shellDrain = _drainShell();
      _check();
      _lifetime.check();
      _socket = await connection.client.services.connectSocket(
        connection.device,
        AdbSocket.localAbstract(socketName),
        timeout: config.sessionTimeout,
      );
      _watch(_socket!);
      _lifetime.check();
      _rpcReader = _readMessages();
      await _socket!.write(
        Uint8List.fromList(utf8.encode('${jsonEncode({'token': secret})}\n')),
      );
      final initial = await _ready.future;
      _check();
      _lifetime.check();
      _started = true;
      return initial;
    } catch (error, stack) {
      _fault(error);
      Error.throwWithStackTrace(error, stack);
    } finally {
      deadline.cancel();
      unsubscribe?.call();
    }
  }

  Future<void> _pushServer(String jar) async {
    // 创建不可提前放弃：先保存迟到句柄，再绑定已可能撤销的 lifetime。
    final session = _upload = await connection.client.services
        .sync(connection.device)
        .openPush(
          AdbPath(jar),
          maxBytes: _serverBytes.length,
          permissions: 420,
          timeout: config.startupTimeout,
        );
    _watch(session);
    try {
      _lifetime.check();
      final reading = () async {
        int? transferred;
        await for (final event in session.events) {
          if (event.done) transferred = event.transferred;
        }
        if (transferred != _serverBytes.length) {
          throw const CompanionException('server_integrity', '互联服务上传不完整。');
        }
      }();
      // 读写并行，立即观察读取错误；原错误仍由下面的 await 呈现。
      _uploadCompletion = reading.then<void>((_) {}, onError: (Object _) {});
      await session.addStream(Stream.value(_serverBytes));
      await session.finish();
      await reading;
    } finally {
      await _releaseUpload();
    }
  }

  Future<void> _releaseUpload() async {
    if (_upload case final session?) {
      try {
        await session.close();
      } catch (error) {
        // 关闭失败仍保留原 session；后续 close 只重试此精确操作。
        throw CompanionException('cleanup_unconfirmed', '上传会话关闭未确认：$error');
      }
      await _uploadCompletion;
      _upload = null;
      _uploadCompletion = null;
    }
  }

  void _watch(AdbServiceSession session) {
    // 先保存精确句柄再绑定撤销；创建迟到后的清理失败仍由本对象重试。
    _sessionCancellation.add(
      _lifetime.onCancel(() {
        unawaited(session.close().catchError((Object _) {}));
      }),
    );
  }

  Future<void> _drainShell() async {
    try {
      while (await _shellLines!.moveNext()) {
        /* 启动后日志不持久保留。 */
      }
      if (!_lifetime.isCancelled) {
        _fault(const CompanionException('disconnected', '服务进程已结束。'));
      }
    } catch (error) {
      if (!_lifetime.isCancelled) _fault(error);
    }
  }

  Future<void> _readMessages() async {
    try {
      await for (final frame in companionLines(
        _socket!.events.map((event) => event.bytes),
        maximumBytes: config.maximumMessageBytes,
      )) {
        _receive(companionMessage(frame));
      }
      if (!_lifetime.isCancelled) {
        _fault(const CompanionException('disconnected', '互联服务已断开。'));
      }
    } catch (error) {
      if (!_lifetime.isCancelled) _fault(error);
    }
  }

  void _receive(Map<String, Object?> message) {
    if (message['event'] == 'ready') {
      if (_ready.isCompleted ||
          message['protocol'] is! int ||
          message['uid'] is! int ||
          message['protocol'] != 1 ||
          message['uid'] != 2000) {
        throw const CompanionException(
          'protocol_error',
          '互联服务协议或 shell 身份不匹配。',
        );
      }
      _ready.complete(message);
      return;
    }
    if (message['requestId'] case final String id) {
      final request = _pending[id];
      if (request == null) return; // 取消或超时后的迟到回执不得回写新请求。
      if (message['error'] case final Map<Object?, Object?> error) {
        final code = error['code'], reason = error['message'];
        if (code is! String || reason is! String) {
          throw const CompanionException('protocol_error', '互联服务错误回执无效。');
        }
        _finish(request, error: CompanionException(code, reason));
      } else if (message.containsKey('result')) {
        _finish(request, result: message['result']);
      } else {
        throw const CompanionException('protocol_error', '互联服务结果回执缺失。');
      }
    } else if (message['event'] is String) {
      if (_closed) return;
      if (!_events.hasListener) return;
      if (_eventsPaused) {
        if (_queuedEvents.length >= config.maximumQueuedEvents) {
          throw const CompanionException('event_limit', '互联服务事件消费过慢，需要重新核验。');
        }
        _queuedEvents.add(message);
      } else {
        _events.add(message);
      }
    } else {
      throw const CompanionException('protocol_error', '互联服务消息类型无效。');
    }
  }

  void _flushEvents() {
    while (!_eventsPaused && _queuedEvents.isNotEmpty) {
      _events.add(_queuedEvents.removeFirst());
    }
    if (_eventsFinished && _queuedEvents.isEmpty && !_events.isClosed) {
      if (_eventFailure case final error? when _events.hasListener) {
        _events.addError(error);
      }
      unawaited(_events.close());
    }
  }

  /// mutation 由业务调用者明确声明；未知副作用不会自动重放。
  Future<Object?> request(
    String command,
    Map<String, Object?> parameters, {
    required bool mutation,
    AdbCancellation? cancellation,
  }) {
    _check();
    if (!_started) throw const CompanionException('not_started', '互联服务尚未启动。');
    return _request(command, parameters, mutation, cancellation);
  }

  Future<Object?> _request(
    String command,
    Map<String, Object?> parameters,
    bool mutation,
    AdbCancellation? cancellation, {
    bool allowClosing = false,
  }) {
    cancellation?.check();
    if (command.isEmpty || command.contains('\u0000')) {
      throw ArgumentError('无效命令。');
    }
    if (_pending.length >= config.maximumPendingRequests) {
      throw const CompanionException('busy', '互联服务在途请求已达上限。');
    }
    final id = _randomHex(16);
    final bytes = utf8.encode(
      jsonEncode({...parameters, 'command': command, 'requestId': id}),
    );
    if (bytes.length > config.maximumMessageBytes) {
      throw const CompanionException('input_limit', '互联服务请求超过限制。');
    }
    final request = _Request(id, Uint8List.fromList([...bytes, 10]), mutation);
    _pending[id] = request;
    request.unsubscribe = cancellation?.onCancel(
      () => _abandon(request, 'cancelled'),
    );
    request.timer = Timer(config.requestTimeout, () {
      final incompleteWrite = request.sent && !request.written;
      _abandon(request, 'timeout');
      if (incompleteWrite) {
        _fault(const CompanionException('timeout', '互联服务写入未完成。'));
      }
    });
    final write = _writeTail.then((_) async {
      if (request.completion.isCompleted) return;
      if (_failure != null || (_closed && !allowClosing)) {
        _abandon(request, 'disconnected');
        return;
      }
      request.sent = true;
      if (command.startsWith('media.') && command != 'media.shutdown') {
        _mediaMayExist = true;
      }
      try {
        // 单个服务写入上限为 64 KiB；同一帧发出后始终完成它，避免取消制造半帧。
        for (var offset = 0; offset < request.bytes.length; offset += 65536) {
          final end = min(offset + 65536, request.bytes.length);
          await _socket!.write(
            Uint8List.sublistView(request.bytes, offset, end),
          );
        }
        request.written = true;
      } catch (error) {
        _fault(error);
      }
    });
    _writeTail = write.then<void>(
      (_) {},
      onError: (Object error) {
        _fault(error);
      },
    );
    return request.completion.future;
  }

  void _finish(_Request request, {Object? result, Object? error}) {
    if (request.completion.isCompleted) return;
    _pending.remove(request.id);
    request.timer?.cancel();
    request.unsubscribe?.call();
    if (error == null) {
      request.completion.complete(result);
    } else {
      request.completion.completeError(error);
    }
  }

  void _abandon(_Request request, String code) => _finish(
    request,
    error: CompanionException(
      request.sent && request.mutation ? 'result_unknown' : code,
      request.sent && request.mutation
          ? '动作已发出，结果未确认，不会自动重试。'
          : '互联服务请求未完成：$code。',
    ),
  );
  void _fault(Object error) {
    if (_failure != null) return;
    _failure = error;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final request in _pending.values.toList()) {
      _abandon(request, 'disconnected');
    }
    _lifetime.cancel();
    _eventFailure = error;
    _eventsFinished = true;
    _flushEvents();
  }

  /// 同步停止新准入；只在全部本机资源和精确远端进程确认退出后成功。
  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    return _closing = _close().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _close() async {
    // start 尚在等待时必须先取消，随后仍等待真实迟到返回并保留其资源。
    if (!_started) {
      _fault(const CompanionException('closed', '互联服务启动已被关闭。'));
    }
    await _starting?.then<void>((_) {}, onError: (Object _) {});
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

    // 撤销普通请求，但保留完整写入中的帧和认证通道供精确 shutdown 使用。
    for (final request in _pending.values.toList()) {
      _abandon(request, 'cancelled');
    }
    await release(_releaseUpload);
    if (_mediaMayExist && _socket != null && _failure == null) {
      try {
        // 子进程关闭属于部署机制；不安装任何观察或通知产品策略。
        final result = await _request(
          'media.shutdown',
          {'operationId': _operationId()},
          false,
          null,
          allowClosing: true,
        );
        if (result is! Map<Object?, Object?> || result['reaped'] != true) {
          throw const CompanionException(
            'cleanup_unconfirmed',
            '互联服务子进程尚未确认退出。',
          );
        }
        _mediaMayExist = false;
      } catch (error) {
        if (_socket != null && _failure == null && !_lifetime.isCancelled) {
          // 有效失败回执或未损坏通道上的超时不能夺走下一次确认机会。
          throw CompanionException(
            'cleanup_unconfirmed',
            '媒体子进程未确认退出，保留原认证通道供重试：$error',
          );
        }
        // 通道实际失效后仍继续核验主进程；下方单独保留子进程未知事实。
      }
    }
    _lifetime.cancel();
    for (final request in _pending.values.toList()) {
      _abandon(request, 'cancelled');
    }
    if (_socket case final socket?) {
      await release(() async {
        await socket.close();
        _socket = null;
      });
    }
    if (_process case final process?) {
      await release(() async {
        await process.close();
        _process = null;
      });
    }
    await release(() async {
      await _shellLines?.cancel();
    });
    await release(() async {
      await _writeTail;
      await _rpcReader;
      await _shellDrain;
    });
    // 本机流清理失败时不继续删除远端输入，精确对象保留供下次关闭。
    if (failure == null) {
      if (_identity case final identity?) {
        await release(() async {
          if (_mediaMayExist) {
            await stopCompanionProcess(
              connection,
              identity,
              timeout: config.cleanupTimeout,
            );
            return; // 主进程已退出也不删除子进程仍可能需要的 JAR。
          }
          await cleanupCompanionDeployment(
            connection,
            identity,
            timeout: config.cleanupTimeout,
          );
          _identity = null;
          _jar = null;
        });
      } else if (_jar case final jar?) {
        await release(() async {
          // 未取得进程身份时，仅能确认上传路径删除，不能假称 Java 已经退出。
          if (_launchIssued) {
            throw const CompanionException(
              'cleanup_unconfirmed',
              '未收到精确进程身份，不能确认远端退出。',
            );
          }
          final result = await companionShell(
            connection,
            'rm -f -- ${companionQuote(jar)} && print -r -- removed',
            timeout: config.cleanupTimeout,
          );
          if (result.trim() != 'removed') {
            throw const CompanionException('cleanup_unconfirmed', '部署路径未确认删除。');
          }
          _jar = null;
        });
      }
    }
    if (_mediaMayExist) {
      failure ??= const CompanionException(
        'cleanup_unconfirmed',
        '原媒体子进程退出事实仍未知；主进程核验不能替代此回执。',
      );
      trace ??= StackTrace.current;
    }
    if (failure != null) Error.throwWithStackTrace(failure!, trace!);
    for (final unsubscribe in _sessionCancellation) {
      unsubscribe();
    }
    _sessionCancellation.clear();
    _eventsFinished = true;
    _flushEvents();
  }
}
