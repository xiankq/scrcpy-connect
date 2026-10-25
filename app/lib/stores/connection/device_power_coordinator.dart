import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/models/device_record.dart';

/// 一次明确唤醒及其精确 shell 资源；连接、窗口和重试意图仍由各自所有者持有。
/// 成功仅证明命令取得退出码 0，不证明实体屏幕已亮或设备已解锁。
final class DevicePowerCoordinator {
  DevicePowerCoordinator({
    required this.requireConnection,
    this.timeout = const Duration(seconds: 5),
  }) {
    adbTimeoutMillis(timeout);
  }

  final DeviceConnection Function(String) requireConnection;
  final Duration timeout;
  final _requests = <_WakeRequest>{};
  final _retired = Expando<bool>();
  bool _closed = false;
  Future<void>? _closing;

  bool handles(String command) => command == 'devices.wake';

  Future<Map<String, Object?>> command(
    String name,
    Map<String, Object?> params, {
    AdbCancellation? cancellation,
  }) {
    if (_closed) {
      throw const ApplicationCommandException('disposed', '设备唤醒已停止。');
    }
    if (!handles(name)) {
      throw const ApplicationCommandException('unknown_command', '未知设备电源操作。');
    }
    final id = params['deviceId'];
    if (id is! String || !validDeviceId(id)) {
      throw const ApplicationCommandException('invalid_device_id', '设备记录标识无效。');
    }
    final expected = params['connectionId'];
    if (expected != null && (expected is! String || expected.isEmpty)) {
      throw const ApplicationCommandException(
        'invalid_connection_id',
        '设备连接标识无效。',
      );
    }
    if (cancellation?.isCancelled == true) {
      throw const ApplicationCommandException('cancelled', '本次唤醒已取消。');
    }
    final request = _WakeRequest(id, requireConnection(id));
    _assertCurrent(request);
    if (_requests.any(
      (previous) =>
          identical(previous.connection, request.connection) &&
          previous.done.isCompleted &&
          !previous.released,
    )) {
      throw const ApplicationCommandException(
        'wake_cleanup_unconfirmed',
        '上次唤醒资源尚未确认释放，请先重试断开，不能重复发送。',
      );
    }
    // 在首次异步读取之前登记；停止必须等待迟到创建和实际 shell 关闭。
    _requests.add(request);
    final unwatch = cancellation?.onCancel(request.cancel);
    return _run(
      request,
      expected as String?,
    ).whenComplete(() => unwatch?.call());
  }

  void _assertCurrent(_WakeRequest request) {
    if (_closed || request.cancellation.isCancelled) {
      throw const ApplicationCommandException('cancelled', '本次唤醒已取消，不能自动重放。');
    }
    DeviceConnection current;
    try {
      current = requireConnection(request.deviceId);
    } on ApplicationCommandException catch (error) {
      if (error.code != 'disconnected') rethrow;
      _stale();
    }
    if (_retired[request.connection] == true ||
        !identical(current, request.connection)) {
      _stale();
    }
  }

  Future<AdbConnectionFacts> _facts(_WakeRequest request) async {
    _assertCurrent(request);
    final connection = request.connection;
    final facts = await connection.client.services.connectionFacts(
      connection.device,
    );
    _assertCurrent(request);
    if (facts.closed ||
        facts.connectionId == null ||
        facts.connectionId!.isEmpty) {
      _stale();
    }
    return facts;
  }

