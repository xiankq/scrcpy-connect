import 'dart:io';

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
  final service = application
      .findElements('service')
      .where(
        (item) =>
            (attribute(item, 'name') ?? '').endsWith('.ConnectionService'),
      )
      .singleOrNull;
  final types = service == null
      ? ''
      : attribute(service, 'foregroundServiceType') ?? '';
  final namedTypes = types.split('|').toSet();
  if (service == null ||
      attribute(service, 'exported') != 'false' ||
      (!['18', '0x12'].contains(types) &&
          !(namedTypes.length == 2 &&
              namedTypes.containsAll(['connectedDevice', 'mediaPlayback'])))) {
    throw StateError(
      'Packaged ConnectionService must retain its private foreground types.',
    );
  }
}

void main(List<String> arguments) {
  try {
    final root = repositoryRoot();
    final apk = File(
      arguments.isEmpty
          ? '${applicationRoot(root).path}/build/app/outputs/flutter-apk/app-debug.apk'
          : arguments.single,
    ).absolute;
    verifyApk(apk, ['armeabi-v7a', 'arm64-v8a', 'x86_64']);
    final sdk =
        Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'];
    if (sdk == null) {
      throw StateError('Set ANDROID_HOME to the Android SDK directory.');
    }
    final analyzer =
        '$sdk/cmdline-tools/latest/bin/apkanalyzer${Platform.isWindows ? '.bat' : ''}';
    final result = Process.runSync(analyzer, [
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
      'PASS: packaged Android manifest and Flutter/Rust ELF libraries for all three ABIs',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
