# 参与邻接开发

## 报告问题

请写明：

1. 主控平台和邻接版本。
2. 被控手机的 Android 版本。
3. 连接方式（USB、配对码、扫码或 IP 连接）。
4. 操作步骤、预期结果和实际结果。

视觉问题可以附截图和对应的设计稿页面。提交前遮住设备地址、序列号、通知、联系人和私人文件，录屏和调试日志里也要检查。安全问题按[安全报告](SECURITY.md)私下提交。

## 准备开发环境

基础工具：Flutter 3.50.1、按 `rust-toolchain.toml` 安装的 Rust、Node.js 22、Python 3、Meson、Ninja、NASM。运行完整检查还需要 FRB 生成器和 cargo-expand：

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn  # 可选：pub 镜像
flutter pub get --enforce-lockfile
cargo install --locked cargo-expand --version 1.0.127
cargo install --locked flutter_rust_bridge_codegen --version 2.13.0
```

按要构建的平台再装：

| 构建目标 | 额外工具 |
| --- | --- |
| Android | JDK 21、Android SDK 36 和 37、Build Tools 37.0.0、NDK 28.2.13676358、CMake 3.22.1。先接受 SDK 组件许可再构建。 |
| Linux x64 / ARM64 | GCC、Clang、CMake、pkg-config，以及 GTK 3、libdrm、libepoxy、libclang、libva 的开发包。ARM64 还需要发行版自带的 ADB。 |
| Windows x64 / ARM64 | Visual Studio 的「使用 C++ 的桌面开发」工作负载和对应架构的工具、Windows SDK、LLVM 的 `clang` 和 `clang-cl`、MSYS2 的 Bash、`make` 和 `diffutils`。 |
| macOS / iOS | Xcode、CocoaPods 和对应平台的 SDK。 |

## 检查改动

- 只改 Flutter 界面时，在 `app/` 下运行 `flutter test --no-pub`。
- 提交前按改动范围运行对应测试，见[测试说明](test/README.md)。
- 完整检查要先编译当前电脑的 FFmpeg，例如在 Apple 芯片 Mac 上：

```sh
python3 packages/media_codec/tool/build_ffmpeg.py --platform macos --arch arm64
./scripts/check.sh
```

改页面行为或视觉时，同步更新[产品规格](designs/prod/README.md)或[视觉规范](designs/design.md)。代码放在哪里见[仓库规则](AGENTS.md)。

## 提交 PR

- 说明：谁受影响、操作上有什么变化、跑过哪些测试。
- 改界面时附改动前后的截图。
- 改平台集成时写明在哪些平台上验证过；涉及真机的写明平台和连接方式。
- 新功能、依赖升级和清理分成不同的 PR，方便单独审查。
