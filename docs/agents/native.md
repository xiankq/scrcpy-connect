# 原生能力

- ADB协议与服务见[Rust接口](../../rust/adb/README.md)，被控版本见[兼容条件](../implementation/android-target-compatibility.md)。
- 应用Dart持有设备、准入和产品策略；Rust持有协议流、捕获、FD及执行事实。资源交接见[架构](../implementation/architecture.md)。
- 旧shell退出码、文件errno与未知结果保留原语义；取消后等待真实任务退出，关闭失败保留精确句柄重试。
- FRB、依赖与产物见[工具链](../implementation/repository-tooling.md)，被控执行端见[servers](../../servers/AGENTS.md)。
