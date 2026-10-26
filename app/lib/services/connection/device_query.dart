import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';

import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

/// 有界设备文本查询，共用旧版 shell 与 shell v2 的退出、取消及解码规则。
/// 只收集 stdout；stderr 同样计入预算，不把错误信息当作设备属性。
/// 调用方负责固定命令或参数转义，并在接纳结果前核对实际连接代次。
Future<String> readDeviceText(
  DeviceConnection connection,
  String command, {
  AdbCancellation? cancellation,
  Duration timeout = const Duration(seconds: 5),
  int maxBytes = 256 * 1024,
}) async {
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  cancellation?.check();
  adbTimeoutMillis(timeout);
  final ({Uint8List stdout, Uint8List stderr, int? exitCode}) result;
  try {
    result = await readDeviceShell(
      connection,
      command,
      cancellation: cancellation,
      timeout: timeout,
      maxBytes: maxBytes,
      onExit: (code) {
        if (code != null && code != 0) {
          throw const ApplicationCommandException(
            'query_unavailable',
            '目标设备未能提供此项数据。',
          );
        }
      },
    );
  } on ApplicationCommandException catch (error) {
    if (error.code != 'result_unknown') rethrow;
    throw const ApplicationCommandException('query_unavailable', '设备查询在完成前中断。');
  }
  try {
    return utf8.decode(result.stdout);
  } on FormatException {
    throw const ApplicationCommandException('invalid_data', '设备数据不是有效的 UTF-8。');
  }
}

/// 收集有界 shell 字节并核验完整终态；退出码和文字解码政策由调用者决定。
Future<({Uint8List stdout, Uint8List stderr, int? exitCode})> readDeviceShell(
  DeviceConnection connection,
  String command, {
  required Duration timeout,
  required int maxBytes,
  AdbCancellation? cancellation,
  void Function(int?)? onExit,
}) async {
  final stdout = BytesBuilder(copy: false), stderr = BytesBuilder(copy: false);
  var count = 0, terminal = false;
  int? exitCode;
  await for (final event in connection.client.shell(
    connection.device,
    command,
    cancellation: cancellation,
    timeout: timeout,
  )) {
    cancellation?.check();
    if (terminal) {
      throw const ApplicationCommandException(
        'invalid_data',
        '设备命令在终态后继续返回数据。',
      );
    }
    count += event.bytes.length;
    if (count > maxBytes) {
      throw const ApplicationCommandException('byte_limit', '设备命令输出超过本次限额。');
    }
    switch (event.channel) {
      case AdbShellChannel.stdout:
        stdout.add(event.bytes);
      case AdbShellChannel.stderr:
        stderr.add(event.bytes);
      case AdbShellChannel.exit:
        if (event.bytes.isNotEmpty) {
          throw const ApplicationCommandException(
            'invalid_data',
            '设备退出回执包含无效字节。',
          );
        }
        exitCode = event.exitCode;
        onExit?.call(exitCode);
        terminal = true;
    }
  }
  cancellation?.check();
  if (!terminal) {
    throw const ApplicationCommandException('result_unknown', '设备命令没有返回完整终态。');
  }
  return (
    stdout: stdout.takeBytes(),
    stderr: stderr.takeBytes(),
    exitCode: exitCode,
  );
}
