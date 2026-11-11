import '../support/adb_event_fixture.dart';

import 'package:scrcpy_connect/models/device_connection.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/scrcpy_server_queries.dart';

void main() {
  test('经典shell真实上传与退出确认后删除JAR，不因缺少协议退出码阻塞', () async {
    final fixture = _Fixture();
    fixture.api.legacyShell = true;
    final entries = await fixture.probe.encoders(
      fixture.connection,
      AdbCancellation(),
    );
    expect(entries, [
      {
        'codec': 'h264',
        'name': 'c2.vendor.avc.encoder',
        'available': true,
        'hardware': true,
      },
    ]);
    expect(fixture.api.uploads.single.bytes, [1, 2, 3]);
    expect(fixture.api.trace, [
      'create:push-1',
      'write:push-1',
      'finish:push-1',
      'close:push-1',
      'execute',
      'close:shell-1',
      'remove',
      'close:shell-2',
    ]);
    expect(fixture.api.commands.first, isNot(contains('rm -f')));
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    await fixture.probe.close();
    expect(fixture.api.commands.length, 2);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('上传字节回执不完整不执行，已确认关闭后才可回收部署', () async {
    final fixture = _Fixture();
    fixture.api.transferred = 2;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('encoder_probe_upload')),
    );
    expect(fixture.api.commands, isEmpty);
    await fixture.probe.close();
    expect(fixture.api.commands.single, startsWith('rm -f -- '));
  });

  test('创建失败未交付会话由SDK持有责任，不伪造无法重试的部署债务', () async {
    final fixture = _Fixture();
    fixture.api.creationFailures = 1;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(isA<AdbException>()),
    );
    expect(fixture.api.commands, isEmpty);
    await fixture.probe.stopForConnection(fixture.connection);
    expect(fixture.api.commands, isEmpty);
    final next = await fixture.probe.encoders(
      fixture.connection,
      AdbCancellation(),
    );
    expect(next.single['name'], 'c2.vendor.avc.encoder');
    await fixture.probe.close();
    expect(fixture.api.commands.length, 2);
  });

  test('真实非零退出仍确认进程结束并清理，不留下不可解决的执行未知', () async {
    final fixture = _Fixture();
    fixture.api.executionExitCode = 9;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('shell_failed')),
    );
    expect(fixture.api.commands.length, 2);
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    await fixture.probe.close();
    expect(fixture.api.commands.length, 2);
  });

  test('上传关闭仅首败也交还显式停止重试，不在查询中隐式消耗失败', () async {
    final fixture = _Fixture();
    fixture.api.uploadCloseFailures = 1;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('encoder_probe_cleanup_unconfirmed')),
    );
    expect(fixture.api.closed, ['push-1']);
    expect(fixture.api.commands, isEmpty);
    await fixture.probe.stopForConnection(fixture.connection);
    expect(fixture.api.closed.where((id) => id == 'push-1').length, 2);
    expect(fixture.api.commands.single, startsWith('rm -f -- '));
    await fixture.probe.close();
  });

  for (final unknown in ['missing-terminal', 'unknown-exit-code']) {
    test('执行未知$unknown独立核验精确进程后回收，不永久锁住连接', () async {
      final fixture = _Fixture();
      fixture.api.executionUnknown = unknown;
      await expectLater(
        fixture.probe.encoders(fixture.connection, AdbCancellation()),
        throwsA(anyOf(isA<AdbException>(), _code('result_unknown'))),
      );
      await fixture.probe.stopForConnection(fixture.connection);
      await fixture.probe.close();
      await fixture.probe.close();
      expect(
        fixture.api.commands
            .where((c) => c.contains('list_encoders=true'))
            .length,
        1,
      );
      expect(
        fixture.api.commands
            .where((c) => c.contains('p=4321\nexpected=8765'))
            .length,
        1,
      );
      expect(fixture.api.commands.last, startsWith('rm -f -- '));
      expect(fixture.api.disconnected, isEmpty);
    });
  }

  test('同取消令牌的旧查询结束不会删除仍在创建的后继登记', () async {
    final fixture = _Fixture();
    final secondGate = fixture.api.creationGates[2] = Completer<void>();
    final cancellation = AdbCancellation();
    final first = fixture.probe.encoders(fixture.connection, cancellation);
    final second = fixture.probe.encoders(fixture.connection, cancellation);
    final secondFailure = expectLater(second, throwsA(isA<AdbException>()));
    await fixture.api.waitForUploads(2);
    await first;
    var stopped = false;
    final stopping = fixture.probe.stopForConnection(fixture.connection).then((
      _,
    ) {
      stopped = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(cancellation.isCancelled, isTrue);
    expect(stopped, isFalse);
    secondGate.complete();
    await secondFailure;
    await stopping;
    expect(fixture.api.closed, contains('push-2'));
    expect(
      fixture.api.commands.where((command) => command.startsWith('rm ')).length,
      2,
    );
    await fixture.probe.close();
  });

  test('同取消令牌并发创建全部排空，close等待每个迟到上传句柄', () async {
    final fixture = _Fixture();
    final firstGate = fixture.api.creationGates[1] = Completer<void>();
    final secondGate = fixture.api.creationGates[2] = Completer<void>();
    final cancellation = AdbCancellation();
    final first = expectLater(
      fixture.probe.encoders(fixture.connection, cancellation),
      throwsA(isA<AdbException>()),
    );
    final second = expectLater(
      fixture.probe.encoders(fixture.connection, cancellation),
      throwsA(isA<AdbException>()),
    );
    await fixture.api.waitForUploads(2);
    var closed = false;
    final closing = fixture.probe.close().then((_) => closed = true);
    expect(cancellation.isCancelled, isTrue);
    firstGate.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(fixture.api.commands, isEmpty);
    secondGate.complete();
    await second;
    await closing;
    expect(fixture.api.closed, containsAll(['push-1', 'push-2']));
    expect(fixture.api.uploads.every((upload) => upload.bytes.isEmpty), isTrue);
    expect(fixture.api.commands.length, 2);
    expect(
      fixture.api.commands.every((command) => command.startsWith('rm ')),
      isTrue,
    );
  });

  test('删除失败或回执不完整保留本次部署，重试不重放查询', () async {
    for (final fault in [
      'nonzero',
      'missing',
      'duplicate',
      'trailing',
      'eof',
    ]) {
      final fixture = _Fixture();
      fixture.api.removeFault = fault;
      await expectLater(
        fixture.probe.encoders(fixture.connection, AdbCancellation()),
        throwsA(
          fault == 'eof'
              ? isA<AdbException>().having(
                  (error) => error.code,
                  'code',
                  'result_unknown',
                )
              : _code(fault == 'nonzero' ? 'shell_failed' : 'result_unknown'),
        ),
      );
      fixture.api.removeFault = null;
      await fixture.probe.close();
      expect(fixture.api.runCount, 1);
      expect(
        fixture.api.commands.where((value) => value.startsWith('rm ')).length,
        2,
      );
    }
  });

  test('安装列表保留系统标识、Unicode名称及上游长名称换行格式', () async {
    final fixture = _Fixture();
    fixture.api.executionOutput =
        '[server] INFO: List of apps:\n'
        ' * 系统 设置                     com.android.settings\n'
        ' - An extremely long application name\n'
        '                                org.example.long\n';
    fixture.api.outputToStderr = true;
    final apps = await fixture.probe.installedApps(
      fixture.connection,
      AdbCancellation(),
    );
    expect(apps, [
      {'name': '系统 设置', 'packageName': 'com.android.settings', 'system': true},
      {
        'name': 'An extremely long application name',
        'packageName': 'org.example.long',
        'system': false,
      },
    ]);
    expect(fixture.api.commands.first, contains('list_apps=true'));
    expect(fixture.api.commands.first, isNot(contains('list_encoders')));
    expect(fixture.api.commands.first, contains('/interop-apps-1.jar'));
    expect(
      fixture.api.trace.indexOf('close:push-1'),
      lessThan(fixture.api.trace.indexOf('execute')),
    );
    await fixture.probe.close();
  });

  test('合法空安装清单不同于缺失清单回执', () async {
    final fixture = _Fixture();
    fixture.api.executionOutput = 'List of apps:\n';
    expect(
      await fixture.probe.installedApps(fixture.connection, AdbCancellation()),
      isEmpty,
    );
    fixture.api.executionOutput = '[server] ERROR: cannot list packages\n';
    await expectLater(
      fixture.probe.installedApps(fixture.connection, AdbCancellation()),
      throwsA(_code('apps_unavailable')),
    );
    expect(
      fixture.api.commands.where((command) => command.startsWith('rm ')).length,
      2,
    );
    await fixture.probe.close();
  });

  test('无效包名不成为可启动应用条目，单段android包名仍兼容换行格式', () async {
    final fixture = _Fixture();
    fixture.api.executionOutput =
        'List of apps:\n'
        ' - Digit package                  3example.bad\n'
        ' - Empty segment                  org..bad\n'
        ' - Overlong package               org.${List.filled(230, 'a').join()}\n'
        ' * Android\n'
        '                                  android\n'
        ' - Valid                          org.valid_app\n';
    expect(
      await fixture.probe.installedApps(fixture.connection, AdbCancellation()),
      [
        {'name': 'Android', 'packageName': 'android', 'system': true},
        {'name': 'Valid', 'packageName': 'org.valid_app', 'system': false},
      ],
    );
    await fixture.probe.close();
  });

  test('安装查询已知退出后无效UTF8不遗留无法回收的执行未知', () async {
    final fixture = _Fixture();
    fixture.api.executionBytes = [0xff];
    await expectLater(
      fixture.probe.installedApps(fixture.connection, AdbCancellation()),
      throwsA(_code('apps_unavailable')),
    );
    await fixture.probe.close();
    expect(fixture.api.commands.length, 2);
  });

  test('查询已经授权后取消，原监督器等待退出后才删除JAR且不关闭共享连接', () async {
    final fixture = _Fixture();
    fixture.api.holdExecution = true;
    final stop = AdbCancellation();
    final query = expectLater(
      fixture.probe.encoders(fixture.connection, stop),
      throwsA(_code('cancelled')),
    );
    await fixture.api.runStarted.future;
    stop.cancel();
    await query;
    await fixture.probe.stopForConnection(fixture.connection);
    await fixture.probe.close();
    expect(fixture.api.runCount, 1);
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')),
      isEmpty,
    );
    expect(
      fixture.api.trace.indexOf('stop'),
      lessThan(fixture.api.trace.indexOf('remove')),
    );
    expect(
      fixture.api.trace.indexOf('terminal'),
      lessThan(fixture.api.trace.indexOf('remove')),
    );
    expect(fixture.api.closed, contains('shell-1'));
    expect(fixture.api.disconnected, isEmpty);
  });

  test('执行未知的身份核验首败保留原进程，停止重试成功后才删JAR', () async {
    final fixture = _Fixture();
    fixture.api.executionUnknown = 'missing-terminal';
    fixture.api.inspectionFailures = 1;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('encoder_probe_cleanup_unconfirmed')),
    );
    expect(fixture.api.commands.any((c) => c.startsWith('rm ')), isFalse);
    await fixture.probe.stopForConnection(fixture.connection);
    await fixture.probe.close();
    expect(fixture.api.runCount, 1);
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    expect(
      fixture.api.commands
          .where((c) => c.contains('list_encoders=true'))
          .length,
      1,
    );
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')).length,
      2,
    );
  });

  test('终态已到但本机流关闭失败保留同流，关闭重试不重放查询', () async {
    final fixture = _Fixture();
    fixture.api.processCloseFails = true;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('encoder_probe_cleanup_unconfirmed')),
    );
    expect(fixture.api.commands.any((c) => c.startsWith('rm ')), isFalse);
    fixture.api.processCloseFails = false;
    await fixture.probe.stopForConnection(fixture.connection);
    await fixture.probe.close();
    expect(fixture.api.runCount, 1);
    expect(
      fixture.api.closed.where((id) => id == 'shell-1').length,
      greaterThanOrEqualTo(2),
    );
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    expect(fixture.api.disconnected, isEmpty);
  });

  test('取消等待迟到exec句柄，不发送RUN并实际关闭原流', () async {
    final fixture = _Fixture();
    final gate = fixture.api.execCreationGate = Completer<void>();
    final stop = AdbCancellation();
    final query = expectLater(
      fixture.probe.encoders(fixture.connection, stop),
      throwsA(_code('cancelled')),
    );
    await fixture.api.execCreated.future;
    var stopped = false;
    final stopping = fixture.probe
        .stopForConnection(fixture.connection)
        .then((_) => stopped = true);
    expect(stop.isCancelled, isTrue);
    expect(stopped, isFalse);
    expect(fixture.api.runCount, 0);
    gate.complete();
    await query;
    await stopping;
    expect(fixture.api.runCount, 0);
    expect(fixture.api.startCount, 0);
    expect(fixture.api.closed, contains('shell-1'));
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    await fixture.probe.close();
  });

  test('输出超限仍接纳同nonce监督终态，回收后保留限额错误', () async {
    final fixture = _Fixture();
    fixture.api.executionBytes = List.filled(512 * 1024 + 1024, 120);
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('byte_limit')),
    );
    await fixture.probe.close();
    expect(fixture.api.runCount, 1);
    expect(
      fixture.api.commands
          .where((c) => c.contains('list_encoders=true'))
          .length,
      1,
    );
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
  });

  test('原监督器STOP回执迟到时禁止删除JAR，收到真实终态后才完成取消', () async {
    final fixture = _Fixture();
    fixture.api.holdExecution = true;
    fixture.api.holdStop = true;
    final stop = AdbCancellation();
    var finished = false;
    final query = expectLater(
      fixture.probe.encoders(fixture.connection, stop),
      throwsA(_code('cancelled')),
    ).then((_) => finished = true);
    await fixture.api.runStarted.future;
    stop.cancel();
    await fixture.api.stopSent.future;
    expect(finished, isFalse);
    expect(fixture.api.commands.any((c) => c.startsWith('rm ')), isFalse);
    final operation = fixture.api.operations['shell-1']!;
    fixture.api._terminal(operation, operation.queryToken!, 143);
    await query;
    await fixture.probe.close();
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')),
      isEmpty,
    );
  });

  test('START后身份前失败的同nonce终态仍证明回收，但不能作为查询成功', () async {
    final fixture = _Fixture();
    fixture.api.failBeforeReady = true;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('process_identity')),
    );
    await fixture.probe.close();
    expect(fixture.api.startCount, 1);
    expect(fixture.api.runCount, 0);
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')),
      isEmpty,
    );
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    expect(
      fixture.api.trace.indexOf('terminal'),
      lessThan(fixture.api.trace.indexOf('remove')),
    );
  });

  test('启动诊断先于同nonce终态时仍排空退出，但保留身份错误', () async {
    final fixture = _Fixture();
    fixture.api.failBeforeReady = true;
    fixture.api.startupDiagnostic = true;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('process_identity')),
    );
    await fixture.probe.close();
    expect(fixture.api.startCount, 1);
    expect(fixture.api.runCount, 0);
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')),
      isEmpty,
    );
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
    expect(
      fixture.api.trace.indexOf('terminal'),
      lessThan(fixture.api.trace.indexOf('remove')),
    );
  });

  test('启动诊断后仍保存READY身份，STOP终态排空且不能发RUN', () async {
    final fixture = _Fixture();
    fixture.api.startupDiagnostic = true;
    fixture.api.holdExecution = true;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('process_identity')),
    );
    await fixture.probe.close();
    expect(fixture.api.startCount, 1);
    expect(fixture.api.runCount, 0);
    expect(fixture.api.trace, contains('stop'));
    expect(fixture.api.trace, contains('terminal'));
    expect(
      fixture.api.commands.where((c) => c.contains('expected=8765')),
      isEmpty,
    );
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
  });

  test('START可能交付但身份丢失时不凭无RUN宣称退出，也不删除JAR', () async {
    final fixture = _Fixture();
    fixture.api.loseReady = true;
    final stop = AdbCancellation();
    final query = expectLater(
      fixture.probe.encoders(fixture.connection, stop),
      throwsA(_code('encoder_probe_cleanup_unconfirmed')),
    );
    await fixture.api.startSent.future;
    // 原流真实断开仍没有远端子进程退出证明。
    fixture.api.operations['shell-1']!.close();
    stop.cancel();
    await query;
    expect(fixture.api.runCount, 0);
    await expectLater(
      fixture.probe.stopForConnection(fixture.connection),
      throwsA(_code('encoder_probe_cleanup_unconfirmed')),
    );
    expect(fixture.api.commands.any((c) => c.startsWith('rm ')), isFalse);
    expect(fixture.api.disconnected, isEmpty);
  });

  test('其他nonce终态不能证明原查询已退出，必须独立核验后收尾', () async {
    final fixture = _Fixture();
    fixture.api.wrongTerminalNonce = true;
    await expectLater(
      fixture.probe.encoders(fixture.connection, AdbCancellation()),
      throwsA(_code('result_unknown')),
    );
    await fixture.probe.close();
    expect(
      fixture.api.commands
          .where((c) => c.contains('p=4321\nexpected=8765'))
          .length,
      1,
    );
    expect(fixture.api.runCount, 1);
    expect(fixture.api.commands.last, startsWith('rm -f -- '));
  });
}

