# Android 打包

仓库根运行，需Flutter、JDK21及Android SDK：

```sh
dart --disable-dart-dev tool/android.dart init-signing
dart --disable-dart-dev tool/android.dart build
dart --disable-dart-dev tool/android.dart verify app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

默认生成三个独立ABI包；`build --abi arm64` 只构建指定架构，`--abi universal` 生成通用包。APK位于 `app/build/app/outputs/flutter-apk/`。

首次初始化创建本机签名身份，重复执行保留原身份。私钥与key.properties不入Git；更新安装沿用原签名，不自动卸载或清数据。

构建器核对签名、ABI、ZIP/CRC、ELF对齐与共享执行资源。切换release与集成测试时重新准备依赖，避免错误插件注册；同一工作区串行构建。

被控助手按被控ABI选择，不随主控ABI裁剪。来源、许可证及缓存见[工具链](repository-tooling.md)。
