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
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: '../../rust/scrcpy/bridge',
      assetName: 'src/native/generated/frb_generated.io.dart',
    ).run(input: input, output: output);
  });
}
