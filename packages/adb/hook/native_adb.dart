import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

Future<({List<CodeAsset> assets, Iterable<Uri> dependencies})> buildNativeAdb(
  BuildInput input,
) async {
  final output = BuildOutputBuilder();
  // 监督器由 build.rs 单独调用 rustc 构建；显式登记 Cargo 库 dep-info 之外的输入。
  output.dependencies.addAll([
    input.packageRoot.resolve('../../rust/adb/bridge/build.rs'),
    for (final source in [
      'build.rs',
      'supervisor/main.rs',
      'supervisor/protocol.rs',
    ])
      input.packageRoot.resolve('../../rust/adb/api/$source'),
  ]);
  await FlutterRustBridgeNativeAssetsBuilder(
    cratePath: '../../rust/adb/bridge',
    assetName: 'src/native/generated/frb_generated.io.dart',
    // 各构建配置共用仓库 Cargo 目标目录；默认每个配置各占约 1 GB 的独立目录且不回收。
    extraCargoEnvironmentVariables: {
      'CARGO_TARGET_DIR': input.packageRoot
          .resolve('../../target')
          .toFilePath(),
    },
  ).run(input: input, output: output);
  final built = output.build();
  return (
    assets: built.assets.code,
    // 监督器二进制是本轮 Cargo 的中间产物，输入由上面登记的源码覆盖。
    dependencies: built.dependencies.where(
      (uri) => !uri.path.endsWith('/out/interop-adb-supervisor'),
    ),
  );
}
