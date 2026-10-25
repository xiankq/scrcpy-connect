# 被控临时程序

通过已授权 ADB 临时执行，不安装配套 APK。

| 目录 | 职责 |
| --- | --- |
| [vendor](vendor/README.md) | 固定 scrcpy 视频、音频与控制 JAR |
| [companion](companion/README.md) | Binder 观察、剪贴板、应用信息与缩略图 |
| [helpers](helpers/README.md) | 四种被控 ABI 的原生文件助手 |

根目录 `flutter pub get` 后运行：

```sh
dart --disable-dart-dev servers/vendor/build.dart --check
dart --disable-dart-dev servers/companion/build.dart --check
dart --disable-dart-dev servers/helpers/build.dart --check
dart --disable-dart-dev servers/package.dart --check
```

`--check` 离线核对摘要；各构建器的 `--rebuild` 临时重建并逐字节比较。修改输入后按对应说明更新产物，再运行 `dart --disable-dart-dev servers/package.dart`。

唯一资源目录为 `app/assets/servers/`；文件助手按被控 ABI 选择，不随主控 APK ABI 裁剪。许可证及对应源码归档随受控输入保留，见[工具链](../docs/implementation/repository-tooling.md)。
