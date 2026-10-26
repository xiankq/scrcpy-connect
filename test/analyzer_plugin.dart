import 'dart:io';

import 'package:path/path.dart' as path;

import '../scripts/src/repository_tooling.dart';
import '../scripts/src/process.dart';

const source = '''import 'package:hooks_riverpod/hooks_riverpod.dart';

class InvalidNotifier extends Notifier<int> {
  @override
  int build() => 0;

  int get outsideState => 1;
}
''';

Future<void> main() async {
  Directory? temporary;
  try {
    final application = applicationRoot();
    // 夹具必须继承工作区的 analyzer 插件和导入配置。
    temporary = Directory(path.join(application.path, 'test'))
        .createTempSync('lint_smoke_');
    final fixture = File(path.join(temporary.path, 'lint_smoke.dart'))
      ..writeAsStringSync(source);
    final result = await runProcess(
      Platform.resolvedExecutable,
      ['analyze', '--fatal-infos', fixture.path],
      workingDirectory: application.path,
      timeout: const Duration(minutes: 3),
    );
    final output = '${result.stdout}\n${result.stderr}';
    if (!output.toLowerCase().contains('avoid_public_notifier_properties')) {
      throw StateError(
        'Riverpod plugin did not report its intentional violation (exit ${result.exitCode}).\n$output',
      );
    }
    stdout.writeln(
      'Riverpod analyzer plugin detected its intentional violation.',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary?.deleteSync(recursive: true);
  }
}
