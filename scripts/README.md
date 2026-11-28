# 仓库脚本

在仓库根目录运行，格式为 `dart --disable-dart-dev scripts/<脚本>.dart`。各脚本加 `--help` 查看全部参数。`src/` 里是脚本共用的实现，不要直接运行。

## 常用命令

| 要做的事 | 命令 |
| --- | --- |
| 构建 Android APK | `android.dart build`。`--abi all` 构建三个 ABI 包和一个通用包，构建号相同；`--abi universal` 只构建通用包 |
| 校验已构建的 APK | `android.dart verify <APK> [--abis ...]`，检查签名、ABI、manifest 和共享资源，和 `build` 结束时的检查相同 |
| 构建桌面或 Apple 安装包 | `build_host.dart <平台> --arch <架构> --installers` |
| 构建 iOS | 真机编译归档：`build_host.dart ios`；模拟器包：`build_host.dart ios --simulator` |
| 更新生成文件和共享资源 | `generate.dart`；只检查是否过期：`generate.dart --check` |
| 完整检查（提交前） | `./scripts/check.sh`；加 `--android` 额外构建并校验一个调试 APK（默认 arm64，用环境变量 `ANDROID_TARGET_PLATFORM` 换 ABI） |
| 更新设计 token | 见 [design_tokens](design_tokens/README.md) |
| 导出应用图标 | `npm run generate --prefix scripts/app_icons`；检查：`npm run check --prefix scripts/app_icons` |

- 构建命令结束时会自动校验最终产物。
- 被控手机上的程序（scrcpy server、companion、helpers）不在这里构建，统一用 `servers/build.dart`，见[被控程序构建](../servers/README.md)。
- 测试的选择和运行见[测试说明](../test/README.md)。

## 应用图标

图标从 [SVG 主稿](../designs/assets/app-icon.svg)导出。改了主稿后，用 Node 20.9 及以上运行：

```sh
npm ci --ignore-scripts --prefix scripts/app_icons
npm run generate --prefix scripts/app_icons
npm run check --prefix scripts/app_icons
```

平台构建直接使用已提交的图标文件，不会重新导出。

## 打包选项

- 更新渠道：Android 和桌面构建都接受 `--update-feed <HTTPS 地址>`，写入应用检查更新时使用的地址。
- 签名指纹：`android.dart build` 和 `verify` 都接受 `--signer-sha256 <证书指纹>`，签名证书不符时失败，防止用错密钥。
- 本地 Android 签名读取 `app/android/key.properties`（可用 `android.dart init-signing` 生成）。CI 改用四个环境变量：`ANDROID_SIGNING_STORE_FILE`、`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_ALIAS`、`ANDROID_SIGNING_KEY_PASSWORD`，必须四个都设置。
- 桌面打包加 `--verify-only` 时不重新构建，直接校验并打包已构建好的同架构应用。
- Linux 打包需要 `dpkg-deb`、`rpmbuild`、`file`、`desktop-file-validate`、`appstreamcli` 和 `squashfs-tools`。
- Windows 安装器由 Inno Setup 的 `ISCC.exe` 生成。
- macOS 试打包直接生成 DMG。
- 排查编译慢：`build_host.dart windows --verbose` 输出 Flutter、CMake、FFmpeg 和媒体 Rust 的原生构建日志。

## 发布

- `release.dart`：读取应用版本和 [CHANGELOG](../CHANGELOG.md)，检查标签，把通过校验的包整理成 GitHub Release 附件。
- `release_media_source.py`：收集按锁文件校验过的媒体库源码、补丁和构建工具，生成媒体源码归档。
- CI、试打包和正式发布流程见[发布说明](../docs/releasing.md)。

## 清理构建缓存

下面的目录不会自动清理，磁盘紧张时可以直接删除。代价是下次构建要从头编译 Rust 和 Flutter，耗时明显变长；不影响源码和已提交的文件。

| 目录 | 内容 |
| --- | --- |
| `target/` | Rust（Cargo）编译产物。`packages/adb` 和 `packages/scrcpy` 的构建钩子把 `CARGO_TARGET_DIR` 设为这里，所有构建配置共用一份 |
| `app/build/` | Flutter 构建输出（APK、桌面包等） |
| `.dart_tool/hooks_runner/` | Dart 原生资产钩子的工作目录 |
| `app/.dart_tool/flutter_build/` | Flutter 的增量构建缓存 |

```sh
rm -rf target app/build .dart_tool/hooks_runner app/.dart_tool/flutter_build
```

不要顺手删除 `.dart_tool/media_codec/`：里面是编译好的 FFmpeg 和源码归档，重建很慢。