Matcher _code(String code) =>
    isA<RequestFailure>().having((error) => error.code, 'code', code);

final class _Fixture {
  _Fixture() {
    connection = DeviceConnection(
      client: NativeAdbClient(api, '/unused/key'),
      device: AdbDevice(
        id: 'exact-connection',
        serial: 'serial',
        state: 'device',
        nativeOwner: api,
      ),
    );
    probe = ScrcpyServerQueries(
      serverBytes: Uint8List.fromList([1, 2, 3]),
      newId: () => '${++generation}',
      timeout: const Duration(seconds: 2),
    );
  }
  final api = _Api();
  int generation = 0;
  late final DeviceConnection connection;
  late final ScrcpyServerQueries probe;
}

final class _Operation {
  final bytes = <int>[];
  final queue = Queue<NativeAdbEvent>();
  Completer<NativeAdbEvent?>? waiting;
  bool closed = false, endWithoutTerminal = false;
  String? queryToken;
  String? queryCommand;
  bool run = false;

  void add(NativeAdbEvent event) {
    final pending = waiting;
    if (pending != null) {
      waiting = null;
      pending.complete(event);
    } else {
      queue.add(event);
    }
  }

  Future<NativeAdbEvent?> next() {
    if (queue.isNotEmpty) return Future.value(queue.removeFirst());
    if (closed || endWithoutTerminal) return Future.value(null);
    return (waiting = Completer<NativeAdbEvent?>()).future;
  }

