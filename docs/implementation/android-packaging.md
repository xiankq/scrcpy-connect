# Android 打包、签名与安装

构建输入和资源边界见[工具链契约](repository-tooling.md)，实现入口为 `tool/android.dart` 与 `app/android/`。

## 签名与 ABI

release 构建在编译前校验本机签名配置；缺少身份时拒绝生成不可安装的包，不回退 debug 签名。`init-signing` 创建 RSA-3072 JKS 身份、随机密码和权限 600 的配置；重复执行保留原身份。私钥与 `key.properties` 不进入 Git，更新安装必须使用同一签名，工具不自动卸载旧应用或清除数据。

默认使用 Flutter `--split-per-abi` 输出 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三份独立 APK，用户只安装与主控匹配的一份。`--abi universal` 显式生成包含三种主控 ABI 的兼容包；`--abi arm64` 等只构建指定目标。默认压缩原生库，下载字节、ZIP 解压载荷与实际安装空间分别衡量。

应用通过 scrcpy 组合宿主使用同库 ADB 登记；release 不重复分发独立 ADB 桥。ADB 包仍可独立使用，其 link hook 根据独立初始化入口的实际可达性保留原生资产。调试或缺少可达性信息时保守保留。共享被控执行资源按被控 ABI 选择，不能跟随主控 ABI 裁剪。

## 构建与核验

在仓库根运行，要求 Flutter、JDK 21 和 `ANDROID_HOME` 可用：

```sh
dart --disable-dart-dev tool/android.dart init-signing
dart --disable-dart-dev tool/android.dart build
dart --disable-dart-dev tool/android.dart build --abi arm64
dart --disable-dart-dev tool/android.dart build --abi universal
dart --disable-dart-dev tool/android.dart verify app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

工具本身是宿主 Dart 程序，`--disable-dart-dev` 直接运行 VM，避免先在宿主编译一遍与打包无关的原生 hooks；工具内的 Flutter 构建仍正常执行目标 hooks。

验证调用 SDK `apksigner`、`aapt2`、`zipalign`，核对 Manifest、ZIP 条目与 CRC、各 ABI Flutter/Rust/AOT/媒体 ELF、共享服务端资源及 16 KiB 对齐。重复 ZIP 名、损坏 CRC、错误架构、重复独立 ADB 库和来源漂移必须拒绝；输出回执同时记录各 ABI 压缩／展开字节和 ZIP 开销。“Built”不替代独立检查。

## 测试插件注册

release 准备会排除开发测试插件。集成测试后直接 `--no-pub` release 可能保留指向 `integration_test` 的旧注册器，切回 debug 也可能缺截图插件。模式或入口切换时先执行正常依赖准备，再由工具检查注册状态；不手改 `GeneratedPluginRegistrant`，不把测试插件塞入正式包，也不通过跳过截图或媒体断言规避失败。

## 产物

普通 main、debug/profile 夹具、不同 ABI 和签名模式分别记录身份。保留交付包与仍在复用的缓存，清理过期中间目录和重复 APK；来源归档、许可证和受控 JAR/helper 不属于可重建垃圾。实际构建环境与运行边界见[验收记录](validation.md)。
