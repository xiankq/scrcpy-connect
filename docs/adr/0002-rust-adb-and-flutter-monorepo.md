---
status: accepted
---

# 独立 Rust ADB 主机库与 Flutter 主控应用

ADB 主机能力由可独立复用的 Rust 库提供，经 flutter_rust_bridge 接入 Flutter。Flutter 承担主控界面与本机呈现，使用 Hooks 和 Riverpod；协议、绑定、领域实现与应用在同一仓库协同演进。

“完整 ADB 主机”指连接、认证、无线配对、设备发现、传输复用及被控服务访问；不等同于重写被控设备的 adbd 或逐项复制桌面 adb 命令行。应用不调用或分发外部 adb 可执行文件，独立设备实验使用的官方 adb 不属于产品依赖。

ADB 依赖链以尽量采用 Rust 实现为选型方向。系统 API/JNI、TLS 提供者、USB 和压缩后端分别说明其边界；此约束不扩展为对整个媒体栈的纯 Rust 要求，也不构成从零实现已有库的理由。具体依赖与生产成熟度依据[依赖研究](../research/pure-rust-adb-dependencies.md)核查。

Android、iOS、macOS、Windows 的实际整包编译属于交付要求。平台能力缺失不能破坏其他平台的编译；跨 target 检查、宿主链接、Flutter 整包和实际运行是不同证据。构建契约见[四端编译约束](../research/cross-platform-build-contract.md)，已执行结果见[验收记录](../implementation/validation.md)。目录与资源所有权由[架构](../implementation/architecture.md)维护。
