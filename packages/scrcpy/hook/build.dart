import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';

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
    final rustOutput = BuildOutputBuilder();
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../../rust/scrcpy/bridge',
      assetName: 'src/native/generated/frb_generated.io.dart',
      // 各构建配置共用仓库 Cargo 目标目录；默认每个配置各占约 1 GB 的独立目录且不回收。
      extraCargoEnvironmentVariables: {
        'CARGO_TARGET_DIR': input.packageRoot
            .resolve('../../target')
            .toFilePath(),
      },
    ).run(input: input, output: rustOutput);
    final built = rustOutput.build();
    output.assets.code.addAll(built.assets.code);
    // 保留源文件作为输入，监督器二进制由 Cargo 在本轮生成。
    output.dependencies.addAll(
      built.dependencies.where(
        (uri) => !uri.path.endsWith('/out/interop-adb-supervisor'),
      ),
    );
  });
}
