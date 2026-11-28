# 被控临时程序

这些程序通过已授权的 ADB 推到被控手机上临时运行，手机上不需要安装配套 APK。

| 目录 | 做什么 |
| --- | --- |
| [vendor](vendor/README.md) | 固定版本的 scrcpy server JAR：视频、音频、控制 |
| [companion](companion/README.md) | 通知和通话观察、运行中的任务、应用图标、缩略图 |
| [helpers](helpers/README.md) | 文件助手，按被控手机的四种 ABI 各一份 |

## 构建

只有 `servers/build.dart` 一个入口；各子目录的构建器和 `package.dart` 是它的内部实现，不要单独运行。先在仓库根目录运行 `flutter pub get`。

```sh
# 离线检查：固定来源、源码和构建器摘要、共享资源是否一致（不改文件）
dart --disable-dart-dev servers/build.dart --check
# 重新构建自有程序，并更新共享资源
dart --disable-dart-dev servers/build.dart --update companion helpers assets
# 在临时目录重建并逐字节比较，不替换已提交的产物
dart --disable-dart-dev servers/build.dart --rebuild companion helpers
```

- 不写模式时默认 `--check`；不写目标时处理全部。目标可选 `vendor`、`companion`、`helpers`、`assets`，`assets` 总是最后处理。
- `--update assets` 只重新压缩并同步到 `app/assets/servers/`，前提是各程序的产物已经和 `manifest.json` 一致。
- 重建 scrcpy 所需的工具链和选项见 [vendor](vendor/README.md)。

## 职责划分

- ADB 负责文件传输和普通命令。
- scrcpy 负责画面、音频、输入、文本剪贴板和已安装应用列表。
- companion 和 helpers 只做这两者做不到的事：结构化的通知/通话观察、触发原通知的动作、限定大小的缩略图、严格的文件操作。
- 文件助手对目录操作如实返回失败原因，并用原子操作拒绝覆盖已有文件。普通的 `mv -n` 做不到这两点，不能拿来替代。

## 资源

- 所有被控程序打包后只放在 `app/assets/servers/`。
- 文件助手按被控手机的 ABI 选用，主控 APK 按 ABI 拆包时也保留全部四份。
- 许可证和对应源码归档跟构建输入一起保留，规则见[被控程序规则](AGENTS.md)。
