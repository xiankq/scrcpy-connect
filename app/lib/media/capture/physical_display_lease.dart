import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import '../../application/transport/application_command_exception.dart';
import '../../connection/connection_owner.dart';
import 'physical_display_script.dart';
import 'physical_display_command.dart';

/// 逻辑手机窗口持有的物理尺寸租约，跨捕获代次保留原覆盖与恢复责任。
///
/// 取消只撤销新修改；关闭先等待当前写入，再请求远端恢复。断流、原进程退出
/// 和本机服务关闭都不能代替恢复回执，丢失回执时使用远端持久记录重试核验。
final class PhysicalDisplayLease {
  PhysicalDisplayLease(this.connection, {required this.timeout, this.onLost});

  final DeviceConnection connection;
  final Duration timeout;
  final void Function()? onLost;
  final String _owner = _newOwner();
  AdbServiceSession? _service;
  Future<void>? _reading;
  Future<void> _tail = Future.value();
  Future<void>? _closing, _detaching;
  Completer<void> _changed = Completer<void>();
  Object? _readFailure;
  ({int pid, int started})? _identity;
  ({int width, int height})? _size;
  String? _lastReply, _restoration;
  bool _acknowledged = false;
  bool _started = false, _startAttempted = false, _runAttempted = false;
  bool _readerFinished = false, _revoked = false, _closed = false;
  bool _detachRequested = false;
  PhysicalDisplayCommand? _finishing;
  bool _lostReported = false;
  int _sequence = 0;

  ({int width, int height})? get size => _size;
  String? get restoration => _restoration;
  bool get isClosed => _closed;

  Future<void> start(
    int width,
    int height, {
    required AdbCancellation cancellation,
  }) {
    _validate(width, height);
    if (_started || _revoked) _fail('display_closed', '显示租约已经启动或撤销。');
    _started = true;
    return _serial(() async {
      cancellation.check();
      // 创建不绑定取消：迟到服务必须先交给此租约，随后才能精确关闭。
      final service = await connection.client.services.exec(
        connection.device,
        physicalDisplayBootstrap,
        timeout: const Duration(days: 1),
      );
      _service = service;
      _reading = _read(service);
      _check(cancellation);
      await _writeProgram(
        service,
        physicalDisplayProgram(owner: _owner, width: width, height: height),
      );
      _check(cancellation);
      _startAttempted = true;
      await _write('START:$_owner');
      await _wait(() => _identity != null, cancellation);
      _check(cancellation);
      // 先持有远端精确身份，才允许首个 wm。写入失败也保留可能已交付的授权。
      _runAttempted = true;
      await _write('RUN:$_owner');
      await _wait(() => _lastReply == 'READY:$width:$height', cancellation);
      _size = (width: width, height: height);
    });
  }

  Future<void> resize(
    int width,
    int height, {
    required AdbCancellation cancellation,
  }) {
    _validate(width, height);
    if (!_started || _revoked) _fail('display_closed', '显示租约未启动或已经撤销。');
    return _serial(() async {
      _check(cancellation);
      if (_size == null || _restoration != null) {
        _fail('display_unverified', '物理尺寸尚未确认，不能继续调整。');
      }
      _lastReply = null;
      final sequence = ++_sequence;
      await _write('RESIZE:$_owner:$sequence:$width:$height');
      await _wait(
        () => _lastReply == 'SIZE:$sequence:$width:$height',
        cancellation,
      );
      _size = (width: width, height: height);
    });
  }

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _check(AdbCancellation cancellation) {
    cancellation.check();
    if (_revoked) _fail('cancelled', '显示租约已撤销新修改。');
  }

  void _notify() {
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }

