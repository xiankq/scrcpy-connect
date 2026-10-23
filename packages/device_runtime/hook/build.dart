import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';

import 'dart:io';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final environment = <String, String>{};
    final code = input.config.code;
    if (code.targetOS == OS.android) {
      // native_toolchain_rust 1.0.7 hard-codes API 35. Respect the runner's
      // minimum API instead, otherwise a successful build can fail on API 24.
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
      cratePath: '../../crates/interop_bridge',
      extraCargoEnvironmentVariables: environment,
    ).run(input: input, output: output);
  });
}
