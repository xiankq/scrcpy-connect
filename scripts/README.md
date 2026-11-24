# 仓库脚本

仓库根使用 `dart --disable-dart-dev scripts/<entry>.dart`。

| 任务 | 入口 |
| --- | --- |
| Android 构建与交付校验 | `android.dart build` / `android.dart verify <APK> [--abis ...]`。用 `--abi all` 一次构建三个 ABI 包和同构建号的通用包，单独构建通用包用 `--abi universal` |
| 桌面/Apple 构建 | `build_host.dart <平台> --arch <架构> --installers`。iOS 真机编译归档用 `build_host.dart ios`，模拟器包用 `build_host.dart ios --simulator` |
| 生成及漂移检查 | `generate.dart` / `generate.dart --check` |
| 完整门禁 | `check.sh`；`--android` 默认仅 arm64 调试包 |
| 设计 token | [design_tokens](design_tokens/README.md) |
| 应用图标导出与漂移检查 | `npm run generate --prefix scripts/app_icons` / `npm run check --prefix scripts/app_icons` |

构建入口会核验最终产物；Android 的独立 `verify` 复用同一签名、ABI、manifest 与共享资源检查。`generate` 负责生成物和共享资源同步，设备端源码及产物构建统一由 `servers/build.dart` 处理。`src/` 仅放公共实现，不作为命令入口。

应用图标从 [SVG 主稿](../designs/assets/app-icon.svg)导出。修改后用 Node 20.9+ 执行 `npm ci --ignore-scripts --prefix scripts/app_icons`，再运行图标生成与检查。平台构建直接使用已提交的资源。


测试选择与运行见[测试说明](../test/README.md)；受控产物及来源保留规则见[执行端约束](../servers/AGENTS.md)。

## 试打包和正式发布

Android 和桌面构建都接受 `--update-feed <HTTPS 地址>`，给应用配置更新渠道。Android 构建和独立校验都可加 `--signer-sha256 <证书指纹>`，防止使用错误的签名证书。

本地 Android 签名沿用 `app/android/key.properties`。CI 使用 `ANDROID_SIGNING_STORE_FILE`、`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_ALIAS` 和 `ANDROID_SIGNING_KEY_PASSWORD` 一组环境输入。使用这些变量时需提供齐全。

`release.dart` 读取应用版本和变更记录，检查标签，再把通过验证的包整理成 GitHub Release 附件。`release_media_source.py` 收集按锁文件校验过的媒体源码、补丁和构建工具。CI、试打包与正式发布方式见[发布说明](../docs/releasing.md)。

桌面打包可用 `--verify-only` 复用已构建的同架构应用。Linux 发布格式需要 `dpkg-deb`、`rpmbuild`、`file`、`desktop-file-validate`、`appstreamcli` 和 `squashfs-tools`。Windows 安装器由 Inno Setup 的 `ISCC.exe` 生成。macOS 试打包直接生成 DMG。
