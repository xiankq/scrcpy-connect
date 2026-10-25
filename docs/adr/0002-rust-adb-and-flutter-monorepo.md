---
status: accepted
---

# Rust ADB 与 Flutter 主控同仓维护

Flutter 负责界面及业务编排，采用 Hooks／Riverpod；移动端 ADB 主机协议用独立 Rust 库，桌面固定打包官方 ADB，Dart 暴露统一接口。应用拥有独立 ADB server 的端口、身份目录及生命周期，不接管用户 5037 服务。

ADB 依赖优先 Rust，系统接口、TLS、USB 与压缩后端保留必要边界；不为纯 Rust 标签重写成熟库，也不把该方向扩大到媒体栈。协议、绑定与应用同仓演进，职责见 [0008](0008-reusable-packages-and-application-composition.md)。
