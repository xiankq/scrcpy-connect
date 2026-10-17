---
status: accepted
---

# 在 monorepo 中建设独立 Rust ADB 主机库与 Flutter 应用

用户选择 Rust 实现可独立复用的完整 ADB 主机库，经 flutter_rust_bridge 提供给 Flutter，Flutter 承担主要界面与呈现，使用 Flutter Hooks 和 Riverpod。在同一 monorepo 中演进这些部分，以便协议、绑定和应用协同变更，并为后续 iOS、Windows、macOS 主控适配保留路径。

完整性覆盖主机侧连接、认证、无线配对、设备发现、传输复用及设备服务；不把重写被控设备的 adbd 或逐项复制桌面命令行工具作为同义目标。当前功能实施与运行验证针对 Android；Q32 已将四端实际编译补为交付要求，具体遵循四端编译契约。未来端运行验证仍可后续开展，不能把“Rust/Flutter 可跨平台”当成 USB、后台运行和媒体链路已在所有平台验证。具体公开服务契约与生产密码方案仍须闭合；workspace、共享媒体等实施进展以[当前完成度](../../.scratch/interop/current-status.md)为准，不再将本决定写成所有技术细节均未选定。

Q22 中用户补充“希望尽量做到整个 ADB 依赖链纯 Rust”。依赖选型应据此核查实际源码与 feature 图，不能默认接受 ring、aws-lc、libusb 或压缩 C 库；但“尽量”尚不是无例外禁令，也不等于要求从零编写所有 Rust 实现。系统 API/JNI 调用的口径、TLS 提供者成熟度及例外策略仍在调研和访谈中。

Q32 中用户未确定更严格的纯度定义，明确要求确保 Android、iOS、Windows、macOS 全平台编译。将四端编译作为交付验收要求：ADB 核心、平台适配与应用依赖应保留可构建路径，平台不具备的运行能力不得拖垮整个包的编译。2026-10-17已有Android三ABI整包本地证据，其余三宿主整包未取得通过证据；不能把文档宣称支持视为编译通过，也不据此自动接受原生密码依赖。具体产物与验证边界见[当前完成度](../../.scratch/interop/current-status.md)。
