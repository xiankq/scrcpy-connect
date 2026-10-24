---
status: accepted
---

# 独立 Rust ADB 主机库与 Flutter 主控应用

移动端 ADB 主机协议由独立 Rust 库提供；桌面使用随应用固定打包的官方 ADB。`adb` 在 Dart 层提供统一接口。Flutter 承担主控界面与性能不敏感的业务编排，使用 Hooks 和 Riverpod；协议、绑定与应用在同一仓库协同演进。通用包与业务归属见 [0008](0008-reusable-packages-and-application-composition.md)，媒体路径见 [0007](0007-capability-packages-and-native-media.md)。

“完整 ADB 主机”指连接、认证、无线配对、设备发现、传输复用及被控服务访问；不等同于重写被控设备的 adbd。桌面官方 ADB 属于产品依赖，应用拥有独立 server 的端口、身份目录与生命周期，不接管用户已有的 5037 服务。

ADB 依赖链以尽量采用 Rust 实现为选型方向。系统 API/JNI、TLS 提供者、USB 和压缩后端分别说明其边界；此约束不扩展为对整个媒体栈的纯 Rust 要求，也不构成从零实现已有库的理由。具体依赖与生产成熟度依据[依赖研究](../research/pure-rust-adb-dependencies.md)核查。

Android、Windows、Linux 按此顺序进行实际宿主验证。iOS/macOS 实现适配，未获得相应环境前不声明整包或运行验收。跨 target 检查、宿主链接、Flutter 整包和实际运行是不同证据；已执行结果见[验收记录](../implementation/validation.md)，目录与资源所有权由[架构](../implementation/architecture.md)维护。
