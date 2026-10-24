import 'dart:io';

import 'package:args/args.dart';

/// 使用工作区既有 Flutter 图像 codec 比较 PNG。
Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final parser = ArgParser()
    ..addOption(
      'config',
      defaultsTo: '${root.path}/tool/visual_parity/pages.json',
    )
    ..addOption('pencil-dir', mandatory: true)
    ..addOption('flutter-dir', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addFlag('help', abbr: 'h', negatable: false);
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(parser.usage);
    return;
  }
  try {
    final options = parser.parse(arguments);
    final output = Directory(options['output'] as String).absolute;
    await output.create(recursive: true);
    final report = File('${output.path}/report.json');
    if (await report.exists()) await report.delete();
    final process = await Process.start(
      'flutter',
      [
        'test',
        '--no-pub',
        '--reporter',
        'expanded',
        'tool/visual_parity/render_test.dart',
      ],
      workingDirectory: root.path,
      environment: {
        'CONNECT_PARITY_CONFIG': File(options['config'] as String)
            .absolute
            .path,
        'CONNECT_PARITY_PENCIL': Directory(options['pencil-dir'] as String)
            .absolute
            .path,
        'CONNECT_PARITY_FLUTTER': Directory(options['flutter-dir'] as String)
            .absolute
            .path,
        'CONNECT_PARITY_OUTPUT': output.path,
      },
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
    if (await report.exists()) {
      stdout.writeln('Comparison report: ${report.path}');
    } else {
      stderr.writeln('Comparison did not produce a report.');
      if (exitCode == 0) exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n${parser.usage}');
    exitCode = 64;
  } on ProcessException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
