import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'native_adb.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // 链接阶段能根据应用实际调用决定是否需要独立 ADB 库。
    if (!input.config.buildCodeAssets || input.config.linkingEnabled) return;
    await buildNativeAdb(input, output);
  });
}
