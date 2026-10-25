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
  final output = BytesBuilder(copy: false);
  var bytes = 0;
  var exited = false;
  // 等待流的 finally 完成，让 SDK 的超时与取消完成实际命令回收。
  await for (final event in connection.client.shell(
    connection.device,
    command,
    timeout: timeout,
    cancellation: cancellation,
  )) {
    cancellation?.check();
    if (exited) {
      throw const ApplicationCommandException(
        'invalid_data',
        '设备查询在终态后继续返回数据。',
      );
    }
    bytes += event.bytes.length;
    if (bytes > maxBytes) {
      throw const ApplicationCommandException('byte_limit', '设备查询输出超过允许的字节限额。');
    }
    switch (event.channel) {
      case AdbShellChannel.stdout:
        output.add(event.bytes);
      case AdbShellChannel.stderr:
        break;
      case AdbShellChannel.exit:
        if (event.bytes.isNotEmpty) {
          throw const ApplicationCommandException(
            'invalid_data',
            '设备查询退出回执无效。',
          );
        }
        if (event.exitCode != null && event.exitCode != 0) {
          throw const ApplicationCommandException(
            'query_unavailable',
            '目标设备未能提供此项数据。',
          );
        }
        exited = true;
    }
  }
  cancellation?.check();
  if (!exited) {
    throw const ApplicationCommandException('query_unavailable', '设备查询在完成前中断。');
  }
  try {
    return utf8.decode(output.takeBytes());
  } on FormatException {
    throw const ApplicationCommandException('invalid_data', '设备数据不是有效的 UTF-8。');
  }
}
