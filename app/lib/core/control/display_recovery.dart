import 'dart:async';
import 'dart:math';

import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/control/physical_display_command.dart';
import 'package:scrcpy_connect/core/control/physical_display_script.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 跨 isolate 恢复遗留物理显示的应用所有者。
///
/// 调用方必须先排空旧捕获或完成新连接身份核验；本模块不会停止正常活动窗口。
/// 发现 owner 后责任固定于该 owner；失败保留精确流和阶段，不能改为恢复后继。
final class DisplayRecovery {
  DisplayRecovery({required this.timeout});

  final Duration timeout;
  final _entries = Map<DeviceConnection, _RecoveryEntry>.identity();
  bool _closing = false;

  Future<void> recover(
    DeviceConnection connection, {
    AdbCancellation? cancellation,
  }) {
    if (_closing) return Future.error(StateError('显示恢复所有者已关闭。'));
    final entry = _entries.putIfAbsent(connection, _RecoveryEntry.new);
    if (entry.stopping) return Future.error(StateError('该连接已经撤销恢复准入。'));
    return entry.serial(() async {
      cancellation?.check();
      if (entry.stopping) throw StateError('该连接已经撤销恢复准入。');
      final stop = AdbCancellation();
      entry.active = stop;
      final detach = cancellation?.onCancel(stop.cancel);
      try {
        await _recover(connection, entry, stop);
      } catch (error) {
        // 保留调用方的取消；连接所有者仍须完成 stopForConnection，
        // 未确认的恢复或流清理会由该屏障继续报告失败。
        if (cancellation?.isCancelled == true &&
            error is AdbException &&
            error.code == 'cancelled') {
          rethrow;
        }
        _unknown('物理显示恢复尚未结清：$error');
      } finally {
        detach?.call();
        entry.active = null;
      }
    });
  }

  Future<void> _recover(
    DeviceConnection connection,
    _RecoveryEntry entry,
    AdbCancellation cancellation,
  ) async {
    // 先重试原流关闭；即使已收到 DONE，也不能越过失败的本机释放责任。
    await entry.command?.close();
    entry.command = null;
    cancellation.check();
    if (entry.detaching) _unknown('已断开连接仅允许排空本机显示流。');
    if (entry.complete) return;
    if (!entry.restored) {
      final command = PhysicalDisplayCommand(connection, timeout: timeout);
      entry.command = command;
      final discovery = entry.owner == null;
      final request = entry.request;
      var empty = false;
      await command.run(
        discovery
            ? recoverCurrentPhysicalDisplayCommand(request)
            : recoverPhysicalDisplayCommand(entry.owner!),
        cancellation: cancellation,
        onLine: (line) async {
          if (discovery) {
            final prefix = '__DISPLAY_CURRENT__$request:';
            if (line.startsWith(prefix)) {
              final owner = line.substring(prefix.length);
              if (owner == 'empty') {
                if (entry.owner != null) _unknown('发现回执与已知 owner 冲突。');
                empty = true;
                return true;
              }
              if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(owner)) {
                _unknown('发现回执的 owner 格式错误。');
              }
              if (entry.owner != null && entry.owner != owner) {
                _unknown('发现回执试图替换原恢复责任。');
              }
              entry.owner = owner;
              cancellation.check();
              // 先固定责任，再允许远端在原 gate 下执行恢复。
              await command.writeLine('RECOVER:$request:$owner');
            }
          }
          final owner = entry.owner;
          if (owner != null &&
              (line == '__DISPLAY_DONE__$owner:restored' ||
                  line == '__DISPLAY_DONE__$owner:preserved')) {
            entry.restored = true;
            return true;
          }
          return false;
        },
      );
      entry.command = null;
      if (empty) entry.complete = true;
    }
    cancellation.check();
    if (entry.complete) return;
    if (!entry.restored || entry.owner == null) _unknown('原物理覆盖恢复尚未确认。');
    final command = PhysicalDisplayCommand(connection, timeout: timeout);
    entry.command = command;
    await command.run(
      acknowledgePhysicalDisplayCommand(entry.owner!),
      cancellation: cancellation,
      onLine: (line) {
        if (line != '__DISPLAY_ACK__${entry.owner}') return false;
        return true;
      },
    );
    entry.command = null;
    entry.complete = true;
  }

  /// 先同步撤销此精确连接的新恢复，再排空在途命令并沿原 owner 完成恢复。
  /// 清理失败保留原对象，下一次调用重试，不触碰其他连接或共享服务。
  Future<void> stopForConnection(DeviceConnection connection) {
    final entry = _entries[connection];
    if (entry == null) return Future.value();
    if (entry.detaching) return detachClosedConnection(connection);
    entry.stopping = true;
    entry.active?.cancel();
    return entry.serial(() async {
      try {
        await _recover(connection, entry, AdbCancellation());
      } catch (error) {
        _unknown('物理显示恢复尚未结清：$error');
      }
      if (identical(_entries[connection], entry)) _entries.remove(connection);
    });
  }

  /// 捕获排空后退休精确连接的恢复责任；已断开的连接只释放本机命令。
  Future<void> retireConnection(DeviceConnection connection) async {
    final entry = _entries[connection];
    if (entry == null) return;
    entry.stopping = true;
    entry.active?.cancel();
    if ((await connection.client.services.connectionFacts(connection.device))
        .closed) {
      await detachClosedConnection(connection);
      return;
    }
    try {
      await stopForConnection(connection);
    } catch (_) {
      if (!(await connection.client.services.connectionFacts(connection.device))
          .closed) {
        rethrow;
      }
      await detachClosedConnection(connection);
    }
  }

  /// 仅在调用方已核验精确物理连接 closed 且捕获排空后使用。
  ///
  /// 本方法不发恢复或 ACK，也不宣称远端恢复；持久 current 必须由下一条
  /// 已核验连接的恢复屏障处理。迟到服务及关闭失败仍由原 entry 保留并重试。
  Future<void> detachClosedConnection(DeviceConnection connection) {
    final entry = _entries[connection];
    if (entry == null) return Future.value();
    entry.stopping = true;
    entry.detaching = true;
    entry.active?.cancel();
    return entry.serial(() async {
      try {
        await entry.command?.close();
      } catch (error) {
        _unknown('断开连接的显示命令尚未释放：$error');
      }
      entry.command = null;
      if (identical(_entries[connection], entry)) _entries.remove(connection);
    });
  }

  Future<void> close() async {
    _closing = true;
    Object? failure;
    StackTrace? failureStack;
    for (final connection in _entries.keys.toList()) {
      try {
        await stopForConnection(connection);
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}

final class _RecoveryEntry {
  final String request = _nonce();
  String? owner;
  PhysicalDisplayCommand? command;
  AdbCancellation? active;
  bool restored = false, complete = false, stopping = false, detaching = false;
  Future<void> _tail = Future.value();

  Future<void> serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

String _nonce() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

Never _unknown(String message) =>
    throw RequestFailure('display_recovery_unconfirmed', message);
