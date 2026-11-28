# 发布邻接

## 先试打包

- 自动：改动了构建配置、打包工具或依赖锁文件的提交合入 `main` 后，**Packages** 工作流自动试打包，同时为之后的发版准备依赖缓存。
- 手动：任何分支都可以在 **Actions → Packages → Run workflow** 启动。完成后在这次运行的 **Artifacts** 里下载产物。
- 手动启动时的 `windows_timing` 选项：
  - `off`（默认）：跑完整的试打包矩阵。
  - `x64` 或 `x64-and-arm64`：只构建选定的 Windows 架构，并输出详细编译日志。`x64-and-arm64` 使用单独的媒体缓存，可以反复运行，对比冷构建和缓存命中时的耗时。

| 平台 | 架构 | Actions 试打包 | GitHub 公开预览 | 正式发布 |
| --- | --- | --- | --- | --- |
| Android | arm64-v8a、armeabi-v7a、x86_64、通用 | 调试 APK | 4 个同签名、同构建号的 APK | 使用发布签名 |
| Windows | x64、ARM64 | 安装器 EXE、便携 ZIP | 同试打包 | 同试打包 |
| Linux | x64、ARM64 | AppImage、DEB、RPM、tar.gz | 同试打包 | 同试打包 |
| macOS | Apple 芯片、Intel | 两个 DMG | 两个未经公证的 DMG | 配好 Developer ID 和公证后发布两个 DMG |
| iOS 和 iPadOS | arm64 | Apple 芯片 Mac 用的模拟器包、未签名的 iPhoneOS 编译归档 | 同试打包 | 通过 TestFlight 或 App Store 分发 |

CI（`ci.yml`）在 PR 以及 `main`、`dev` 分支上运行，检查生成物、代码格式、静态分析和测试。试打包会校验原生库、运行资源和应用标识，并在对应的运行器上试装、卸载 Windows 安装器和 Linux DEB。启动和实际使用仍需要下载后在真实设备上验证。

### 在 iOS 模拟器试用

在 Apple 芯片 Mac 上解压 `ios-simulator-arm64-debug.tar.gz`，启动一个 iPhone 或 iPad 模拟器，把解压出的 `Runner.app` 拖进模拟器。也可以在仓库根目录运行 `dart scripts/build_host.dart ios --simulator` 自己生成。这个流程不需要 Apple 开发者证书。

`ios-arm64-release.tar.gz` 只用来确认真机目标能编译通过。要在自己的 iPhone 或 iPad 上调试，用 Apple 账号登录 Xcode，选 Personal Team，Xcode 会生成短期开发签名。TestFlight 和 App Store 分发需要加入 Apple Developer Program。[Apple 开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)

## 公开预览和正式发布

1. 首次公开前，先完成[发布前补充清单](release-owner-checklist.md)里「首次公开前」的事项，再开启自动发布。
2. 更新 `app/pubspec.yaml` 的版本，例如 `0.2.0+2`，并在 [CHANGELOG.md](../CHANGELOG.md) 加 `## 0.2.0`。每次公开新构建都要递增构建号（`+` 后的数字），Android 靠它判断能否覆盖升级。
3. 改动合入 `main` 后推送发布标签：
   - 公开预览：设置仓库变量 `PUBLIC_PREVIEWS_ENABLED=true`，推送 `v0.2.0-preview.1`。
   - 正式发布：设置 `PUBLIC_RELEASES_ENABLED=true`，推送 `v0.2.0`。
   - 各平台打包和该提交在 `main` 上的推送 CI 同时进行，两者都成功才会公开。两种标签使用同一个应用基础版本和同一套发布签名。
4. **Release** 工作流出现审核请求时，核对标签和签名来源后批准。工作流先把附件上传到草稿，核对 GitHub 返回的完整附件清单和 SHA-256，再公开。预览标记为 **Pre-release**；正式版标记为 **Latest**，并附带应用更新清单。
5. 从 Releases 页面下载并验证：
   - Android：先装上一个已发布版本，再覆盖安装新版。
   - Windows：安装、卸载，以及便携版启动。
   - Linux：安装包和 AppImage。
   - macOS：把下载的 DMG 拖进「应用程序」并启动。

发布页按操作系统和架构列出直达下载链接。

- 公开预览：18 个客户端安装包和 2 个 iOS 编译归档，另附媒体对应源码和 `SHA256SUMS`。
- 正式版：启用 macOS 时有 18 个客户端安装包，并提供 `release-feed.json`（更新清单）。更新清单保留上一版本的记录；应用从更新入口打开对应的下载页面，由用户自己安装。

