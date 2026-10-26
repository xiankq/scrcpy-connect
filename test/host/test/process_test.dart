import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../../../scripts/src/repository_tooling.dart' show dartExecutable;
import '../../../scripts/src/process.dart';

void main() {
  late Directory temporary;
  setUp(() => temporary = Directory.systemTemp.createTempSync('process-test-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> child(
    String source, {
    Duration? timeout,
    int maxOutputBytes = 32 * 1024 * 1024,
  }) async {
    final script = File(p.join(temporary.path, 'child.dart'))
      ..writeAsStringSync("import 'dart:io';\nimport 'dart:async';\n$source");
    return runProcess(
      dartExecutable,
      [script.path],
      workingDirectory: temporary.path,
      environment: const {'TOOL_PROCESS_VALUE': 'owned-child'},
      stdoutEncoding: null,
      stderrEncoding: null,
      timeout: timeout ?? const Duration(seconds: 10),
      maxOutputBytes: maxOutputBytes,
    );
  }

  test('closes unused stdin like Process.run', () async {
    final result = await child('''
Future<void> main() async {
  await stdin.drain<void>();
  stdout.write('eof');
}
''');
    expect(result.exitCode, 0);
    expect(result.stdout, [101, 111, 102]);
  });

  test('流式构建保留真实失败退出码', () async {
    final script = File(p.join(temporary.path, 'build.dart'))
      ..writeAsStringSync("import 'dart:io'; void main() { exitCode = 7; }");
    await expectLater(
      runStreamingProcess(dartExecutable, [script.path]),
      throwsA(isA<ProcessException>().having((e) => e.errorCode, 'code', 7)),
    );
  });

  test('流式构建超时先终止实际进程再交还清理权', () async {
    final script = File(p.join(temporary.path, 'build.dart'))
      ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:io';
void main() {
  File('pid').writeAsStringSync('$pid');
  var counter = 0;
  Timer.periodic(const Duration(milliseconds: 20), (_) {
    File('heartbeat').writeAsStringSync('${counter++}');
  });
}
''');
    await expectLater(
      runStreamingProcess(
        dartExecutable,
        [script.path],
        workingDirectory: temporary.path,
        timeout: const Duration(seconds: 2),
      ),
      throwsA(isA<TimeoutException>()),
    );
    final marker = File(p.join(temporary.path, 'heartbeat'));
    final atTimeout = marker.readAsStringSync();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(marker.readAsStringSync(), atTimeout);
    if (Platform.isLinux) {
      final childPid = File(p.join(temporary.path, 'pid')).readAsStringSync();
      expect(Directory('/proc/$childPid').existsSync(), isFalse);
    }
  });

  test(
    'output overflow fails without truncating success and reaps the child',
    () async {
      final marker = File(p.join(temporary.path, 'heartbeat'));
      final pidFile = File(p.join(temporary.path, 'pid'));
      await expectLater(
        child(r'''
void main() {
  File('pid').writeAsStringSync('$pid');
  var counter = 0;
  Timer.periodic(const Duration(milliseconds: 10), (_) {
    File('heartbeat').writeAsStringSync('${counter++}');
    stdout.add(List<int>.filled(4096, 65));
  });
}
''', maxOutputBytes: 8192),
        throwsA(
          isA<ProcessOutputLimitException>()
              .having((error) => error.stream, 'stream', 'stdout')
              .having((error) => error.limit, 'limit', 8192),
        ),
      );
      final atFailure = marker.readAsStringSync();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(marker.readAsStringSync(), atFailure);
      if (Platform.isLinux) {
        expect(
          Directory('/proc/${pidFile.readAsStringSync()}').existsSync(),
          isFalse,
        );
      }
    },
  );

  test(
    'captures concurrent binary pipes and preserves nonzero exit status',
    () async {
      final result = await child('''
Future<void> main() async {
  for (var i = 0; i < 32; i++) {
    stdout.add(List<int>.filled(8192, 255));
    stderr.add(List<int>.filled(8192, 128));
  }
  await Future.wait([stdout.flush(), stderr.flush()]);
  exitCode = 7;
}
''');
      expect(result.exitCode, 7);
      expect(result.stdout, List<int>.filled(32 * 8192, 255));
      expect(result.stderr, List<int>.filled(32 * 8192, 128));
    },
  );

  test(
    'timeout reaps the actual child before returning to fixture cleanup',
    () async {
      final marker = File(p.join(temporary.path, 'heartbeat'));
      final pidFile = File(p.join(temporary.path, 'pid'));
      var terminationConfirmed = false;
      try {
        await expectLater(
          child(r'''
void main() {
  File('pid').writeAsStringSync('$pid');
  var counter = 0;
  Timer.periodic(const Duration(milliseconds: 20), (_) {
    File('heartbeat').writeAsStringSync('${counter++}');
  });
}
''', timeout: const Duration(seconds: 2)),
          throwsA(isA<TimeoutException>()),
        );
        expect(
          marker.existsSync(),
          isTrue,
          reason: 'Child must reach its loop',
        );
        final atTimeout = marker.readAsStringSync();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(marker.readAsStringSync(), atTimeout);
        if (Platform.isLinux) {
          expect(
            Directory('/proc/${pidFile.readAsStringSync()}').existsSync(),
            isFalse,
          );
        }
        terminationConfirmed = true;
      } finally {
        if (!terminationConfirmed && pidFile.existsSync()) {
          Process.killPid(
            int.parse(pidFile.readAsStringSync()),
            ProcessSignal.sigkill,
          );
        }
      }
    },
  );
}
