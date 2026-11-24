import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main() async {
  final work = await Directory.systemTemp.createTemp('adb-hook-test-');
  try {
    final package = Platform.script.resolve('../');
    final recordedUses = work.uri.resolve('recorded_uses.json');
    await File.fromUri(recordedUses).writeAsString('{}');
    final buildInput = BuildInputBuilder()
      ..config.setupBuild(linkingEnabled: true);
    final linkInput = LinkInputBuilder()
      ..setupLink(
        assets: [],
        assetsFromLinking: [],
        recordedUsesFile: recordedUses,
      );

    for (final (name, input) in [('build', buildInput), ('link', linkInput)]) {
      final output = work.uri.resolve('$name-output.json');
      input
        ..setupShared(
          packageName: 'adb',
          packageRoot: package,
          outputFile: output,
          outputDirectoryShared: work.uri,
        )
        ..addExtension(
          CodeAssetExtension(
            targetArchitecture: Architecture.x64,
            targetOS: OS.linux,
            linkModePreference: LinkModePreference.dynamic,
          ),
        );

      final config = File.fromUri(work.uri.resolve('$name-input.json'));
      await config.writeAsString(jsonEncode(input.json));
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          package.resolve('hook/$name.dart').toFilePath(),
          '--config',
          config.path,
        ],
        environment: {'RUSTUP_TOOLCHAIN': 'missing-adb-hook-test-toolchain'},
      );
      if (result.exitCode != 0) {
        throw StateError(
          'ADB $name hook attempted to build an unused library.',
        );
      }
      final json = jsonDecode(
        await File.fromUri(output).readAsString(),
      ) as Map<String, Object?>;
      final assets = json['assets'] as List<Object?>?;
      final linkAssets = json['assets_for_linking'] as Map<String, Object?>?;
      if (assets?.isNotEmpty == true || linkAssets?.isNotEmpty == true) {
        throw StateError('ADB $name hook emitted an unused library.');
      }
    }
  } finally {
    await work.delete(recursive: true);
  }
}
