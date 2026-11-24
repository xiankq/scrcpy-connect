import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:record_use/record_use.dart';

import 'native_adb.dart';

void main(List<String> args) async {
  await link(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final uses = input.recordedUses;
    // Without compiler reachability information retain the independent SDK.
    // A composed host supplies its own bindings and never initializes this SDK.
    const initialize = Method(
      'initializeNativeAdb',
      Library('package:adb/src/native/initialize.dart'),
    );
    if (uses != null && !(uses.calls[initialize]?.isNotEmpty ?? false)) return;

    // FRB 的构建器接受 BuildInput。用链接阶段的目标生成该构建配置。
    final code = input.config.code;
    final buildInput = BuildInputBuilder()
      ..setupShared(
        packageName: input.packageName,
        packageRoot: input.packageRoot,
        outputFile: input.outputFile,
        outputDirectoryShared: input.outputDirectoryShared,
      )
      ..addExtension(
        CodeAssetExtension(
          targetArchitecture: code.targetArchitecture,
          targetOS: code.targetOS,
          linkModePreference: code.linkModePreference,
          cCompiler: code.cCompiler,
          android: code.targetOS == OS.android ? code.android : null,
          iOS: code.targetOS == OS.iOS ? code.iOS : null,
          macOS: code.targetOS == OS.macOS ? code.macOS : null,
          sanitizer: code.sanitizer,
        ),
      );
    buildInput.config.setupBuild(linkingEnabled: false);
    final built = BuildOutputBuilder();
    await buildNativeAdb(buildInput.build(), built);
    final result = built.build();
    output.assets.code.addAll(result.assets.code);
    output.dependencies.addAll(result.dependencies);
  });
}
