---
status: accepted
---

# 明确原生组合与宿主检查环境

ADB 的 Dart 类型依赖不应隐式选择原生运行时。`AdbHost` 必须接收 bindings；独立用户显式取得独立 ADB 实现，scrcpy 组合宿主使用同库实现。独立 ADB 桥继续作为能力包维护，但发布链接根据初始化入口的真实可达性决定是否分发；缺少可达性信息时保守保留。相比另设产品桥或跨动态库传递 Rust 对象，这保持了能力包的独立性和精确资源身份，同时避免主控应用重复携带 ADB、TLS、认证和文件实现。代价是维护 build/link hooks，并分别验证独立使用及组合使用。

纯宿主工具测试使用独立 `tool/host/` Dart 环境与锁文件，不加入 Flutter workspace。现有 Flutter 固定的测试依赖与工具 analyzer 约束无法在同一解析中使用纯 Dart runner；继续使用 `flutter test` 又会编译无关原生 hooks。独立环境允许工具测试只承担 ZIP、生成、进程和主机协议夹具验证，不通过依赖 override 改写 Flutter 的测试契约。实际应用、原生能力和设备测试仍由各自入口负责。

本决定补充 [0008](0008-reusable-packages-and-application-composition.md) 的原生组装及开发工具责任，具体构建规则见[工具链契约](../implementation/repository-tooling.md)。
