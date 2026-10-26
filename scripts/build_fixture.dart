// 使用已安装 Android SDK 构建独立测试 APK，不依赖 Gradle。
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../test/fixtures/support.dart';
import 'src/fixture_cache.dart';
import 'src/android_sdk.dart';
import 'src/process.dart';
import 'src/repository_tooling.dart' show executable;

const fixtureNames = [
  'video',
  'audio-focus',
  'input',
  'share',
  'notification',
  'content-delivery',
];

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
    ..addOption('sdk', help: 'Defaults to the installed Android SDK.')
    ..addOption(
      'output',
      defaultsTo: p.join(Directory.systemTemp.path, 'connect-$fixture-fixture'),
    );
  final args = parse(parser, arguments);
  final repository = repositoryRoot();
  final root = p.join(
    repository.path,
    'test',
    'fixtures',
    '${fixture.replaceAll('-', '_')}_fixture',
  );
  final output = p.normalize(p.absolute(args['output'] as String));
  final api36 = ['notification', 'content-delivery'].contains(fixture);
  // 解析已存在父目录的符号链接，再核验输出目录。
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
  final sdk = androidSdkPath(args['sdk'] as String?);
  final tools = api36
      ? p.join(sdk, 'build-tools', '36.0.0')
      : latestAndroidVersion(p.join(sdk, 'build-tools')).path;
  final androidJar = api36
      ? p.join(sdk, 'platforms', 'android-36', 'android.jar')
      : p.join(
          latestAndroidVersion(
            p.join(sdk, 'platforms'),
            prefix: 'android-',
          ).path,
          'android.jar',
        );
  String sdkTool(String name) => androidSdkTool(tools, name);
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
  final javac = executable('javac') ?? 'javac';
  final keytool = executable('keytool') ?? 'keytool';
  final java = executable('java') ?? 'java';
  final lock = await File(p.join(resolvedOutput, '.build.lock'))
      .open(mode: FileMode.append);
  try {
    await lock.lock(FileLock.exclusive);
    final key = p.join(resolvedOutput, 'fixture-test-only.keystore');
    if (!File(key).existsSync()) {
      await runStreamingProcess(keytool, [
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
    final apk = File(p.join(resolvedOutput, '$fixture-fixture.apk'));
    final receipt = File(p.join(resolvedOutput, 'build-inputs.json'));
    final toolVersions = <String>[];
    for (final tool in [javac, java]) {
      final version = await checked(tool, ['-version']);
      toolVersions.add('$tool:${version.stdout}${version.stderr}');
    }
    final inputFiles = <String, File>{
      for (final path in [
        p.join(repository.path, 'scripts/build_fixture.dart'),
        p.join(repository.path, 'test/fixtures/support.dart'),
        p.join(repository.path, 'scripts/src/repository_tooling.dart'),
        p.join(repository.path, 'scripts/src/fixture_cache.dart'),
        p.join(repository.path, 'scripts/src/android_sdk.dart'),
        p.join(repository.path, 'scripts/src/process.dart'),
        p.join(root, 'AndroidManifest.xml'),
        ...Directory(p.join(root, 'src'))
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path),
        if (Directory(p.join(root, 'res')).existsSync())
          ...Directory(p.join(root, 'res'))
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => file.path),
        androidJar,
        key,
        for (final name in ['aapt2', 'd8', 'zipalign', 'apksigner'])
          sdkTool(name),
        p.join(tools, 'lib/d8.jar'),
        p.join(tools, 'lib/apksigner.jar'),
        File(javac).resolveSymbolicLinksSync(),
        File(java).resolveSymbolicLinksSync(),
        File(keytool).resolveSymbolicLinksSync(),
      ])
        path: File(path),
    };
    final fingerprint = await fixtureFingerprint(inputFiles, toolVersions);
    if (await canReuseFixture(apk, receipt, fingerprint, () async {
      await checked(sdkTool('apksigner'), ['verify', apk.path]);
    })) {
      stdout.writeln('Reusing verified fixture: ${apk.path}');
      return;
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
        await runStreamingProcess(sdkTool('aapt2'), [
          'compile',
          '--dir',
          p.join(root, 'res'),
          '-o',
          p.join(work.path, 'resources.zip'),
        ]);
      }
      await runStreamingProcess(sdkTool('aapt2'), [
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
      await runStreamingProcess(javac, [
        '--release',
        '8',
        '-encoding',
        'UTF-8',
        '-classpath',
        androidJar,
        '-d',
        classes,
        ...descendants(p.join(root, 'src'), '.java'),
        ...descendants(generated, '.java'),
      ]);
      await runStreamingProcess(sdkTool('d8'), [
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
      File(unsigned).writeAsBytesSync(ZipEncoder().encode(apkArchive));
      final aligned = p.join(work.path, 'aligned.apk');
      await runStreamingProcess(sdkTool('zipalign'), [
        '-p',
        '4',
        unsigned,
        aligned,
      ]);
      final signed = p.join(work.path, 'signed.apk');
      await runStreamingProcess(sdkTool('apksigner'), [
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
        signed,
        aligned,
      ]);
      await runStreamingProcess(sdkTool('apksigner'), [
        'verify',
        '--verbose',
        signed,
      ]);
      await File(signed).rename(apk.path);
      await recordFixture(apk, receipt, fingerprint);
      stdout.writeln(apk.path);
    } finally {
      work.deleteSync(recursive: true);
    }
  } finally {
    await lock.close();
  }
}

Future<void> main(List<String> arguments) => cli(() async {
  if (arguments.isEmpty ||
      arguments.first == '--help' ||
      arguments.first == '-h') {
    stdout.writeln(
      'Usage: dart scripts/build_fixture.dart <${fixtureNames.join('|')}> [--sdk PATH] [--output PATH]',
    );
    return;
  }
  await buildFixture(arguments.first, arguments.sublist(1));
});
