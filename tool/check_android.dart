import 'dart:io';

import 'src/process.dart';

import 'package:args/args.dart';
import 'package:xml/xml.dart';

import 'android.dart' show verifyApk;
import 'src/host.dart';

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

Future<void> main(List<String> arguments) async {
  try {
    final parser = ArgParser()
      ..addMultiOption(
        'abis',
        allowed: ['armeabi-v7a', 'arm64-v8a', 'x86_64'],
        help: 'Require exactly these ABIs; omitted means verify all packaged ABIs.',
      );
    final args = parser.parse(arguments);
    if (args.rest.length > 1) {
      throw ArgumentError('Expected at most one APK path');
    }
    final root = repositoryRoot();
    final apk = File(
      args.rest.isEmpty
          ? '${applicationRoot(root).path}/build/app/outputs/flutter-apk/app-debug.apk'
          : args.rest.single,
    ).absolute;
    final expected = args.multiOption('abis');
    final receipt = await verifyApk(apk, expected.isEmpty ? null : expected);
    final sdk =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    if (sdk == null) {
      throw StateError('Set ANDROID_HOME to the Android SDK directory.');
    }
    final analyzer =
        '$sdk/cmdline-tools/latest/bin/apkanalyzer${Platform.isWindows ? '.bat' : ''}';
    final result = await runProcess(analyzer, [
      'manifest',
      'print',
      apk.path,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      throw ProcessException(
        analyzer,
        ['manifest', 'print', apk.path],
        '${result.stderr}',
        result.exitCode,
      );
    }
    verifyManifest(result.stdout as String);
    stdout.writeln(
      'PASS: packaged Android manifest and Flutter/Rust/media ELF libraries for ${receipt['abis']}',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
