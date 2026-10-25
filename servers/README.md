# 被控 Android 临时程序

这里的程序由已授权 ADB 临时部署到被控设备，通过 shell 身份执行，不安装配套 APK。

| 目录 | 产物与职责 | 构建与边界 |
| --- | --- | --- |
| `vendor/` | 固定版本 scrcpy JAR：远控的视频、音频、控制和查询 | [来源、API 21 脱糖与许可证](vendor/README.md) |
| `companion/` | 自有 Binder JAR：通知、通话观察、剪贴板、应用信息及媒体缩略图 | [协议、权限与生命周期](companion/README.md) |
| `helpers/` | 四种被控 ABI 的原生文件助手：元数据、目录枚举与原子发布 | [文件语义与 Rust 源码](helpers/README.md) |

各目录的 manifest 记录真实构建输入与产物摘要。`package.dart` 核对六个产物后压缩到唯一应用资源目录 `app/assets/servers/`；主控使用同一份资源，根据被控能力选择部署。文件助手 ABI 属于被控设备，不随主控安装包 ABI 裁剪。`tooling.dart` 共用 Java/DEX 编译、确定性 ZIP 和临时目录管理。

先在仓库根运行 `flutter pub get`。日常离线检查不启动原生编译：

```sh
dart --disable-dart-dev servers/vendor/build.dart --check
dart --disable-dart-dev servers/companion/build.dart --check
dart --disable-dart-dev servers/helpers/build.dart --check
dart --disable-dart-dev servers/package.dart --check
```

修改构建输入后，用对应构建器重新生成产物和 manifest，再运行 `dart --disable-dart-dev servers/package.dart`。三个构建器的 `--rebuild` 均在不替换受控产物的情况下编译并逐字节比较；工具链要求和更新命令见上表。兼容测试与设备探针独立执行，摘要检查和重建成功不代表真实设备功能已验收。

受控 JAR、助手、许可证和对应源码归档均需保留；编译缓存和临时输出的边界见[工具链契约](../docs/implementation/repository-tooling.md)。

构建日志直接流向终端；需要解析的工具回执使用有界输出和有限等待，失败后确认自有进程退出再删除临时编译目录。共享进程实现属于 manifest 追踪输入，修改后须通过实际构建链更新来源记录。
