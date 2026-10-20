# interop_bridge

应用调用 Rust 活动核心的边界。`InteropBridge.initialize(dataDirectory:)` 使用 app 私有目录保存本机 ADB 身份及元数据，`request` 与 `events` 传递操作结果/持续状态；视频和音频内容不穿过 Dart JSON。

绑定由锁定的 flutter_rust_bridge 生成；从仓库根运行 `dart tool/generate.dart`，配置位于根 `flutter_rust_bridge.yaml`。`hook/build.dart` 使用原生 assets 构建 `crates/interop_bridge`，Android linker 遵循 runner 最低 API。

实时视频经 Rust Matroska/鉴权 HTTP 交给 fvp Player，Flutter 展示 Texture；读取实际 snapshot 像素后才报告 ready。暂停串行化消费者和本地显示，不停止官方 scrcpy JAR 的目标采集与编码；恢复通过 RESET_VIDEO 刷新编码，并重新核对播放器与像素。声音共用 fvp 播放链路，焦点由薄 OS 适配提供；Player/channel 由进程 Flutter engine 持有，不跨进程死亡存活。

USB 授权、前台服务、SAF/分享 URI 与系统能力保留薄平台适配；导入、文件复制和任务规则归 Dart/Rust。网络连接、目标任务与传输的所有权不依赖 Flutter 页面。详细边界见[架构](../../docs/implementation/architecture.md)。

平台与设备验收结果见 [验证文档](../../docs/implementation/validation.md)。实验密码提供器、权限/OEM及未完成矩阵不能由编译通过推断为生产可用。
