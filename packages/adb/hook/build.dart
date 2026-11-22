import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
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
      assetRouting: input.config.linkingEnabled
          ? [ToLinkHook(input.packageName)]
          : const [ToAppBundle()],
    ).run(input: input, output: output);
    // Flutter 的 build depfile 只登记直接打包的输出；交给 link hook 的库仍是
    // 后续链接的必需输入。显式登记后，库文件缺失会重跑构建，不能复用悬空回执。
    final pending = output.build().assets.encodedAssetsForLinking.values;
    for (final asset in pending.expand((assets) => assets)) {
      if (!asset.isCodeAsset) continue;
      if (asset.asCodeAsset.file case final file?) {
        output.dependencies.add(file);
      }
    }
  });
}
