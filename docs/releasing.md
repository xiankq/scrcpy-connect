# 发布邻接

## 先试打包

工作流合入默认分支后，在 GitHub 打开 **Actions → Packages → Run workflow**，选择要验证的分支。推送 `codex/package-preview` 也会启动试打包。完成后，在此次运行的 **Artifacts** 下载结果。

| 平台 | 架构 | 试打包 | GitHub Release |
| --- | --- | --- | --- |
| Android | arm64-v8a、armeabi-v7a、x86_64、通用 | 调试 APK | 4 个同签名、同构建号的 APK |
| Windows | x64、ARM64 | 安装器 EXE、便携 ZIP | 同左 |
| Linux | x64、ARM64 | AppImage、DEB、RPM、tar.gz | 同左 |
| macOS | Apple Silicon、Intel | 两个本机试用 DMG | 配好 Developer ID 与公证后发布两个 DMG |
| iOS 和 iPadOS | arm64 | Apple 芯片 Mac 的模拟器包、未签名 iPhoneOS 编译归档 | 通过 TestFlight 或 App Store 分发 |

CI 在 PR 和 `main`、`dev` 分支上运行，检查生成物、代码格式、静态分析和测试。试打包也会核验安装包中的原生库、运行资源和应用标识。下载到干净系统运行，才能确认真实的安装和启动体验。

### 在 iOS 模拟器试用

在 Apple 芯片 Mac 上解压 `ios-simulator-arm64-debug.tar.gz`，启动一个 iPhone 或 iPad 模拟器，把解压得到的 `Runner.app` 拖进模拟器。也可在仓库根运行 `dart scripts/build_host.dart ios --simulator` 自行生成包。这个流程无需 Apple 开发者证书。

`ios-arm64-release.tar.gz` 用于检查真机目标是否能编译。要在自有 iPhone 或 iPad 调试，可以用 Apple 账号登录 Xcode，选择 Personal Team，由 Xcode 生成短期开发签名。TestFlight 和 App Store 分发需要 Apple Developer Program。 [Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)

## 正式发布

1. 完成[发布前补充清单](release-owner-checklist.md)中首次公开所需的事项，再开启自动发布。
2. 更新 `app/pubspec.yaml` 中的版本与构建号，例如 `0.2.0+2`。Google Play 以外的此套 APK 也使用构建号判断覆盖升级，两个数字都应递增。在 [CHANGELOG.md](../CHANGELOG.md) 添加对应的 `## 0.2.0` 标题，用项目符号写用户可见变化。
3. 等改动合入 `main` 且 CI 通过。在该提交创建并推送 `v0.2.0` 标签。标签触发 **Release**，通过代码检查后构建上表所列的公开包。
4. 检查 **Release** 中出现的审核请求，确认标签与签名来源正确后批准。工作流会先将所有附件上传到草稿，再将完成的版本设为 **Latest**。
5. 从 Releases 下载文件验证。Android 用已发布的前一版本做一次覆盖安装。Windows 验证安装、卸载及便携启动。Linux 验证安装包和 AppImage。macOS 从下载的 DMG 拖入「应用程序」并启动。

发布页按操作系统和架构列出直达下载。启用 macOS 后共 18 个客户端附件，另有媒体对应源码包、`SHA256SUMS` 和 `release-feed.json`。更新清单保留上一版本已有的记录，并把用户带到所选版本的下载页面。应用不会代替系统安装新版。内部试打包沿用本地验证渠道。

需要覆盖升级时，沿用 Android 应用 ID、Apple Bundle ID、Linux 和 Windows 的系统应用标识以及应用数据目录。改标识前要检查数据迁移、系统授权和覆盖安装。

## 怎么选下载包

- Android 近年的真机通常选 `arm64-v8a`。不确定架构时选通用 APK。各包可按 Android 的签名和版本规则相互覆盖。
- Windows 选与系统架构对应的安装器或便携 ZIP。ZIP 解压完整目录后运行 `Interconnect.exe`。
- Linux 在 Debian、Ubuntu 系列用 DEB，在 Fedora 系列用 RPM。AppImage 赋予执行权限后打开。没有 FUSE 的系统可以在命令前加 `APPIMAGE_EXTRACT_AND_RUN=1`，也可以解压 tar.gz 后运行 `bundle/interconnect`。构建基线为 Ubuntu 24.04。AppImage 与 tar.gz 依赖宿主 GTK 3 和媒体相关系统库。
- Linux ARM64 从发行版读取 `/usr/bin/adb`。DEB 和 RPM 会声明这个依赖。用 AppImage 或 tar.gz 时，先安装 Debian、Ubuntu 的 `adb` 或 Fedora 的 `android-tools`。
- macOS 在「关于本机」查看芯片，Apple 芯片选 `arm64`，Intel 处理器选 `x64`。Actions 的试用 DMG 用于构建验证。用于公开下载的 DMG 由签名和公证流程交付。

## 出错时怎么处理

- CI 或签名失败时，在 Actions 点开失败的步骤。更新前需要先看签名指纹，避免误用另一把密钥生成用户无法覆盖安装的 APK。
- 上传中断后可以重试原标签的失败运行。只要 Release 还是草稿，工作流会补齐附件再发布。
- 已公开的版本通过新版本修正。保留已发布的标签、签名和资产，方便用户追溯手上安装的包。

`SHA256SUMS` 可用于确认下载文件与 GitHub 上传时相同。在 Linux 用 `sha256sum -c SHA256SUMS`，在 macOS 用 `shasum -a 256 -c SHA256SUMS`。Windows 可用 PowerShell 的 `Get-FileHash -Algorithm SHA256 文件名`，对照清单里同名文件的值。