覆盖升级要求以下标识保持不变：Android 应用 ID、Apple Bundle ID、Linux 和 Windows 的系统应用标识、应用数据目录。改这些标识之前，先检查数据迁移、系统授权和覆盖安装。

## 替换 FFmpeg 后重新构建

安装包里的媒体模块静态链接了 FFmpeg。要修改 FFmpeg 并重新链接，下载同一个 Release 的项目源码和 `media-source.tar.gz`。媒体源码归档里有精确的上游源码、补丁、锁文件和构建脚本。

1. 解压项目源码，按[开发环境](../CONTRIBUTING.md#准备开发环境)安装 Flutter、Rust 和平台 SDK，在仓库根目录运行 `flutter pub get --enforce-lockfile`。另外解压媒体源码归档，把其中 `upstream/` 里的归档复制到仓库的 `.dart_tool/media_codec/source/`，文件名保持不变。
2. 解压其中的 FFmpeg 上游归档，打上 `packages/media_codec/third_party/ffmpeg.lock.json` 里列出的原有补丁。把你的改动保存成基于这棵源码树的 Git 补丁，放进 `packages/media_codec/third_party/patches/`，并按现有条目的格式把补丁的相对路径和 SHA-256 追加到锁文件。构建工具会按顺序打补丁，库版本或补丁变化时自动重新编译。
3. 在对应的系统和架构上构建：
   - Android：`dart scripts/android.dart build --mode debug --abi universal`。也可以先用 `dart scripts/android.dart init-signing` 生成自己的签名，再用 `--mode release` 构建。
   - 桌面：`dart scripts/build_host.dart <linux|windows|macos> --arch <x64|arm64>`。
   - iOS 模拟器：`dart scripts/build_host.dart ios --simulator`。
   - iPhoneOS：`dart scripts/build_host.dart ios` 编译，再在 Xcode 里用自己的签名安装。
4. 确认新包里是改过的媒体模块：启动应用，播放一段短视频或打开一次远控画面，确认能正常解码。各平台需要的 SDK 和额外工具见 [Packages 工作流](../.github/workflows/package.yml)。

## 怎么选下载包

Windows、Linux 和 macOS 的下载包都已内置 ADB。

- Android：近几年的真机通常选 `arm64-v8a`。不确定架构就选通用 APK。各个包可以按 Android 的签名和版本规则互相覆盖安装。
- Windows：选和系统架构一致的安装器或便携 ZIP。安装向导里可以选择创建桌面快捷方式。便携版要解压整个目录，再运行 `Interconnect.exe`。
- Linux：Debian、Ubuntu 系列用 DEB，Fedora 系列用 RPM。AppImage 加上执行权限后直接打开；系统没有 FUSE 时，在命令前加 `APPIMAGE_EXTRACT_AND_RUN=1`，或者解压 tar.gz 后运行 `bundle/interconnect`。
  - 构建基线是 Ubuntu 24.04。AppImage 和 tar.gz 依赖系统里的 GTK 3 和媒体相关库；ARM64 还依赖 libusb 1.0 和 zlib。
  - USB 连接需要系统允许当前用户访问手机；做不到时改用无线连接。
- macOS：在「关于本机」查看芯片。Apple 芯片选 `arm64`，Intel 处理器选 `x64`。

## 出错时怎么处理

- CI 或签名失败：在 Actions 里打开失败的步骤查看。修改签名配置前先核对签名指纹，用错密钥生成的 APK 无法覆盖用户已安装的版本。
- Android 的三个 ABI 包和通用包来自同一次构建，每个都单独校验包体和签名。依赖仓库返回限流或临时服务错误时，构建会等待后自动重试一次。
- 上传中断：重新运行这个标签失败的那次运行。工作流会复用草稿里校验和一致的附件，只上传缺失或不一致的文件，最后再核对完整附件清单。
- 排查耗时：在 Actions 里分别看运行器的开始时间和各步骤用时。构建脚本按编译、校验、归档、签名等阶段计时；仓库脚本的错误信息带阶段名，第三方工具的原始输出在对应阶段的日志里。
- 已公开的版本有问题时，发布一个新版本来修正。不要删除已发布的标签、签名和附件，用户需要靠它们追溯手上的安装包。

`SHA256SUMS` 用来确认下载的文件和上传到 GitHub 时一致：

- Linux：`sha256sum -c SHA256SUMS`
- macOS：`shasum -a 256 -c SHA256SUMS`
- Windows：PowerShell 运行 `Get-FileHash -Algorithm SHA256 文件名`，和清单里同名文件的值对比。