  Future<void> _wait(
    bool Function() received,
    AdbCancellation cancellation,
  ) async {
    final detach = cancellation.onCancel(_notify);
    var expired = false;
    final timer = Timer(timeout, () {
      expired = true;
      _notify();
    });
    try {
      while (true) {
        final changed = _changed.future;
        _check(cancellation);
        if (expired) {
          _fail('display_result_unknown', '显示修改确认超时，仍保留原租约供停止核验。');
        }
        if (_readFailure != null || _readerFinished || _restoration != null) {
          _fail(
            'display_result_unknown',
            '没有收到本次显示修改的完整确认：${_readFailure ?? '监督器已结束'}',
          );
        }
        if (received()) return;
        await changed;
      }
    } finally {
      timer.cancel();
      detach();
    }
  }

  Future<void> _write(String line) async {
    final service = _service;
    if (service == null) _fail('display_unverified', '显示监督流尚未交付。');
    await service.write(Uint8List.fromList(utf8.encode('$line\n')));
  }

  Future<void> _read(AdbServiceSession service) async {
    final line = <int>[];
    var discarded = false;
    try {
      await for (final event in service.events) {
        for (final byte in event.bytes) {
          if (byte == 10) {
            if (!discarded) {
              _receipt(utf8.decode(line, allowMalformed: true).trimRight());
            }
            line.clear();
            discarded = false;
          } else if (!discarded) {
            line.add(byte);
            if (line.length > 8192) {
              // 远端诊断不阻塞恢复回执，也不能将超长行后缀误认为完整回执。
              line.clear();
              discarded = true;
            }
          }
        }
      }
    } catch (error) {
      _readFailure = error;
    } finally {
      _readerFinished = true;
      _notify();
      _reportLost();
    }
  }

  void _receipt(String line) {
    final owner = RegExp('^__DISPLAY_OWNER__$_owner:([0-9]+):([0-9]+)\$')
        .firstMatch(line);
    if (owner != null) {
      final pid = int.tryParse(owner[1]!), started = int.tryParse(owner[2]!);
      if (pid == null || pid <= 1 || started == null || started <= 0) return;
      final identity = (pid: pid, started: started);
      if (_identity != null && _identity != identity) {
        _readFailure = StateError('显示监督器返回了冲突身份。');
      } else {
        _identity = identity;
      }
    }
    for (final type in ['READY', 'SIZE']) {
      final prefix = '__DISPLAY_${type}__$_owner:';
      if (line.startsWith(prefix) && _runAttempted) {
        final dimensions = line.substring(prefix.length);
        if ((type == 'READY'
                ? RegExp(r'^[0-9]+:[0-9]+$')
                : RegExp(r'^[0-9]+:[0-9]+:[0-9]+$'))
            .hasMatch(dimensions)) {
          _lastReply = '$type:$dimensions';
        }
      }
    }
    final prefix = '__DISPLAY_DONE__$_owner:';
    if (line == '${prefix}restored' || line == '${prefix}preserved') {
      _restoration = line.substring(prefix.length);
      _reportLost();
    }
    if (line == '__DISPLAY_ACK__$_owner') _acknowledged = true;
    _notify();
  }

  void _reportLost() {
    if (_revoked || !_runAttempted || _lostReported) return;
    _lostReported = true;
    try {
      onLost?.call();
    } catch (error) {
      _readFailure ??= error;
    }
  }

