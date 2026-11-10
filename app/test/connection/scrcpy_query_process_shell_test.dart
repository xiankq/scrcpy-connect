import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/services/connection/scrcpy_query_process.dart';

void main() {
  final binary = Platform.environment['INTEROP_MKSH_BINARY'];
  final skip = !Platform.isLinux
      ? '该夹具使用 Linux /proc 核验真实子进程。'
      : binary == null || binary.isEmpty
      ? '需设置 INTEROP_MKSH_BINARY，不能用其他 shell 冒充 mksh。'
      : false;

  test('真实mksh监督清单输出与非零wait退出码', () async {
    final fixture = await _Fixture.open(binary!);
    addTearDown(fixture.dispose);
    final result = await fixture.query.run(AdbCancellation());
    expect(utf8.decode(result.stdout), 'List of video encoders:\n');
    expect(result.exitCode, 23);
    await fixture.query.close();
    final operation = fixture.api.operations.single;
    expect(operation.writes.map(utf8.decode), [
      'START ${operation.nonce}\n',
      'RUN ${operation.nonce}\n',
    ]);
    expect(
      operation.transcript,
      contains('__INTEROP_QUERY_END_${operation.nonce}__:23\n'),
    );
    expect(await fixture.launched.exists(), isTrue);
    await operation.assertChildExited();
  }, skip: skip);

  test('真实mksh运行中STOP等待原job退出且不借助独立PID信号', () async {
    final fixture = await _Fixture.open(binary!, block: true);
    addTearDown(fixture.dispose);
    final cancellation = AdbCancellation();
    final result = expectLater(
      fixture.query.run(cancellation),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await fixture.api.running.future;
    cancellation.cancel();
    await result;
    await fixture.query.close();
    final operation = fixture.api.operations.single;
    expect(
      operation.writes.map(utf8.decode),
      contains('STOP ${operation.nonce}\n'),
    );
    expect(
      operation.transcript,
      contains('__INTEROP_QUERY_END_${operation.nonce}__:143\n'),
    );
    await operation.assertChildExited();
    expect(fixture.api.operations, hasLength(1));
  }, skip: skip);

  test('真实mksh身份前子进程失败仍用完整END结清，不宣称查询成功', () async {
    final fixture = await _Fixture.open(binary!, failBeforeReady: true);
    addTearDown(fixture.dispose);
    await expectLater(
      fixture.query.run(AdbCancellation()),
      throwsA(
        isA<RequestFailure>().having((e) => e.code, 'code', 'process_identity'),
      ),
    );
    try {
      await fixture.query.close();
    } catch (error, stack) {
      final operation = fixture.api.operations.single;
      Error.throwWithStackTrace(
        StateError(
          '$error\nstdout=${jsonEncode(operation.transcript)}\nstderr=${jsonEncode(utf8.decode(operation.errors, allowMalformed: true))}',
        ),
        stack,
      );
    }
    final operation = fixture.api.operations.single;
    expect(operation.transcript, isNot(contains('__INTEROP_QUERY_READY_')));
    expect(
      operation.transcript,
      contains('__INTEROP_QUERY_END_${operation.nonce}__:40\n'),
    );
    expect(
      operation.writes.map(utf8.decode),
      isNot(contains('RUN ${operation.nonce}\n')),
    );
    expect(await fixture.launched.exists(), isFalse);
  }, skip: skip);

  test('真实mksh创建迟到而START前取消不创建查询子进程', () async {
    final fixture = await _Fixture.open(binary!);
    addTearDown(fixture.dispose);
    final gate = fixture.api.creationGate = Completer<void>();
    final cancellation = AdbCancellation();
    final result = expectLater(
      fixture.query.run(cancellation),
      throwsA(isA<RequestFailure>().having((e) => e.code, 'code', 'cancelled')),
    );
    await fixture.api.created.future;
    cancellation.cancel();
    final closing = fixture.query.close();
    gate.complete();
    await result;
    await closing;
    expect(fixture.api.operations.single.writes, isEmpty);
    expect(await fixture.launched.exists(), isFalse);
    expect(fixture.api.operations.single.transcript, isEmpty);
  }, skip: skip);
}

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

final class _Fixture {
  _Fixture(this.root, this.launched, this.api, this.query);
  final Directory root;
  final File launched;
  final _ShellApi api;
  final ScrcpyQueryProcess query;

  static Future<_Fixture> open(
    String binary, {
    bool block = false,
    bool failBeforeReady = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('scrcpy-query-mksh-');
    try {
      final mksh = await File(binary).resolveSymbolicLinks();
      final launched = File(p.join(root.path, 'app-started'));
      final sh = p.join(root.path, 'sh');
      if (failBeforeReady) {
        await _executable(sh, '#!$mksh\nexit 40\n');
      } else {
        await Link(sh).create(mksh);
      }
      await _executable(p.join(root.path, 'app_process'), '''#!$mksh
print -r -- started > ${_quote(launched.path)}
print -r -- 'List of video encoders:'
${block ? 'exec /bin/sleep 600' : 'exit 23'}
''');
      final api = _ShellApi(mksh, root.path);
      final connection = DeviceConnection(
        client: NativeAdbClient(api, '/unused/private-key'),
        device: AdbDevice(
          id: 'shell-fixture',
          serial: 'fixture',
          state: 'device',
          nativeOwner: api,
        ),
      );
      return _Fixture(
        root,
        launched,
        api,
        ScrcpyQueryProcess(
          connection: connection,
          jarPath: '/data/local/tmp/interop-encoders-shell-fixture.jar',
          option: 'list_encoders',
          maxBytes: 4096,
          timeout: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      await root.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> _executable(String path, String contents) async {
    await File(path).writeAsString(contents);
    final result = await Process.run('/bin/chmod', ['700', path]);
    if (result.exitCode != 0) {
      throw StateError('无法准备私有测试可执行文件：${result.stderr}');
    }
  }

  Future<void> dispose() async {
    if (api.creationGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    try {
      await query.close().timeout(const Duration(seconds: 10));
    } finally {
      try {
        await api.dispose();
      } finally {
        await root.delete(recursive: true);
      }
    }
  }
}

/// 把公开 exec 的真实生产脚本交给 mksh，不合成 READY、END 或退出事实。
final class _ShellApi implements NativeAdbApi {
  _ShellApi(this.binary, this.directory);
  final String binary, directory;
  final operations = <_ShellOperation>[];
  final running = Completer<void>(), created = Completer<void>();
  Completer<void>? creationGate;

  @override
  Future<String> service(
    String id,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(id, 'shell-fixture');
    expect(request.kind, AdbServiceKind.exec);
    final process = await Process.start(
      binary,
      ['-c', request.service],
      environment: {
        'PATH': '$directory:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
      },
    );
    final operation = _ShellOperation(process, request.service, running);
    operations.add(operation);
    if (!created.isCompleted) created.complete();
    await creationGate?.future;
    return '${operations.length - 1}';
  }

  @override
  Future<NativeAdbEvent?> next(String id) async {
    final operation = operations[int.parse(id)];
    return await operation.reader.moveNext() ? operation.reader.current : null;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    final operation = operations[int.parse(id)];
    expect(input.kind, AdbInputKind.bytes);
    await operation.write(input.bytes);
  }

  @override
  Future<void> cancel(String id) => operations[int.parse(id)].close();

  Future<void> dispose() async {
    for (final operation in operations) {
      await operation.dispose();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ShellOperation {
  _ShellOperation(this.process, String script, Completer<void> running) {
    nonce = RegExp(r'__INTEROP_QUERY_READY_([0-9a-f]{32})__:')
        .firstMatch(script)![1]!;
    reader = StreamIterator(events.stream);
    final stdoutDone = process.stdout.forEach((bytes) {
      raw.addAll(bytes);
      if (transcript.contains('List of video encoders:\n') &&
          !running.isCompleted) {
        running.complete();
      }
      events.add(
        NativeAdbEvent(
          kind: 'data',
          bytes: Uint8List.fromList(bytes),
          done: false,
        ),
      );
    });
    final stderrDone = process.stderr.forEach((bytes) {
      errors.addAll(bytes);
      // exec 是合并输出，不能替生产解析器隐藏 shell 错误。
      events.add(
        NativeAdbEvent(
          kind: 'data',
          bytes: Uint8List.fromList(bytes),
          done: false,
        ),
      );
    });
    drained = () async {
      exitCode = await process.exitCode;
      await Future.wait([stdoutDone, stderrDone]);
      events.add(
        NativeAdbEvent(
          kind: 'done',
          bytes: Uint8List(0),
          done: true,
          exitCode: exitCode,
        ),
      );
      // 原生关闭只等待本机进程与管道，不反向等待尚在消费事件的调用者。
      unawaited(events.close());
    }();
    drained.ignore();
  }

  final Process process;
  late final String nonce;
  final raw = <int>[], errors = <int>[];
  final writes = <Uint8List>[];
  final events = StreamController<NativeAdbEvent>();
  late final StreamIterator<NativeAdbEvent> reader;
  late final Future<void> drained;
  int? exitCode;
  Future<void>? _closing, _writing;
  bool inputClosed = false, acceptingInput = true;
  String get transcript => utf8.decode(raw, allowMalformed: true);

  Future<void> write(Uint8List bytes) {
    if (!acceptingInput) throw StateError('夹具输入已停止准入。');
    if (_writing != null) throw StateError('夹具输入已有在途写入。');
    writes.add(Uint8List.fromList(bytes));
    final writing = () async {
      process.stdin.add(bytes);
      await process.stdin.flush();
    }();
    _writing = writing;
    writing.then<void>(
      (_) {
        if (identical(_writing, writing)) _writing = null;
      },
      onError: (Object _) {
        if (identical(_writing, writing)) _writing = null;
      },
    );
    return writing;
  }

  Future<void> close() {
    acceptingInput = false;
    return _closing ??= _close().catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _close() async {
    // flush 持有 IOSink 的内部流绑定。先等原写入真正结算，再关闭输入；
    // 原写入失败仍由 write 调用者收到，不能拿该错误代替本机回收证明。
    await _writing?.then<void>((_) {}, onError: (Object _) {});
    if (!inputClosed) {
      try {
        await process.stdin.close();
      } on IOException {
        // 对端可能自然退出，但仍须等待实际退出与两条输出管道排空。
      }
      inputClosed = true;
    }
    await drained;
  }

  Future<void> assertChildExited() async {
    final match = RegExp(r'__INTEROP_QUERY_READY_[0-9a-f]{32}__:(\d+):(\d+)\n')
        .firstMatch(transcript)!;
    final stat = File('/proc/${match[1]}/stat');
    if (await stat.exists()) {
      final text = await stat.readAsString();
      final fields = text.substring(text.lastIndexOf(') ') + 2).split(' ');
      // PID 被复用也是原进程已退出；同一存活身份不能被当作回收成功。
      expect(fields[19], isNot(match[2]), reason: '原监督子进程仍存在：$text');
    }
  }

  Future<void> dispose() async {
    await _writing?.then<void>((_) {}, onError: (Object _) {});
    if (exitCode == null && acceptingInput) {
      try {
        await write(Uint8List.fromList(utf8.encode('STOP $nonce\n')));
      } on IOException {
        /* 仍须排空。 */
      }
    }
    try {
      await close().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // 只向本夹具直接持有的 shell 请求终止，不按发现的裸 PID 杀其他进程。
      process.kill(ProcessSignal.sigterm);
      await drained.timeout(const Duration(seconds: 5));
    } finally {
      await reader.cancel();
    }
    if (RegExp(r'__INTEROP_QUERY_READY_[0-9a-f]{32}__:').hasMatch(transcript)) {
      await assertChildExited();
    }
  }
}
