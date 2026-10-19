// Build independent test APKs with the installed Android SDK, without Gradle.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

const fixtureNames = [
  'video',
  'audio-focus',
  'input',
  'share',
  'notification',
  'content-delivery',
];

Directory newest(String directory, [String prefix = '']) {
  final candidates = Directory(directory)
      .listSync()
      .whereType<Directory>()
      .where((d) => p.basename(d.path).startsWith(prefix))
      .toList();
  List<int> version(Directory d) => p
      .basename(d.path)
      .substring(prefix.length)
      .split('.')
      .where((v) => RegExp(r'^\d+$').hasMatch(v))
      .map(int.parse)
      .toList();
  candidates.sort((a, b) {
    final av = version(a), bv = version(b);
    for (var i = 0; i < av.length && i < bv.length; i++) {
      final comparison = av[i].compareTo(bv[i]);
      if (comparison != 0) return comparison;
    }
    return av.length.compareTo(bv.length);
  });
  if (candidates.isEmpty) {
    throw StateError('No Android SDK versions below $directory');
  }
  return candidates.last;
}

List<String> descendants(String directory, String suffix) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(suffix))
        .map((f) => f.path)
        .toList()
      ..sort();

Future<void> buildFixture(String fixture, List<String> arguments) async {
  if (!fixtureNames.contains(fixture)) {
    throw ArgumentError('Unknown fixture: $fixture');
  }
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption(
      'sdk',
      defaultsTo:
          Platform.environment['ANDROID_SDK_ROOT'] ??
          Platform.environment['ANDROID_HOME'] ??
          p.join(
            Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE']!,
            'Android',
            'Sdk',
          ),
    )
    ..addOption(
      'output',
      defaultsTo: p.join(Directory.systemTemp.path, 'connect-$fixture-fixture'),
    );
  final args = parse(parser, arguments);
  final root = p.join(
    repositoryRoot().path,
    'tool',
    'e2e',
    '${fixture.replaceAll('-', '_')}_fixture',
  );
  final output = p.normalize(p.absolute(args['output'] as String));
  final api36 = ['notification', 'content-delivery'].contains(fixture);
  // Resolve existing parent symlinks as pathlib.resolve() did before migration.
  var ancestor = Directory(output);
  final suffix = <String>[];
  while (!ancestor.existsSync()) {
    suffix.insert(0, p.basename(ancestor.path));
    ancestor = ancestor.parent;
  }
  final resolvedOutput = p.joinAll([
    ancestor.resolveSymbolicLinksSync(),
    ...suffix,
  ]);
  final temporaryRoot = Directory.systemTemp.resolveSymbolicLinksSync();
  if (api36 && !p.isWithin(temporaryRoot, resolvedOutput)) {
    throw ArgumentError('--output must be a directory below $temporaryRoot');
  }
  Directory(resolvedOutput).createSync(recursive: true);
  final sdk = args['sdk'] as String;
  final tools = api36
      ? p.join(sdk, 'build-tools', '36.0.0')
      : newest(p.join(sdk, 'build-tools')).path;
  final androidJar = api36
      ? p.join(sdk, 'platforms', 'android-36', 'android.jar')
      : p.join(
          newest(p.join(sdk, 'platforms'), 'android-').path,
          'android.jar',
        );
  String sdkTool(String name) => p.join(
    tools,
    Platform.isWindows
        ? '$name${name == 'd8' || name == 'apksigner' ? '.bat' : '.exe'}'
        : name,
  );
  final alias = switch (fixture) {
    'audio-focus' => 'focusfixture',
    'content-delivery' => 'deliveryfixture',
    _ => '${fixture}fixture',
  };
  final commonName = switch (fixture) {
    'video' => 'InteropVideoFixtureTestOnly',
    'audio-focus' => 'InteropFocusFixtureTestOnly',
    'input' => 'InteropInputFixtureTestOnly',
    'share' => 'InteropShareFixtureTestOnly',
    'notification' => 'NotificationFixtureTestOnly',
    _ => 'DeliveryFixtureTestOnly',
  };
  Future<void> run(String command, List<String> values) async {
    final result = await checked(command, values);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  }

  final key = p.join(resolvedOutput, 'fixture-test-only.keystore');
  if (!File(key).existsSync()) {
    await run('keytool', [
      '-genkeypair',
      '-keystore',
      key,
      '-storepass',
      'android',
      '-keypass',
      'android',
      '-alias',
      alias,
      '-keyalg',
      'RSA',
      '-keysize',
      '2048',
      '-validity',
      '3650',
      '-dname',
      'CN=$commonName',
      '-noprompt',
    ]);
  }
  final work = Directory(resolvedOutput).createTempSync('compile-');
  try {
    final generated = p.join(work.path, 'generated');
    final classes = p.join(work.path, 'classes');
    final dex = p.join(work.path, 'dex');
    for (final path in [generated, classes, dex]) {
      Directory(path).createSync();
    }
    final resources = Directory(p.join(root, 'res')).existsSync();
    if (resources) {
      await run(sdkTool('aapt2'), [
        'compile',
        '--dir',
        p.join(root, 'res'),
        '-o',
        p.join(work.path, 'resources.zip'),
      ]);
    }
    await run(sdkTool('aapt2'), [
      'link',
      '-I',
      androidJar,
      '--manifest',
      p.join(root, 'AndroidManifest.xml'),
      if (!api36) ...['--java', generated],
      '-o',
      p.join(work.path, 'base.apk'),
      if (resources) p.join(work.path, 'resources.zip'),
    ]);
    await run('javac', [
      if (api36) ...[
        '--release',
        '8',
        '-encoding',
        'UTF-8',
      ] else ...[
        '-source',
        '8',
        '-target',
        '8',
      ],
      '-classpath',
      androidJar,
      '-d',
      classes,
      ...descendants(p.join(root, 'src'), '.java'),
      ...descendants(generated, '.java'),
    ]);
    await run(sdkTool('d8'), [
      '--lib',
      androidJar,
      '--min-api',
      api36
          ? '36'
          : fixture == 'audio-focus'
          ? '26'
          : '23',
      '--output',
      dex,
      ...descendants(classes, '.class'),
    ]);
    final apkArchive = ZipDecoder().decodeBytes(
      File(p.join(work.path, 'base.apk')).readAsBytesSync(),
    );
    final dexBytes = File(p.join(dex, 'classes.dex')).readAsBytesSync();
    apkArchive.addFile(
      ArchiveFile.noCompress('classes.dex', dexBytes.length, dexBytes),
    );
    final unsigned = p.join(work.path, 'unsigned.apk');
    File(unsigned).writeAsBytesSync(ZipEncoder().encode(apkArchive)!);
    final aligned = p.join(work.path, 'aligned.apk');
    await run(sdkTool('zipalign'), ['-p', '4', unsigned, aligned]);
    final apk = p.join(resolvedOutput, '$fixture-fixture.apk');
    await run(sdkTool('apksigner'), [
      'sign',
      '--ks',
      key,
      '--ks-key-alias',
      alias,
      '--ks-pass',
      'pass:android',
      '--key-pass',
      'pass:android',
      '--out',
      apk,
      aligned,
    ]);
    await run(sdkTool('apksigner'), ['verify', '--verbose', apk]);
    stdout.writeln(apk);
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<void> main(List<String> arguments) => cli(() async {
  if (arguments.isEmpty ||
      arguments.first == '--help' ||
      arguments.first == '-h') {
    stdout.writeln(
      'Usage: dart tool/e2e/build_fixture.dart <${fixtureNames.join('|')}> [--sdk PATH] [--output PATH]',
    );
    return;
  }
  await buildFixture(arguments.first, arguments.sublist(1));
});
