# 发布邻接

## 先试打包

构建配置、打包工具或依赖锁文件合入 `main` 后会自动启动试打包，并为后续发版准备依赖缓存。任何分支都可在 **Actions → Packages → Run workflow** 手动试打包。完成后，在此次运行的 **Artifacts** 下载结果。

| 平台 | 架构 | Actions 试打包 | GitHub 公开预览 | 正式发布 |
| --- | --- | --- | --- | --- |
| Android | arm64-v8a、armeabi-v7a、x86_64、通用 | 调试 APK | 4 个同签名、同构建号的 APK | 沿用发布签名 |
| Windows | x64、ARM64 | 安装器 EXE、便携 ZIP | 同试打包 | 同试打包 |
| Linux | x64、ARM64 | AppImage、DEB、RPM、tar.gz | 同试打包 | 同试打包 |
| macOS | Apple Silicon、Intel | 两个 DMG | 两个未经公证的 DMG | 配好 Developer ID 与公证后发布两个 DMG |
| iOS 和 iPadOS | arm64 | Apple 芯片 Mac 的模拟器包、未签名 iPhoneOS 编译归档 | 同试打包 | 通过 TestFlight 或 App Store 分发 |

CI 在 PR 和 `main`、`dev` 分支上运行，检查生成物、代码格式、静态分析和测试。试打包会核验原生库、运行资源和应用标识，并在对应运行器上试装、卸载 Windows 安装器和 Linux DEB。下载后仍可在真实设备验证启动和使用体验。

### 在 iOS 模拟器试用

在 Apple 芯片 Mac 上解压 `ios-simulator-arm64-debug.tar.gz`，启动一个 iPhone 或 iPad 模拟器，把解压得到的 `Runner.app` 拖进模拟器。也可在仓库根运行 `dart scripts/build_host.dart ios --simulator` 自行生成包。这个流程无需 Apple 开发者证书。

`ios-arm64-release.tar.gz` 用于检查真机目标是否能编译。要在自有 iPhone 或 iPad 调试，可以用 Apple 账号登录 Xcode，选择 Personal Team，由 Xcode 生成短期开发签名。TestFlight 和 App Store 分发需要 Apple Developer Program。 [Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)

## 公开预览和正式发布

1. 完成[发布前补充清单](release-owner-checklist.md)中首次公开所需的事项，再开启自动发布。
2. 更新 `app/pubspec.yaml`，例如 `0.2.0+2`，并在 [CHANGELOG.md](../CHANGELOG.md) 添加 `## 0.2.0`。每次公开新构建递增构建号，Android 用它判断能否覆盖升级。
3. 等改动合入 `main` 且该提交的推送 CI 通过。公开预览需设置仓库变量 `PUBLIC_PREVIEWS_ENABLED=true` 并推送 `v0.2.0-preview.1`。正式发布需设置 `PUBLIC_RELEASES_ENABLED=true` 并推送 `v0.2.0`。发布工作流核对标签对应提交的 CI 记录，再并行打包各平台。两个标签都使用同一份应用基础版本和发布签名。
4. 如果 **Release** 出现审核请求，核对标签和签名来源后批准。工作流先把所有附件上传到草稿，再公开。预览标记为 **Pre-release**，正式版标记为 **Latest** 并提供应用更新清单。
5. 从 Releases 下载文件验证。Android 用已发布的前一版本做一次覆盖安装。Windows 验证安装、卸载及便携启动。Linux 验证安装包和 AppImage。macOS 从下载的 DMG 拖入「应用程序」并启动。

发布页按操作系统和架构列出直达下载。公开预览包含 20 个客户端和编译归档，另附媒体对应源码与 `SHA256SUMS`。正式版启用 macOS 时有 18 个客户端，并提供 `release-feed.json`。更新清单保留上一版本的记录，应用从更新入口打开对应下载页面，由用户安装。

需要覆盖升级时，沿用 Android 应用 ID、Apple Bundle ID、Linux 和 Windows 的系统应用标识以及应用数据目录。改标识前要检查数据迁移、系统授权和覆盖安装。

