# device_runtime

应用能力的组装入口。`DeviceRuntime.initialize(dataDirectory:)` 连接独立的 ADB、连接编排、偏好、文件、投屏和诊断包。`request` 与 `events` 传递控制结果与状态；视频和音频内容不穿过 Dart JSON。本包保留原生执行适配和生命周期组合，不拥有其他能力的业务规则。

绑定由锁定的 flutter_rust_bridge 生成；从仓库根运行 `dart tool/generate.dart`，配置位于根 `flutter_rust_bridge.yaml`。`hook/build.dart` 使用原生 assets 构建 `crates/interop_bridge`，Android linker 遵循 runner 最低 API。

实时视频由 Rust scrcpy 压缩包直接进入 `media_codec` 的 Rust/FFmpeg 解码核心，Flutter 展示平台纹理；读取实际像素后才报告 ready。暂停停止本地呈现，官方 scrcpy 的目标采集仍运行；恢复通过 RESET_VIDEO 请求新画面。PCM 音频直达平台输出，只有原生实际接收字节后才报告 ready。`flutter_adb` 对移动端 Rust 传输与桌面官方 adb 提供统一调用。

Dart 协调器组织配对、USB 记录选择、转 IP 重试、自动重连、连接后屏幕策略与能力说明；产品默认设置及画质预设在此解析，再向 Rust 提交具体执行参数。Rust 持有连接、授权身份、活动与原生操作租约，提供探测事实并核验迟到结果。

USB 授权、前台服务、SAF/分享 URI 与系统能力保留薄平台适配；导入、文件复制和任务规则归 Dart/Rust。网络连接、目标任务与传输的所有权不依赖 Flutter 页面。详细边界见[架构](../../docs/implementation/architecture.md)。

平台与设备验收结果见[本轮原生媒体验收](../../docs/implementation/native-media-validation.md)和[验证文档](../../docs/implementation/validation.md)。实验密码提供器、权限/OEM及未完成矩阵不能由编译通过推断为生产可用。