  Future<Map<String, Object?>> _run(
    _WakeRequest request,
    String? expected,
  ) async {
    try {
      final before = await _facts(request);
      if (expected != null && expected != before.connectionId) _stale();
      _assertCurrent(request);
      // 发送前按实际协商能力选定唯一路径；发送后的失败不切换协议或重放。
      final v2 = before.features.contains('shell_v2');
      final nonce = v2 ? null : _nonce();
      // 创建已受理后取消不承诺命令未发送。等待精确句柄交付，再登记和关闭它；
      // 不把取消交给创建后的 SDK 检查，避免关闭失败时调用方拿不到迟到句柄。
      final services = request.connection.client.services;
      request.session = v2
          ? await services.shell(
              request.connection.device,
              'input keyevent KEYCODE_WAKEUP',
              maxPacket: 8192,
              timeout: timeout,
            )
          : await services.open(
              request.connection.device,
              // 先保存 input 的真实退出状态；echo 是旧 Android shell 的内建命令。
              // 标记只含本次随机 ASCII，不拼接用户输入，也不依赖外部 printf。
              "shell:input keyevent KEYCODE_WAKEUP; __wake_status=\$?; echo; echo '$nonce:'\"\$__wake_status\"",
              timeout: timeout,
            );
      _assertCurrent(request);
      var bytes = 0;
      var terminal = false;
      final legacyOutput = BytesBuilder(copy: false);
      await for (final event in request.session!.events) {
        _assertCurrent(request);
        bytes += event.bytes.length;
        if (bytes > 8192) {
          throw const ApplicationCommandException(
            'byte_limit',
            '唤醒命令输出超过限额，结果尚未确认。',
          );
        }
        if (terminal) {
          throw const ApplicationCommandException(
            'invalid_data',
            '唤醒命令返回了无效回执。',
          );
        }
        if (!v2) {
          if (event.kind == 'data' && !event.done) {
            legacyOutput.add(event.bytes);
          } else if (event.kind == 'end' && event.done && event.bytes.isEmpty) {
            // 原始服务的 end 表示远端 EOF；单独的尾部标记不能代替完整收尾。
            terminal = true;
          } else {
            throw const ApplicationCommandException(
              'result_unknown',
              '旧式唤醒通道没有返回完整 EOF，不能确认命令完成。',
            );
          }
          continue;
        }
        if (!const {'stdout', 'stderr', 'exit'}.contains(event.kind)) {
          throw const ApplicationCommandException(
            'invalid_data',
            '唤醒命令返回了无效回执。',
          );
        }
        if (event.kind == 'exit') {
          if (!event.done || event.bytes.isNotEmpty) {
            throw const ApplicationCommandException(
              'invalid_data',
              '唤醒退出回执不完整。',
            );
          }
          if (event.exitCode == null) {
            throw const ApplicationCommandException(
              'result_unknown',
              '设备未提供退出码，不能确认唤醒命令完成。',
            );
          }
          if (event.exitCode != 0) {
            throw ApplicationCommandException('wake_failed', '设备拒绝执行唤醒命令。', {
              'exitCode': event.exitCode,
            });
          }
          terminal = true;
        } else if (event.done) {
          throw const ApplicationCommandException(
            'result_unknown',
            '唤醒命令缺少退出回执。',
          );
        }
      }
      if (!terminal) {
        throw const ApplicationCommandException(
          'result_unknown',
          '唤醒命令未返回明确终态，不能自动重放。',
        );
      }
      if (nonce != null) {
        final status = _legacyStatus(legacyOutput.takeBytes(), nonce);
        if (status != 0) {
          throw ApplicationCommandException('wake_failed', '设备拒绝执行唤醒命令。', {
            'exitCode': status,
          });
        }
      }
      await request.release();
      final after = await _facts(request);
      if (after.connectionId != before.connectionId ||
          after.configuredIdentity?.fingerprint !=
              before.configuredIdentity?.fingerprint) {
        _stale();
      }
      return {
        'deviceId': request.deviceId,
        'connectionId': before.connectionId,
        'commandCompleted': true,
        'exitCode': 0,
        'evidence': v2 ? 'shell_exit_success' : 'legacy_shell_exit_success',
        'screenStateVerified': false,
        'screenOn': null,
        'locked': null,
      };
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(error.code, error.message),
        stack,
      );
    } finally {
      try {
        await request.release();
      } finally {
        request.done.complete();
        if (request.released) _requests.remove(request);
      }
    }
  }

  /// 调用即撤销此旧连接的唤醒准入；不关闭共享 Client 或任何连接。
  /// 失败保留精确 shell，后续调用只重试关闭，不重放 WAKEUP。
  Future<void> stopConnection(String deviceId, DeviceConnection connection) {
    _retired[connection] = true;
    return _drain(
      _requests
          .where(
            (request) =>
                request.deviceId == deviceId &&
                identical(request.connection, connection),
          )
          .toList(),
    );
  }

  Future<void> _drain(List<_WakeRequest> requests) async {
    for (final request in requests) {
      request.cancel();
    }
    await Future.wait(
      requests.map((request) async {
        await request.done.future;
        await request.release();
        _requests.remove(request);
      }),
    );
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    final closing = _drain(_requests.toList())
        .catchError((Object error, StackTrace stack) {
          _closing = null;
          Error.throwWithStackTrace(error, stack);
        });
    return _closing = closing;
  }
}

String _nonce() {
  final random = Random.secure();
  return 'SCRCPY_WAKE_${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

int _legacyStatus(Uint8List output, String nonce) {
  // 单字节解码保留命令输出的任意原始字节；只有精确 ASCII 尾部承担退出证明。
  final text = latin1.decode(output);
  final match = RegExp('\n${RegExp.escape(nonce)}:(0|[1-9][0-9]{0,2})\r?\n\$')
      .firstMatch(text);
  final status = match == null ? null : int.tryParse(match[1]!);
  if (match == null ||
      match.end != text.length ||
      status == null ||
      status > 255 ||
      text.indexOf(nonce) != match.start + 1 ||
      text.lastIndexOf(nonce) != match.start + 1) {
    throw const ApplicationCommandException(
      'result_unknown',
      '旧式唤醒缺少本次完整退出回执，不能自动重放。',
    );
  }
  return status;
}

final class _WakeRequest {
  _WakeRequest(this.deviceId, this.connection);
  final String deviceId;
  final DeviceConnection connection;
  final cancellation = AdbCancellation();
  final done = Completer<void>();
  AdbServiceSession? session;
  bool _released = false;
  bool get released => session == null || _released;

  void cancel() {
    cancellation.cancel();
    if (session != null) unawaited(release().catchError((Object _) {}));
  }

  Future<void> release() async {
    if (session == null || _released) return;
    try {
      await session!.close();
      _released = true;
    } catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(
          'wake_cleanup_unconfirmed',
          '唤醒操作资源尚未确认释放，请重试清理。',
          {'cause': '$error'},
        ),
        stack,
      );
    }
  }
}

Never _stale() => throw const ApplicationCommandException(
  'stale_connection',
  '唤醒请求所属连接已变化，请核对当前画面。',
);
