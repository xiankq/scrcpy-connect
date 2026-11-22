/// 本机签名、按 ABI 发布构建与独立 APK 校验。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'src/repository_tooling.dart';
import 'src/apk.dart';
import 'src/android_sdk.dart';

final root = repositoryRoot();
const platforms = {
  'arm64': ('android-arm64', ['arm64-v8a']),
  'arm': ('android-arm', ['armeabi-v7a']),
  'x64': ('android-x64', ['x86_64']),
  'universal': (
    'android-arm,android-arm64,android-x64',
    ['armeabi-v7a', 'arm64-v8a', 'x86_64'],
  ),
  'split': (
    'android-arm,android-arm64,android-x64',
    ['armeabi-v7a', 'arm64-v8a', 'x86_64'],
  ),
};

Future<void> privateFile(File file, List<int> contents) async {
  file.createSync(exclusive: true);
  try {
    if (!Platform.isWindows) {
      await runTool(['chmod', '600', file.path], quiet: true);
    }
    file.writeAsBytesSync(contents);
  } on Object {
    file.deleteSync();
    rethrow;
  }
}

Future<void> initializeSigning({Directory? android}) async {
  android ??= Directory(p.join(applicationRoot(root).path, 'android'));
  final properties = File(p.join(android.path, 'key.properties'));
  if (properties.existsSync()) {
    stdout.writeln(
      'Keeping existing app/android/key.properties and signing identity.',
    );
    return;
  }
  final key = File(p.join(android.path, 'keystores/connect-local-release.jks'));
  if (key.existsSync()) {
    throw StateError(
      'Signing key already exists; restore its key.properties. It will not be replaced.',
    );
  }
  final keytool = executable('keytool');
  if (keytool == null) {
    throw StateError(
      'keytool is required (install JDK 21 and add its bin directory to PATH).',
    );
  }
  key.parent.createSync(recursive: true);
  final secure = Random.secure();
  final password = base64Url
      .encode(List<int>.generate(32, (_) => secure.nextInt(256)))
      .replaceAll('=', '');
  final work = key.parent.createTempSync('signing-');
  try {
    final candidate = File(p.join(work.path, p.basename(key.path)));
    await runTool(
      [
        keytool,
        '-genkeypair',
        '-keystore',
        candidate.path,
        '-storetype',
        'JKS',
        '-alias',
        'interconnect',
        '-keyalg',
        'RSA',
        '-keysize',
        '3072',
        '-validity',
        '10000',
        '-dname',
        'CN=Interconnect Local Release,O=Interconnect',
        '-storepass:env',
        'CONNECT_LOCAL_KEY_PASSWORD',
        '-keypass:env',
        'CONNECT_LOCAL_KEY_PASSWORD',
      ],
      environment: {'CONNECT_LOCAL_KEY_PASSWORD': password},
      secret: true,
    );
    await privateFile(key, candidate.readAsBytesSync());
  } finally {
    work.deleteSync(recursive: true);
  }
  try {
    await privateFile(
      properties,
      utf8.encode(
        '# Machine-local sideload signing identity. Keep both files backed up privately.\n'
        'storeFile=keystores/connect-local-release.jks\n'
        'keyAlias=interconnect\n'
        'storePassword=$password\nkeyPassword=$password\n',
      ),
    );
  } on Object {
    // 本次调用独占创建密钥成功，因此仅本次调用拥有该密钥。
    key.deleteSync();
    rethrow;
  }
  stdout.writeln(
    'Created a persistent local release signing identity; credentials are Git-ignored.',
  );
  stdout.writeln(
    'For distribution, replace key.properties with your chosen release keystore.',
  );
}

(String, String, String) sdkTools() {
  const names = ['apksigner', 'aapt2', 'zipalign'];
  final directory = latestAndroidVersion(
    p.join(androidSdkPath(), 'build-tools'),
    usable: (directory) => names.every(
      (name) => File(androidSdkTool(directory.path, name)).existsSync(),
    ),
  );
  return (
    androidSdkTool(directory.path, names[0]),
    androidSdkTool(directory.path, names[1]),
    androidSdkTool(directory.path, names[2]),
  );
}

const androidNamespace = 'http://schemas.android.com/apk/res/android';

