# 被控临时程序

通过已授权 ADB 临时执行，不安装配套 APK。

| 目录 | 职责 |
| --- | --- |
| [vendor](vendor/README.md) | 固定 scrcpy 视频、音频与控制 JAR |
| [companion](companion/README.md) | 通知与通话观察、运行任务、图标与缩略图 |
| [helpers](helpers/README.md) | 四种被控 ABI 的原生文件助手 |

唯一入口为 `servers/build.dart`。根目录先 `flutter pub get`：

```sh
# 离线检查全部固定来源、源码/构建器摘要及共享资源
dart --disable-dart-dev servers/build.dart --check
# 更新自有程序及共享资源
dart --disable-dart-dev servers/build.dart --update companion helpers assets
# 临时重建指定程序并逐字节比较，不替换受控产物
dart --disable-dart-dev servers/build.dart --rebuild companion helpers
```

省略模式默认为 `--check`，省略目标为全部；可选择 `vendor`、`companion`、`helpers`、`assets`，资源始终最后处理。`--update assets` 只同步压缩载荷，必须已有与 manifest 匹配的受控输入。上游重建的工具链与来源选项见 [vendor](vendor/README.md)。各子目录构建器与 `package.dart` 只提供内部实现，不另设命令入口。

标准 ADB 承担文件传输和普通命令，scrcpy 承担画面、音频、输入、文本剪贴板和安装应用查询；扩展只保留其未覆盖的结构化观察、原通知动作、有界缩略图及严格文件原语。文件 helper 保留目录失败语义和原子拒绝覆盖，不能用普通 `mv -n` 替代。

唯一资源目录为 `app/assets/servers/`；文件助手按被控 ABI 选择，不随主控 APK ABI 裁剪。许可证及对应源码归档随受控输入保留，见[执行端构建约束](AGENTS.md)。
