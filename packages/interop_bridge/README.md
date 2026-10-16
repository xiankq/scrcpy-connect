# interop_bridge

应用调用 Rust 活动核心的边界。`InteropBridge.initialize(dataDirectory:)` 使用 app 私有目录保存本机 ADB 身份及元数据，`request` 与 `events` 传递操作结果/持续状态；视频和音频内容不穿过 Dart JSON。

绑定由固定 flutter_rust_bridge 2.13.0 生成。在仓库根执行 `flutter_rust_bridge_codegen generate` 后执行 `cargo fmt --all`，配置位于根 flutter_rust_bridge.yaml。`hook/build.dart` 使用原生 assets 构建 crates/interop_bridge；Android linker遵循runner最低API，覆盖当前上游固定35的行为。

实时视频由共享Rust Matroska/鉴权HTTP和公开fvp Player承担，Flutter展示Texture；只有实际snapshot像素通过后才向Rust报告ready。按会话串行化暂停：先确认消费者暂停，再停止捕获；恢复先继续捕获和刷新编码，再确认播放器与像素。Android五codec、真实HOME/返回及旋转generation交接已通过；旧Native视频解码实现已删除，实际产品页面五codec复验通过。共享fvp音频已接入生产，真实PCM/暂停恢复/产品HOME、Activity重建与双设备外部焦点已通过；自写AudioTrack循环已删除。焦点由薄OS适配提供，持续Player/channel由进程Flutter engine持有，不能推定进程死亡可存活。USB授权、前台服务、SAF/分享URI与系统能力保留薄平台适配，导入/文件复制和任务规则在Dart/Rust。网络连接/目标任务/传输不依赖Flutter页面存在。

平台与设备验收结果见 [验证文档](../../docs/implementation/validation.md)。实验密码提供器、权限/OEM及未完成矩阵不能由编译通过推断为生产可用。
