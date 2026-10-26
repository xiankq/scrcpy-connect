import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../scripts/src/repository_tooling.dart';
import '../scripts/src/process.dart';

/// 用已解析的 SDK 和编译器输入编译真实协调源码，再在 JVM 上验证硬件接口，不使用 framework stub。
///
Future<void> main(List<String> arguments) async {
  Directory? temporary;
  try {
    final kind = arguments.isEmpty ? 'all' : arguments.single;
    if (!['all', 'audio', 'ownership'].contains(kind)) {
      throw ArgumentError(
        'Usage: dart test/native_contracts.dart [all|audio|ownership]',
      );
    }
    final root = repositoryRoot();
    final android = path.join(applicationRoot(root).path, 'android');
    final properties = <String, String>{};
    for (final line in File(
      path.join(android, 'local.properties'),
    ).readAsLinesSync()) {
      if (line.trimLeft().startsWith('#')) continue;
      final split = line.indexOf('=');
      if (split < 0) continue;
      properties[line.substring(0, split).trim()] = line
          .substring(split + 1)
          .replaceAll(r'\:', ':')
          .replaceAll(r'\=', '=')
          .replaceAll(r'\\', r'\');
    }
    final settings = File(path.join(android, 'settings.gradle.kts'))
        .readAsStringSync();
    final version = RegExp(
      r'id\("org.jetbrains.kotlin.android"\) version "([^"]+)"',
    ).firstMatch(settings)![1]!;
    final userHome =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;
    final cache = path.join(
      Platform.environment['GRADLE_USER_HOME'] ??
          path.join(userHome, '.gradle'),
      'caches/modules-2/files-2.1',
    );
    File artifact(
      String group,
      String name,
      String release, [
      String extension = 'jar',
    ]) {
      final directory = Directory(path.join(cache, group, name, release));
      final files = directory.existsSync()
          ? directory
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (file) =>
                      path.basename(file.path) == '$name-$release.$extension',
                )
                .toList()
          : <File>[];
      if (files.length != 1) {
        throw StateError(
          'Run the project native Gradle compile first; missing local $name:$release',
        );
      }
      return files.single;
    }

    final compiler = artifact(
      'org.jetbrains.kotlin',
      'kotlin-compiler-embeddable',
      version,
    );
    final pom = XmlDocument.parse(
      artifact(
        'org.jetbrains.kotlin',
        'kotlin-compiler-embeddable',
        version,
        'pom',
      ).readAsStringSync(),
    );
    final compilerJars = [compiler.path];
    for (final dependency
        in pom
            .findAllElements('dependencies')
            .single
            .findElements('dependency')) {
      String text(String name) =>
          dependency.findElements(name).single.innerText;
      final scopes = dependency.findElements('scope');
      final scope = scopes.isEmpty ? 'compile' : scopes.single.innerText;
      if (scope == 'compile' || scope == 'runtime') {
        compilerJars.add(
          artifact(text('groupId'), text('artifactId'), text('version')).path,
        );
      }
    }
    final annotations = Directory(
      path.join(cache, 'org.jetbrains/annotations'),
    );
    if (annotations.existsSync()) {
      final jars =
          annotations
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.jar'))
              .map((file) => file.path)
              .toList()
            ..sort();
      if (jars.isNotEmpty) compilerJars.add(jars.last);
    }
    final stdlib = artifact(
      'org.jetbrains.kotlin',
      'kotlin-stdlib',
      version,
    ).path;
    final sdk = path.join(
      properties['sdk.dir']!,
      'platforms/android-36/android.jar',
    );
    final flutter = path.join(
      properties['flutter.sdk']!,
      'bin/cache/artifacts/engine/android-x64/flutter.jar',
    );
    if (!File(sdk).existsSync() || !File(flutter).existsSync()) {
      throw StateError(
        'Project Android 36 SDK and Flutter android-x64 engine cache are required.',
      );
    }
    final javaHome = Platform.environment['JAVA_HOME'];
    final java = javaHome == null
        ? executable('java')
        : path.join(javaHome, 'bin', Platform.isWindows ? 'java.exe' : 'java');
    if (java == null) throw StateError('Install JDK 21 or set JAVA_HOME.');
    final separator = Platform.isWindows ? ';' : ':';
    final source = path.join(
      android,
      'app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect',
    );
    final tests = path.join(
      android,
      'app/src/test/kotlin/dev/scrcpyconnect/scrcpy_connect',
    );
    temporary = Directory.systemTemp.createTempSync(
      'interop-native-contracts-',
    );
    Future<void> compile(List<String> sources) => runStreamingProcess(java, [
      '-Xmx768m',
      '-cp',
      compilerJars.join(separator),
      'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
      '-no-stdlib',
      '-no-reflect',
      '-jvm-target',
      '17',
      '-classpath',
      [stdlib, sdk, flutter].join(separator),
      '-d',
      temporary!.path,
      ...sources,
    ]);
    Future<void> execute(String name, {bool embedding = false}) =>
        runStreamingProcess(java, [
          '-cp',
          [temporary!.path, stdlib, if (embedding) flutter].join(separator),
          'dev.scrcpyconnect.scrcpy_connect.$name',
        ]);
    if (kind != 'audio') {
      await compile([
        path.join(source, 'BackgroundKeepAliveState.kt'),
        path.join(tests, 'BackgroundKeepAliveTest.kt'),
        path.join(source, 'AudioSessionOwnership.kt'),
        path.join(source, 'NativeLeaseOwnership.kt'),
        path.join(tests, 'NativeOwnershipTest.kt'),
        path.join(tests, 'ActivityLeaseTest.kt'),
        path.join(source, 'IncomingShareOwner.kt'),
        path.join(tests, 'IncomingShareOwnerTest.kt'),
        path.join(source, 'IncomingShares.kt'),
        path.join(source, 'PlatformDocuments.kt'),
        path.join(tests, 'documents/DocumentPickerReplyTest.kt'),
      ]);
      await execute('NativeOwnershipTest');
      await execute('BackgroundKeepAliveTest');
      await execute('ActivityLeaseTest');
      await execute('DocumentPickerReplyTest', embedding: true);
      await execute('IncomingShareOwnerTest');
    }
    if (kind != 'ownership') {
      await compile([
        path.join(source, 'AudioFocusController.kt'),
        path.join(tests, 'AudioPlaybackTest.kt'),
      ]);
      await execute('AudioPlaybackTest');
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    temporary?.deleteSync(recursive: true);
  }
}