  void close() {
    closed = true;
    queue.clear();
    waiting?.complete(null);
    waiting = null;
  }
}

final class _Api implements NativeAdbApi {
  final operations = <String, _Operation>{};
  final uploads = <_Operation>[];
  final creationGates = <int, Completer<void>>{};
  final uploadWaiters = <int, Completer<void>>{};
  final trace = <String>[], closed = <String>[], commands = <String>[];
  final disconnected = <String>[];
  int shellCount = 0;
  int creationFailures = 0;
  int executionExitCode = 0;
  int? transferred;
  bool legacyShell = false;
  String? removeFault;
  int uploadCloseFailures = 0;
  String? executionUnknown, executionOutput;
  List<int>? executionBytes;
  bool outputToStderr = false;
  bool holdExecution = false,
      processCloseFails = false,
      wrongTerminalNonce = false,
      loseReady = false,
      failBeforeReady = false,
      startupDiagnostic = false,
      holdStop = false;
  int inspectionFailures = 0, runCount = 0, startCount = 0;
  final runStarted = Completer<void>(),
      execCreated = Completer<void>(),
      startSent = Completer<void>(),
      stopSent = Completer<void>();
  Completer<void>? execCreationGate;

  Future<void> waitForUploads(int count) => uploads.length >= count
      ? Future.value()
      : (uploadWaiters[count] ??= Completer<void>()).future;

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async {
    expect(id, 'exact-connection');
    expect(request.kind, AdbSyncKind.push);
    expect(request.permissions, 384);
    expect(request.maxBytes, 3);
    if (creationFailures > 0) {
      creationFailures--;
      throw const AdbException('closed');
    }
    final operation = _Operation();
    uploads.add(operation);
    final index = uploads.length;
    final key = 'push-$index';
    trace.add('create:$key');
    operations[key] = operation;
    uploadWaiters[index]?.complete();
    await creationGates[index]?.future;
    return key;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    final operation = operations[id]!;
    if (input.kind == AdbInputKind.bytes) {
      if (operation.queryToken case final token?) {
        final text = utf8.decode(input.bytes);
        if (text == 'START $token\n') {
          startCount++;
          if (!startSent.isCompleted) startSent.complete();
          if (startupDiagnostic) {
            operation.add(
              adbText('mksh: /proc/4321/stat: No such file or directory\n'),
            );
          }
          if (failBeforeReady) {
            _terminal(operation, token, 40);
            return;
          }
          if (!loseReady) {
            operation.add(
              adbText('__INTEROP_QUERY_READY_${token}__:4321:8765\n'),
            );
          }
          return;
        }
        if (text == 'STOP $token\n') {
          trace.add('stop');
          if (!stopSent.isCompleted) stopSent.complete();
          if (holdStop || loseReady) return;
          if (!operation.closed &&
              !operation.endWithoutTerminal &&
              holdExecution) {
            _terminal(operation, token, 143);
          }
          return;
        }
        expect(text, 'RUN $token\n');
        operation.run = true;
        runCount++;
        if (!runStarted.isCompleted) runStarted.complete();
        if (holdExecution) return;
        _queryOutput(operation);
        return;
      }
      trace.add('write:$id');
      operation.bytes.addAll(input.bytes);
    } else if (input.kind == AdbInputKind.finish) {
      trace.add('finish:$id');
      operation.add(
        adbDone(transferred: transferred ?? operation.bytes.length),
      );
    }
  }

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(id, 'exact-connection');
    expect(request.kind, AdbServiceKind.exec);
    final command = request.service;
    commands.add(command);
    final key = 'shell-${++shellCount}';
    final operation = operations[key] = _Operation();
    final check = RegExp(r'__INTEROP_QUERY_CHECK_([0-9a-f]{32})__:')
        .firstMatch(command);
    if (check != null) {
      trace.add('inspect');
      final failed = inspectionFailures > 0;
      if (failed) inspectionFailures--;
      operation.add(
        adbText(
          'released:absent\n\n__INTEROP_QUERY_CHECK_${check[1]}__:${failed ? 42 : 0}\n',
        ),
      );
      operation.add(adbDone());
      return key;
    }
    trace.add('execute');
    final token = RegExp(r'__INTEROP_QUERY_READY_([0-9a-f]{32})__:')
        .firstMatch(command)![1]!;
    operation.queryToken = token;
    operation.queryCommand = command;
    if (!execCreated.isCompleted) execCreated.complete();
    await execCreationGate?.future;
    return key;
  }

  void _terminal(_Operation operation, String token, int code) {
    trace.add('terminal');
    operation.add(adbText('\n__INTEROP_QUERY_END_${token}__:$code\n'));
    operation.add(adbDone());
  }

  void _queryOutput(_Operation operation) {
    final token = operation.queryToken!;
    operation.add(
      adbData(
        executionBytes ??
            utf8.encode(
              executionOutput ??
                  (operation.queryCommand!.contains('list_apps=true')
                      ? 'List of apps:\n - Example org.example.app\n'
                      : 'List of video encoders:\n --video-codec=h264 --video-encoder=c2.vendor.avc.encoder (hw)\n'),
            ),
      ),
    );
    if (executionUnknown == 'missing-terminal') {
      operation.endWithoutTerminal = true;
    } else {
      if (executionUnknown != 'unknown-exit-code') {
        operation.add(
          adbText(
            '\n__INTEROP_QUERY_END_${wrongTerminalNonce ? '00000000000000000000000000000000' : token}__:$executionExitCode\n',
          ),
        );
      }
      operation.add(adbDone());
    }
  }

  @override
  Future<String> shell(String id, String command, int timeoutMs) async {
    expect(id, 'exact-connection');
    commands.add(command);
    final remove = command.startsWith('rm ');
    trace.add(remove ? 'remove' : 'execute');
    final key = 'shell-${++shellCount}';
    final operation = operations[key] = _Operation();
    if (remove && removeFault != 'missing') {
      final marker = RegExp(r'__INTEROP_QUERY_REMOVE_[a-f0-9-]+__:')
          .firstMatch(command)
          ?.group(0);
      if (marker != null) {
        final receipt = '\n$marker${removeFault == 'nonzero' ? 1 : 0}\n';
        operation.add(
          adbText(
            receipt +
                (removeFault == 'duplicate' ? receipt : '') +
                (removeFault == 'trailing' ? 'unexpected\n' : ''),
            kind: 'stdout',
          ),
        );
      }
    }
    if (!remove) {
      operation.add(
        adbData(
          executionBytes ??
              utf8.encode(
                executionOutput ??
                    (command.contains('list_apps=true')
                        ? 'List of apps:\n - Example org.example.app\n'
                        : 'List of video encoders:\n --video-codec=h264 --video-encoder=c2.vendor.avc.encoder (hw)\n'),
              ),
          kind: outputToStderr ? 'stderr' : 'stdout',
        ),
      );
    }
    if (remove && removeFault == 'eof' ||
        !remove && executionUnknown == 'missing-terminal') {
      operation.endWithoutTerminal = true;
    } else {
      operation.add(
        adbDone(
          kind: 'exit',
          exitCode:
              legacyShell || !remove && executionUnknown == 'unknown-exit-code'
              ? null
              : remove && removeFault == 'nonzero'
              ? 1
              : remove
              ? 0
              : executionExitCode,
        ),
      );
    }
    return key;
  }

  @override
  Future<NativeAdbEvent?> next(String id) => operations[id]!.next();

  @override
  Future<void> cancel(String id) async {
    closed.add(id);
    trace.add('close:$id');
    if (operations[id]!.queryToken != null && processCloseFails) {
      throw const AdbException('cleanup_unconfirmed');
    }
    if (id.startsWith('push')) {
      if (uploadCloseFailures > 0) {
        if (uploadCloseFailures > 0) uploadCloseFailures--;
        throw const AdbException('cleanup_unconfirmed');
      }
    }
    operations[id]!.close();
  }

  @override
  Future<void> disconnect(String id) async => disconnected.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
