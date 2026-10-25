import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';

import 'dart:io';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    // 监督器由 build.rs 单独调用 rustc 构建；显式登记 Cargo 库 dep-info 之外的输入。
    output.dependencies.addAll([
      input.packageRoot.resolve('../../rust/scrcpy/bridge/build.rs'),
      for (final source in [
        'build.rs',
        'supervisor/main.rs',
        'supervisor/protocol.rs',
      ])
        input.packageRoot.resolve('../../rust/adb/api/$source'),
    ]);
    final environment = <String, String>{};
    final code = input.config.code;
    if (code.targetOS == OS.android) {
      // native_toolchain_rust 1.0.7 固定使用 API 35；此处遵循 runner 的最低 API，
      // 避免构建成功却无法在 API 24 运行。
      final triples = switch (code.targetArchitecture) {
        Architecture.arm64 => (
          'aarch64-linux-android',
          'aarch64-linux-android',
        ),
        Architecture.arm => (
          'armv7-linux-androideabi',
          'armv7a-linux-androideabi',
        ),
        Architecture.x64 => ('x86_64-linux-android', 'x86_64-linux-android'),
        _ => throw UnsupportedError('Unsupported Android architecture'),
      };
      final binaryDirectory = code.cCompiler!.compiler.resolve('.');
      final api = code.android.targetNdkApi;
      final suffix = Platform.isWindows ? '.cmd' : '';
      final clang = File.fromUri(
        binaryDirectory.resolve('${triples.$2}$api-clang$suffix'),
      ).path;
      final clangCpp = File.fromUri(
        binaryDirectory.resolve('${triples.$2}$api-clang++$suffix'),
      ).path;
      final key = triples.$1.replaceAll('-', '_');
      environment['CC_$key'] = clang;
      environment['CXX_$key'] = clangCpp;
      environment['CARGO_TARGET_${key.toUpperCase()}_LINKER'] = clang;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../../rust/scrcpy/bridge',
      assetName: 'src/native/generated/frb_generated.io.dart',
      extraCargoEnvironmentVariables: environment,
    ).run(input: input, output: output);
  });
}