## 替换 FFmpeg 后重新构建

安装包中的媒体模块静态链接 FFmpeg。要修改库并重新链接，下载同一 Release 的项目源码和 `media-source.tar.gz`。媒体归档含精确的上游源码、补丁、锁文件和构建脚本。

1. 解压项目源码，按 [开发环境](../CONTRIBUTING.md) 安装 Flutter、Rust 和平台 SDK。在仓库根运行 `flutter pub get --enforce-lockfile`。单独解开媒体源码包，把其 `upstream/` 里的归档复制到仓库的 `.dart_tool/media_codec/source/`，保留文件名。
2. 解开其中的 FFmpeg 上游归档，应用 `packages/media_codec/third_party/ffmpeg.lock.json` 中列出的原有补丁。把自己的改动保存为基于该源码树的 Git 补丁，放在 `packages/media_codec/third_party/patches/`。按现有条目格式将补丁的相对路径和 SHA-256 追加到锁文件。构建工具会按顺序应用补丁，并在库版本或补丁变化时重新编译。
3. 在对应系统和架构构建。Android 用 `dart scripts/android.dart build --mode debug --abi universal`；桌面用 `dart scripts/build_host.dart <linux|windows|macos> --arch <x64|arm64>`；iOS 模拟器用 `dart scripts/build_host.dart ios --simulator`。Android 也可通过 `dart scripts/android.dart init-signing` 创建自己的签名后以 `--mode release` 构建。iPhoneOS 用 `dart scripts/build_host.dart ios` 编译，再通过 Xcode 使用自己的签名安装。
4. 验证重新构建的包包含改过的媒体模块，启动后用一个短视频或一次远控画面验证解码。各平台所需 SDK 和额外工具见 [Packages 工作流](../.github/workflows/package.yml)。

## 怎么选下载包

- Android 近年的真机通常选 `arm64-v8a`。不确定架构时选通用 APK。各包可按 Android 的签名和版本规则相互覆盖。
- Windows 选与系统架构对应的安装器或便携 ZIP。ZIP 解压完整目录后运行 `Interconnect.exe`。
- Linux 在 Debian、Ubuntu 系列用 DEB，在 Fedora 系列用 RPM。AppImage 赋予执行权限后打开。没有 FUSE 的系统可以在命令前加 `APPIMAGE_EXTRACT_AND_RUN=1`，也可以解压 tar.gz 后运行 `bundle/interconnect`。构建基线为 Ubuntu 24.04。AppImage 与 tar.gz 依赖宿主 GTK 3 和媒体相关系统库。
- Linux 的 DEB 和 RPM 会声明 ADB 依赖。用 AppImage 或 tar.gz 时，先安装 Debian、Ubuntu 的 `adb` 或 Fedora 的 `android-tools`。
- Windows 和 macOS 先用 Android Studio 的 SDK Manager 安装 Android SDK Platform-Tools，或从官方页面下载后把其目录加到 `PATH`。macOS 也可通过 `brew install --cask android-platform-tools` 安装。 [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)
- macOS 在「关于本机」查看芯片，Apple 芯片选 `arm64`，Intel 处理器选 `x64`。

## 出错时怎么处理

- CI 或签名失败时，在 Actions 点开失败的步骤。更新前需要先看签名指纹，避免误用另一把密钥生成用户无法覆盖安装的 APK。
- Android 的三个 ABI 包和通用包来自同一次构建，各自通过包体和签名校验。依赖仓库返回限流或临时服务错误时，构建等待后重试一次。
- 上传中断后可以重试原标签的失败运行。只要 Release 还是草稿，工作流会补齐附件再发布。
- 已公开的版本通过新版本修正。保留已发布的标签、签名和资产，方便用户追溯手上安装的包。

`SHA256SUMS` 可用于确认下载文件与 GitHub 上传时相同。在 Linux 用 `sha256sum -c SHA256SUMS`，在 macOS 用 `shasum -a 256 -c SHA256SUMS`。Windows 可用 PowerShell 的 `Get-FileHash -Algorithm SHA256 文件名`，对照清单里同名文件的值。
