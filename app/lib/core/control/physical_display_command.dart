import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/control/physical_display_script.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 一次显示恢复或确认命令拥有的精确原始流。
///
/// 命令只执行一次；失败后调用方必须保留本对象，重试 [close] 确认释放后
/// 才能创建下一次命令。完整回执不能替代本机流关闭，关闭也不代表显示恢复。
final class PhysicalDisplayCommand {
  PhysicalDisplayCommand(this.connection, {required this.timeout});

  final DeviceConnection connection;
  final Duration timeout;
  final Completer<void> _created = Completer<void>();
  AdbServiceSession? _service;
  Future<void>? _reading, _closing;
  Future<void> _writes = Future.value();
  Completer<void> _changed = Completer<void>();
  Object? _readFailure;
  bool _started = false, _finished = false, _received = false;
  bool _closeRequested = false, _closed = false;

  /// [onLine] 只在完整有界行上调用，返回 true 表示收到本命令的精确终态。
  /// 回调可先保存发现的 owner，再通过 [writeLine] 授权同一远端流恢复。
  Future<void> run(
    String program, {
    required FutureOr<bool> Function(String line) onLine,
    AdbCancellation? cancellation,
  }) async {
    if (_started || _closeRequested) throw StateError('显示命令已执行或关闭。');
    _started = true;
    final detach = cancellation?.onCancel(_notify);
    var expired = false;
    final timer = Timer(timeout, () {
      expired = true;
      _notify();
    });
    try {
      try {
        // 不将取消绑定到创建：迟到交付也必须先登记精确流再关闭。
        _service = await connection.client.services.exec(
          connection.device,
          physicalDisplayBootstrap,
          timeout: timeout,
        );
        _reading = _read(_service!, onLine);
      } finally {
        _created.complete();
      }
      cancellation?.check();
      if (_closeRequested || expired) _unknown();
      final bytes = Uint8List.fromList(
        utf8.encode('$program\n__INTEROP_DISPLAY_PROGRAM_END__\n'),
      );
      try {
        for (var offset = 0; offset < bytes.length; offset += 65536) {
          cancellation?.check();
          if (_closeRequested || expired) _unknown();
          await _write(
            Uint8List.sublistView(
              bytes,
              offset,
              min(offset + 65536, bytes.length),
            ),
          );
        }
      } catch (_) {
        // 最后一块可已交付；继续读取完整回执，不能凭写入异常猜测执行结果。
      }
      while (true) {
        final changed = _changed.future;
        cancellation?.check();
        if (_closeRequested || expired) _unknown();
        if (_finished) {
          if (_received && _readFailure == null) return;
          _unknown();
        }
        await changed;
      }
    } finally {
      timer.cancel();
      detach?.call();
      await close();
    }
  }

  Future<void> writeLine(String line) async {
    if (_closeRequested) throw StateError('显示命令已撤销写入。');
    await _write(Uint8List.fromList(utf8.encode('$line\n')));
  }

  Future<void> _write(Uint8List bytes) {
    // 远端回执可早于前一块 write 的 await 返回；同一流仍只允许一个写者。
    final result = _writes.then((_) async {
      if (_closeRequested) throw StateError('显示命令已撤销写入。');
      await _service!.write(bytes);
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _read(
    AdbServiceSession service,
    FutureOr<bool> Function(String) onLine,
  ) async {
    final line = <int>[];
    var discarded = false;
    try {
      await for (final event in service.events) {
        for (final byte in event.bytes) {
          if (byte == 10) {
            if (!discarded) {
              try {
                if (await onLine(
                  utf8.decode(line, allowMalformed: true).trimRight(),
                )) {
                  _received = true;
                }
              } catch (error) {
                // 保留错误但继续 drain；诊断或授权失败之后仍可能有完整 DONE。
                _readFailure ??= error;
              }
            }
            line.clear();
            discarded = false;
            _notify();
          } else if (!discarded) {
            line.add(byte);
            if (line.length > 8192) {
              line.clear();
              discarded = true;
            }
          }
        }
      }
    } catch (error) {
      _readFailure ??= error;
    } finally {
      _finished = true;
      _notify();
    }
  }

  void _notify() {
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }

  /// 同步撤写入准入，随后等迟到创建及精确流真正释放。失败保留同一流供重试。
  Future<void> close() {
    if (_closed) return Future.value();
    if (_closing case final pending?) return pending;
    _closeRequested = true;
    _notify();
    final result = () async {
      if (_started) await _created.future;
      await _service?.close();
      await _writes;
      await _reading;
      _closed = true;
    }();
    return _closing = result.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Never _unknown() => throw RequestFailure(
    'display_cleanup_unconfirmed',
    '显示命令尚无完整终态：${_readFailure ?? '回执缺失或等待超时'}',
  );
}
