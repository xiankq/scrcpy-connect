# device_runtime

应用能力的组装入口。`DeviceRuntime.initialize(dataDirectory:)` 连接 ADB、连接编排、偏好、文件、投屏和诊断包；`request`/`events` 传递控制结果与状态，媒体字节留在原生链路。

本包提供 FRB 执行适配和跨能力生命周期组合；业务规则归各能力包，USB、前台服务、SAF/分享 URI 保留薄平台适配。依赖与资源归属见[架构](../../docs/implementation/architecture.md)，绑定生成及 native assets 构建见[工具链](../../docs/implementation/repository-tooling.md)。

平台与设备运行结果见[验收记录](../../docs/implementation/validation.md)。