  /// 捕获退出后调用。失败保留同一服务及远端 owner，后续调用沿原责任重试。
  Future<void> close() {
    if (_closed) return Future.value();
    if (_detachRequested) return detachClosedConnection();
    if (_closing case final pending?) return pending;
    _revoked = true;
    _notify();
    final result = () async {
      await _tail;
      await _finishing?.close();
      _finishing = null;
      final service = _service;
      if (service != null) {
        if (!_detachRequested &&
            _startAttempted &&
            !_readerFinished &&
            _restoration == null) {
          try {
            await _write('STOP:$_owner');
            await _waitRestoration();
          } catch (_) {
            // 流写入或回执失败只转入精确恢复检查，不能提前投影为已经恢复。
          }
        }
        await service.close();
        await _reading;
      }
      if (!_detachRequested &&
          (_runAttempted || _identity != null) &&
          _restoration == null) {
        // 恢复程序同样通过短 bootstrap 注入，兼容旧 adbd 的 OPEN 负载上限。
        await _finishProgram(
          recoverPhysicalDisplayCommand(_owner),
          () => _restoration != null,
        );
        if (_restoration == null) {
          _fail('display_cleanup_unconfirmed', '物理尺寸恢复尚未确认，保留原租约供重试。');
        }
      }
      if (!_detachRequested && _restoration != null && !_acknowledged) {
        // 只有 Dart 已持有恢复证明后才能删除远端终态；ACK 丢失可沿同 owner 重试。
        await _finishProgram(
          acknowledgePhysicalDisplayCommand(_owner),
          () => _acknowledged,
        );
        if (!_acknowledged) {
          _fail('display_cleanup_unconfirmed', '显示已恢复，远端租约记录尚未确认释放。');
        }
      }
      _closed = true;
    }();
    return _closing = result.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// 捕获实际关闭后才可调用。只在此精确连接的 closed 事实成立时释放本机责任。
  ///
  /// 不发恢复或 ACK、不设置 restoration；远端 current 留给后继已核验连接的
  /// 准入恢复。迟到创建、原写入及关闭失败仍保留在本租约，下一次调用可重试。
  Future<void> detachClosedConnection() {
    if (_closed) return Future.value();
    if (_detaching case final pending?) return pending;
    _revoked = true;
    _notify();
    final result = () async {
      await _tail;
      final facts = await connection.client.services.connectionFacts(
        connection.device,
      );
      if (!facts.closed) {
        _fail('display_cleanup_unconfirmed', '连接尚未确认关闭，不能延期远端显示恢复。');
      }
      _detachRequested = true;
      _notify();
      // 正常 close 可能已在等待恢复命令；精确关闭该命令以唤醒它，不能另起 helper。
      await _finishing?.close();
      if (_closing case final pending?) {
        try {
          await pending;
        } catch (_) {
          // 关闭期间的远端回执失败不再由死连接重播；下方仍逐项核验本机释放。
        }
      }
      await _finishing?.close();
      _finishing = null;
      await _service?.close();
      await _reading;
      _closed = true;
    }();
    return _detaching = result.catchError((Object error, StackTrace stack) {
      _detaching = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _finishProgram(String program, bool Function() received) async {
    if (_detachRequested) _fail('display_closed', '显示租约仅允许排空本机资源。');
    final command = PhysicalDisplayCommand(connection, timeout: timeout);
    _finishing = command;
    await command.run(
      program,
      onLine: (line) {
        _receipt(line);
        return received();
      },
    );
    _finishing = null;
  }

  Future<void> _writeProgram(AdbServiceSession service, String program) async {
    final bytes = Uint8List.fromList(
      utf8.encode('$program\n__INTEROP_DISPLAY_PROGRAM_END__\n'),
    );
    for (var offset = 0; offset < bytes.length; offset += 65536) {
      final end = min(offset + 65536, bytes.length);
      await service.write(Uint8List.sublistView(bytes, offset, end));
    }
  }

  Future<void> _waitRestoration() async {
    var expired = false;
    final timer = Timer(timeout, () {
      expired = true;
      _notify();
    });
    try {
      while (_restoration == null &&
          !_readerFinished &&
          !_detachRequested &&
          !expired) {
        await _changed.future;
      }
    } finally {
      timer.cancel();
    }
  }
}

void _validate(int width, int height) {
  if (width < 320 || width > 4096 || height < 320 || height > 4096) {
    _fail('invalid_argument', '手机显示宽高必须在 320 到 4096 像素之间。');
  }
}

String _newOwner() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Never _fail(String code, String message) =>
    throw ApplicationCommandException(code, message);
