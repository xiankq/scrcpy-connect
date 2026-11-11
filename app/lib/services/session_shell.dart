import 'package:scrcpy_connect/models/device_connection.dart';
import 'package:scrcpy_connect/models/session_shell_result.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:scrcpy_connect/services/device_query.dart';
import 'package:adb/adb.dart';
import 'package:scrcpy_connect/models/application_request.dart';

/// 固定的设备查询与任务操作；等待 SDK 流结束，不用 Future.timeout 丢弃执行。
final class SessionShell {
  const SessionShell(this.connection, this.timeout);
  final DeviceConnection connection;
  final Duration timeout;

  Future<SessionShellResult> run(
    String command, {
    AdbCancellation? cancellation,
    int maxBytes = 262144,
    bool requireExitCode = true,
    bool requireSuccess = true,
  }) async {
    final result = await readDeviceShell(
      connection,
      command,
      cancellation: cancellation,
      timeout: timeout,
      maxBytes: maxBytes,
    );
    final exitCode = result.exitCode;
    if (requireSuccess && exitCode != null && exitCode != 0) {
      _fail('shell_failed', '系统报告设备命令执行失败。');
    }
    // 旧版 shell 没有退出码；只读查询仍须完整终态，并由调用方核验内容。
    // 修改设备状态的命令必须取得可核实的成功码。
    if (requireExitCode && exitCode == null) {
      _fail('result_unknown', '设备没有提供退出码，无法确认命令成功。');
    }
    try {
      return SessionShellResult(
        utf8.decode(result.stdout),
        utf8.decode(result.stderr),
        exitCode,
      );
    } on FormatException {
      _fail('invalid_data', '设备命令返回了无效 UTF-8。');
    }
  }

  Future<({int width, int height, int density})> metrics(
    AdbCancellation stop,
  ) async {
    final result = await run(
      'wm size; wm density',
      cancellation: stop,
      maxBytes: 8192,
      requireExitCode: false,
    );
    int? width, height, density;
    for (final line in const LineSplitter().convert(result.stdout)) {
      final size = RegExp(r'^(?:Physical|Override) size: (\d+)x(\d+)$')
          .firstMatch(line.trim());
      if (size != null) {
        width = int.tryParse(size[1]!);
        height = int.tryParse(size[2]!);
      }
      final dpi = RegExp(r'^(?:Physical|Override) density: (\d+)$')
          .firstMatch(line.trim());
      if (dpi != null) density = int.tryParse(dpi[1]!);
    }
    if (width == null ||
        height == null ||
        density == null ||
        width <= 0 ||
        height <= 0 ||
        density <= 0) {
      _fail('display_metrics_unavailable', '无法核实手机屏幕尺寸和密度，未更改独立窗口。');
    }
    return (width: width, height: height, density: density);
  }

  Future<int> task(String package, int display, AdbCancellation stop) async {
    final result = await run(
      'cmd activity stack list',
      cancellation: stop,
      requireExitCode: false,
    );
    int? root, rootDisplay;
    final children = <int, int>{}, found = <int>{};
    for (final line in const LineSplitter().convert(result.stdout)) {
      if (line.startsWith('RootTask id=')) {
        root = int.tryParse(
          RegExp(r'^RootTask id=(\d+)').firstMatch(line)?[1] ?? '',
        );
        rootDisplay = int.tryParse(
          RegExp(r'\bdisplayId=(\d+)').firstMatch(line)?[1] ?? '',
        );
      } else if (line.trimLeft().startsWith('taskId=') && root != null) {
        children[root] = (children[root] ?? 0) + 1;
        if (rootDisplay == display && line.contains(': $package/')) {
          found.add(root);
        }
      }
    }
    if (found.length != 1 || children[found.single] != 1) {
      _fail('task_identity_unverified', '无法唯一核实独立窗口的现有任务，未重新启动应用。');
    }
    return found.single;
  }

  Future<void> moveTask(
    int task,
    int display, {
    AdbCancellation? cancellation,
  }) async {
    final result = await run(
      'cmd activity display move-stack $task $display',
      cancellation: cancellation,
      maxBytes: 8192,
    );
    if (result.stderr.isNotEmpty) _fail('task_move_failed', '系统未确认原应用任务迁移。');
  }
}

int scaledDisplayDensity(
  ({int width, int height, int density}) metrics,
  int width,
  int height,
) =>
    (metrics.density *
            math.min(width, height) /
            math.min(metrics.width, metrics.height))
        .round()
        .clamp(72, 65535);

Never _fail(String code, String message) => throw RequestFailure(code, message);
