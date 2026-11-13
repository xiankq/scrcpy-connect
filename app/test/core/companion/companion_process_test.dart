import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/companion/companion_process.dart';
import 'package:scrcpy_connect/core/companion/models/companion_deployment_identity.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';

void main() {
  test('监督器关闭期间核验失败后，重新确认原进程消失才删除部署', () async {
    // AVD 实际回执：关闭 shell 后 /proc 核验返回 42，原进程随即消失。
    final client = _ShellTrace([
      (42, ''),
      (0, 'released:absent\n'),
      (0, 'removed\n'),
    ]);
    await cleanupCompanionDeployment(
      _connection(client),
      _identity,
      timeout: const Duration(seconds: 1),
    );
    expect(client.commands, hasLength(3));
    expect(client.commands[1], contains('expected=5678'));
    expect(client.commands[1], isNot(contains('kill -TERM')));
    expect(client.commands.last, startsWith('rm -f -- '));
  });

  test('信号失败但原身份仍存活时保留失败及部署，不重复发信号', () async {
    final client = _ShellTrace([(42, ''), (0, 'pending\n')]);
    await expectLater(
      stopCompanionProcess(
        _connection(client),
        _identity,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<CompanionException>().having(
          (e) => e.code,
          'code',
          'remote_process_error',
        ),
      ),
    );
    expect(client.commands, hasLength(2));
    expect(client.commands.last, isNot(contains('kill -TERM')));
    expect(client.commands.last, isNot(contains('rm -f')));
  });

  test('PID 已被其他进程复用时只确认原身份结束，不清理新进程', () async {
    final client = _ShellTrace([(42, ''), (0, 'released:replaced\n')]);
    await stopCompanionProcess(
      _connection(client),
      _identity,
      timeout: const Duration(seconds: 1),
    );
    expect(client.commands, hasLength(2));
    expect(client.commands.last, isNot(contains('kill -TERM')));
  });
}

final _identity = CompanionDeploymentIdentity(
  pid: 1234,
  started: 5678,
  jarPath:
      '/data/local/tmp/interop-companion-0123456789abcdef0123456789abcdef.jar',
);

DeviceConnection _connection(AdbClient client) => DeviceConnection(
  client: client,
  device: const AdbDevice(id: 'connection', serial: 'avd', state: 'device'),
);

class _ShellTrace implements AdbClient {
  _ShellTrace(this.replies);
  final List<(int, String)> replies;
  final commands = <String>[];

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    commands.add(command);
    final (exitCode, output) = replies.removeAt(0);
    if (output.isNotEmpty) {
      yield AdbShellEvent(.stdout, Uint8List.fromList(utf8.encode(output)));
    }
    yield AdbShellEvent(.exit, Uint8List(0), exitCode: exitCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
