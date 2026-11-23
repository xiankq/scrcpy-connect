# 参与邻接开发

## 报告问题

说明主控平台、邻接版本、被控 Android 版本、使用的连接方式、操作步骤及预期结果。视觉问题可以附截图和对应设计页面。请先遮住设备地址、序列号、通知、联系人和私人文件；也请检查录屏和调试日志里是否包含这些内容。安全问题按[安全报告](SECURITY.md)提交。

## 本机开发

准备 Flutter 3.50.1、按 `rust-toolchain.toml` 安装的 Rust、Node.js 22、Python 3、Meson、Ninja 与 NASM。完整检查还需要 FRB 生成器和 cargo-expand。

```sh
export PUB_HOSTED_URL=https://pub.flutter-io.cn
flutter pub get --enforce-lockfile
cargo install --locked cargo-expand --version 1.0.127
cargo install --locked flutter_rust_bridge_codegen --version 2.13.0
```

按需要添加宿主工具。

| 构建目标 | 额外工具 |
| --- | --- |
| Android | JDK 21、Android SDK 36 和 37、Build Tools 37.0.0、NDK 28.2.13676358、CMake 3.22.1。接受 SDK 组件许可后再构建。 |
| Linux x64 | Clang、CMake、pkg-config，以及 GTK 3、libdrm、libepoxy、libclang、libva 的开发包。 |
| Windows x64 | Visual Studio 的「使用 C++ 的桌面开发」工作负载、Windows SDK、Git Bash 和 MSYS2 版 GNU Make。 |
| macOS / iOS | Xcode、CocoaPods 和对应平台的 SDK。 |

改 Flutter 界面可以在 `app/` 下运行 `flutter test --no-pub`。提交前按改动范围运行[相应测试](test/README.md)。完整检查需要先准备当前宿主的 FFmpeg，例如 Apple Silicon 上运行：

```sh
python3 packages/media_codec/tool/build_ffmpeg.py --platform macos --arch arm64
./scripts/check.sh
```

改动页面行为或视觉时，请同步更新对应[产品规格](designs/prod/README.md)或[设计稿](designs/design.md)。涉及真机的结果请附上实际验证的平台和连接方式。按[仓库约束](AGENTS.md)放置代码，保证应用通过能力包的公开接口调用原生实现。

## 提交改动

PR 简要说明谁受影响、操作有什么变化、跑过哪些测试。调整界面时附前后截图，修改平台集成时注明验证过的平台。把新功能、依赖升级和清理拆成可独立审查的改动。