void verifyManifest(String contents) {
  final manifest = XmlDocument.parse(contents);
  final application = manifest.findAllElements('application').singleOrNull;
  if (application == null) {
    throw StateError('Packaged manifest is missing its application.');
  }
  String? attribute(XmlElement element, String name) =>
      element.getAttribute(name, namespaceUri: androidNamespace);
  for (final name in ['allowBackup', 'usesCleartextTraffic']) {
    if (attribute(application, name) != 'false') {
      throw StateError('Packaged manifest must disable $name.');
    }
  }
  final activity = application
      .findElements('activity')
      .where(
        (item) => (attribute(item, 'name') ?? '').endsWith('.MainActivity'),
      )
      .singleOrNull;
  if (activity == null ||
      !['singleTask', '2', '0x2'].contains(attribute(activity, 'launchMode'))) {
    throw StateError('Packaged MainActivity must use singleTask.');
  }
  void requirePrivateService(String name, Set<String> expectedTypes) {
    final service = application
        .findElements('service')
        .where((item) => (attribute(item, 'name') ?? '').endsWith('.$name'))
        .singleOrNull;
    final type = service == null
        ? ''
        : attribute(service, 'foregroundServiceType') ?? '';
    if (service == null ||
        attribute(service, 'exported') != 'false' ||
        !expectedTypes.contains(type)) {
      throw StateError(
        'Packaged $name must retain its private foreground type.',
      );
    }
  }

  requirePrivateService('ConnectionService', {'connectedDevice', '16', '0x10'});
  requirePrivateService('AudioPlaybackService', {'mediaPlayback', '2', '0x2'});
}

