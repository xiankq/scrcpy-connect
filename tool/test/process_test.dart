import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../src/repository_tooling.dart' show dartExecutable;
import '../src/process.dart';

void main() {
  late Directory temporary;
  setUp(() => temporary = Directory.systemTemp.createTempSync('process-test-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> child(String source, {Duration? timeout}) async {
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
    'passes working directory and environment to the actual child',
    () async {
      final result = await child('''
void main() {
  File('owned.txt').writeAsStringSync(Platform.environment['TOOL_PROCESS_VALUE']!);
}
''');
      expect(result.exitCode, 0);
      expect(
        File(p.join(temporary.path, 'owned.txt')).readAsStringSync(),
        'owned-child',
      );
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
