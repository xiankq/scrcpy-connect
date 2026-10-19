import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../../tooling.dart';

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addOption('sdk')
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(
      'Build an API-21 app_process probe.\nUsage: dart build_probe.dart OUTPUT [--sdk SDK]\n${parser.usage}',
    );
    return;
  }
  require(options.rest.length == 1, 'Provide exactly one output JAR');
  require(
    (options['sdk'] as String?) != null ||
        Platform.environment['ANDROID_HOME'] != null ||
        Platform.environment['ANDROID_SDK_ROOT'] != null,
    'Set ANDROID_HOME (or --sdk)',
  );
  require(Platform.environment['JAVA_HOME'] != null, 'Set JAVA_HOME');
  final sdk = androidSdk(options['sdk'] as String?);
  final output = File(options.rest.single).absolute;
  final source = p.join(
    repositoryRoot().path,
    'servers',
    'vendor',
    'test',
    'ScrcpyApi21Probe.java',
  );
  final android = p.join(sdk.path, 'platforms', 'android-36', 'android.jar');
  await withTemporary('scrcpy-api21-probe-', (work) async {
    await run(javaTool('javac'), [
      '-source',
      '8',
      '-target',
      '8',
      '-classpath',
      android,
      '-d',
      work.path,
      source,
    ], echo: true);
    await run(
      p.join(
        sdk.path,
        'build-tools',
        '36.0.0',
        Platform.isWindows ? 'd8.bat' : 'd8',
      ),
      [
        '--min-api',
        '21',
        '--lib',
        android,
        '--output',
        work.path,
        ...files(work, '.class').map((file) => file.path),
      ],
      echo: true,
    );
    await output.writeAsBytes(
      storedZip({
        'classes.dex': File(p.join(work.path, 'classes.dex')).readAsBytesSync(),
      }, date: DateTime.utc(1980)),
    );
  });
  stdout.writeln(output.path);
});