Future<Map<String, Object>> verifyApk(
  File input, [
  List<String>? expectedAbis,
]) async {
  final apk = File(input.resolveSymbolicLinksSync());
  final tools = sdkTools();
  final bytes = apk.readAsBytesSync();
  final inspection = inspectApk(
    bytes,
    repository: root,
    expectedAbis: expectedAbis,
  );
  final signature =
      (await runTool([
            tools.$1,
            'verify',
            '--verbose',
            '--print-certs',
            apk.path,
          ], quiet: true)).stdout
          as String;
  await runTool([tools.$3, '-c', '-P', '16', '-v', '4', apk.path], quiet: true);
  final badging =
      (await runTool([
            tools.$2,
            'dump',
            'badging',
            apk.path,
          ], quiet: true)).stdout
          as String;
  final sdk = p.dirname(p.dirname(p.dirname(tools.$1)));
  final manifest = await runTool([
    androidSdkTool(p.join(sdk, 'cmdline-tools/latest/bin'), 'apkanalyzer'),
    'manifest',
    'print',
    apk.path,
  ], quiet: true);
  verifyManifest(manifest.stdout as String);
  final lines = const LineSplitter().convert(badging);
  final package = lines
      .where((line) => line.startsWith('package: '))
      .firstOrNull;
  if (package == null ||
      !package.startsWith("package: name='dev.scrcpyconnect.scrcpy_connect'")) {
    throw StateError('The final APK has an unexpected application ID.');
  }
  if (!lines.contains("application-label:'邻接'") ||
      !lines.any((line) => line.startsWith('application-icon-'))) {
    throw StateError('The final APK lacks the app label or launcher icon.');
  }
  if (!lines.any((line) => line.startsWith('launchable-activity:'))) {
    throw StateError('The final APK has no launchable activity.');
  }
  final receipt = <String, Object>{
    'apk': apk.path,
    'bytes': bytes.length,
    'sha256': sha256.convert(bytes).toString(),
    'abis': inspection.abis,
    'size': inspection.toJson(),
    'package': package,
    'signatureVerified': true,
    'zipIntegrityVerified': true,
    'zipAlignmentVerified': true,
    'zipNativePageAlignmentBytes': 16384,
    'sharedServerArtifactsVerified': true,
    'manifestVerified': true,
    'signerCertificates': const LineSplitter()
        .convert(signature)
        .where((line) => line.contains('certificate SHA-256 digest:'))
        .toList(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(receipt));
  return receipt;
}

Future<void> buildApk({
  String mode = 'release',
  String abi = 'split',
  bool noPub = false,
  bool compressNative = true,
  Directory? application,
}) async {
  application ??= applicationRoot(root);
  final android = Directory(p.join(application.path, 'android'));
  if (mode == 'release' &&
      !File(p.join(android.path, 'key.properties')).existsSync()) {
    throw StateError(
      'No release signing identity. Run: dart scripts/android.dart init-signing',
    );
  }
  final registrant = File(
    p.join(
      android.path,
      'app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    ),
  );
  if (mode == 'release' &&
      noPub &&
      registrant.existsSync() &&
      registrant.readAsStringSync().contains(
        'dev.flutter.plugins.integration_test.IntegrationTestPlugin',
      )) {
    throw StateError(
      'Stale integration-test plugin registration. Omit --no-pub so Flutter regenerates release registration.',
    );
  }
  final flutter = executable('flutter');
  if (flutter == null) throw StateError('Add Flutter to PATH.');
  final platform = platforms[abi];
  if (platform == null) throw ArgumentError.value(abi, 'abi');
  final watch = Stopwatch()..start();
  await streamTool([
    flutter,
    'build',
    'apk',
    '--$mode',
    '--target-platform',
    platform.$1,
    if (abi == 'split') '--split-per-abi',
    '-Pcompress-native-libs=$compressNative',
    if (noPub) '--no-pub',
  ], cwd: application);
  watch.stop();
  for (final architecture in abi == 'split' ? platform.$2 : [null]) {
    final filename = architecture == null
        ? 'app-$mode.apk'
        : 'app-$architecture-$mode.apk';
    await verifyApk(
      File(p.join(application.path, 'build/app/outputs/flutter-apk', filename)),
      architecture == null ? platform.$2 : [architecture],
    );
  }
  stdout.writeln(
    'Build wall time: ${(watch.elapsedMicroseconds / 1000000).toStringAsFixed(2)}s. Reuse .dart_tool/hooks_runner and Gradle caches between builds.',
  );
}

Future<void> main(List<String> arguments) async {
  try {
    ArgParser commandParser() =>
        ArgParser()..addFlag('help', abbr: 'h', negatable: false);
    final parser = commandParser()
      ..addCommand('init-signing', commandParser())
      ..addCommand(
        'build',
        commandParser()
          ..addOption(
            'abi',
            allowed: platforms.keys.toList(),
            defaultsTo: 'split',
            help: 'Build separate installable APKs by default; universal is an explicit compatibility bundle.',
          )
          ..addOption(
            'mode',
            allowed: ['debug', 'release'],
            defaultsTo: 'release',
          )
          ..addFlag('no-pub', negatable: false)
          ..addFlag(
            'compress-native',
            defaultsTo: true,
            help: 'Compress native libraries in the APK; Android extracts them at install time.',
          ),
      )
      ..addCommand(
        'verify',
        commandParser()..addMultiOption(
          'abis',
          allowed: ['armeabi-v7a', 'arm64-v8a', 'x86_64'],
          help:
              'Require exactly these ABIs; omitted verifies all packaged ABIs.',
        ),
      );
    final args = parser.parse(arguments);
    final command = args.command;
    if ((args['help'] as bool) || (command?['help'] as bool? ?? false)) {
      stdout.writeln(
        'Usage: dart scripts/android.dart <init-signing|build|verify>\n${command == null ? parser.usage : parser.commands[command.name]!.usage}',
      );
      return;
    }
    if (command == null) {
      throw ArgumentError(
        'Usage: dart scripts/android.dart <init-signing|build|verify>',
      );
    }
    switch (command.name) {
      case 'init-signing':
        if (command.rest.isNotEmpty) {
          throw ArgumentError('init-signing accepts no arguments');
        }
        await initializeSigning();
      case 'build':
        if (command.rest.isNotEmpty) {
          throw ArgumentError('build accepts no positional arguments');
        }
        await buildApk(
          mode: command['mode'] as String,
          abi: command['abi'] as String,
          noPub: command['no-pub'] as bool,
          compressNative: command['compress-native'] as bool,
        );
      case 'verify':
        if (command.rest.length != 1) {
          throw ArgumentError('verify requires one APK path');
        }
        final expected = command.multiOption('abis');
        await verifyApk(
          File(command.rest.single),
          expected.isEmpty ? null : expected,
        );
    }
  } on Object catch (error) {
    stderr.writeln('Android packaging failed: $error');
    exitCode = 1;
  }
}
