# Android 打包、签名与安装

构建输入和资源边界见[工具链契约](repository-tooling.md)，实现入口为 `tool/android.dart` 与 `app/android/`。

## 签名与 ABI

release 构建在编译前校验本机签名配置；缺少身份时拒绝生成不可安装的包，不回退 debug 签名。`init-signing` 创建 RSA-3072 JKS 身份、随机密码和权限 600 的配置；重复执行保留原身份。私钥与 `key.properties` 不进入 Git，更新安装必须使用同一签名，工具不自动卸载旧应用或清除数据。

通用包包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`，构建按请求平台过滤 Flutter、插件和 Rust ABI。`--split-per-abi` 使用 Flutter 自身路径，检查真实 ELF 身份，不能只看目录名。默认压缩原生库以减少下载大小；安装后占用与下载大小分别衡量。

## 构建与核验

在仓库根运行，要求 Flutter、JDK 21 和 `ANDROID_HOME` 可用：

```sh
dart tool/android.dart init-signing
dart tool/android.dart build
dart tool/android.dart build --abi arm64
dart tool/android.dart build --abi x64
dart tool/android.dart verify app/build/app/outputs/flutter-apk/app-release.apk
```

验证调用 SDK `apksigner`、`aapt2`、`zipalign`，核对 Manifest、ZIP 条目与 CRC、各 ABI Flutter/Rust/AOT ELF、共享六份服务端资源及 16 KiB 对齐。重复 ZIP 名、损坏 CRC、错误架构和来源漂移必须拒绝；“Built”不替代独立检查。发布来源见 [Flutter Android 部署](https://docs.flutter.dev/deployment/android)与 [apksigner](https://developer.android.com/tools/apksigner)。

## 测试插件注册

release 准备会排除开发测试插件。集成测试后直接 `--no-pub` release 可能保留指向 `integration_test` 的旧注册器，切回 debug 也可能缺截图插件。模式或入口切换时先执行正常依赖准备，再由工具检查注册状态；不手改 `GeneratedPluginRegistrant`，不把测试插件塞入正式包，也不通过跳过截图或媒体断言规避失败。

## 产物

普通 main、debug/profile 夹具、不同 ABI 和签名模式分别记录身份。保留交付包与仍在复用的缓存，清理过期中间目录和重复 APK；来源归档、许可证和受控 JAR/helper 不属于可重建垃圾。实际构建环境与运行边界见[验收记录](validation.md)。
