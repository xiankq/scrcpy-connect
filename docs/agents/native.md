# Rust 核心边界

## 按修改范围读取

| 范围 | 责任来源 |
| --- | --- |
| ADB transport、认证、shell、sync、流复用 | [ADB 库契约](../../rust/adb/README.md)；核对旧协议行为时再读[固定源码研究](../research/adb-android-compatibility.md) |
| 系统版本、权限、宽元数据或远端进程 | [被控兼容边界](../implementation/android-target-compatibility.md) |
| 设备连接、活动准入、释放或恢复 | [架构所有权](../implementation/architecture.md)、[状态恢复](../implementation/state-recovery.md) |
| FRB、命令契约、原生助手或受控依赖 | [工具链契约](../implementation/repository-tooling.md)、[服务端产物约束](../../servers/AGENTS.md) |

## 能力与结果

`interop-adb` 提供独立的协议与服务能力。Rust 管理协议流、原生捕获和精确文件描述符，公开类型化执行事实；设备记录、连接准入、活动归属、产品可用条件、默认设置、配对与重连策略由应用 Dart 持有。主控安装条件、被控 SDK、协商的协议版本／payload／feature 和实际权限分别处理，不能用其中一个代替其他条件。

旧 shell 的退出码、文件元数据精度和操作结果保留真实语义。修改文件读取、传输或预览时，沿同一元数据边界核对前后源身份、目标冲突和提交结果；未知、无权、消失与空内容分别返回，处理规则见兼容文档。

## 所有权与验证

同一 Client 上的流与设备连接分开拥有生命周期；活动、页面租约和播放器也不互相代替。停止、取消、迟到回执和重连按所属身份及代际处理；临时进程沿共享监督器与文件服务租约回收，不能只删除 JAR 或路径作为退出证明。

协议夹具应表现对端真实协商及错误行为；默认测试通过只证明其覆盖的协议／主机边界。设备用例按各自声明显式运行并记录 SDK、ABI、连接方式及清理结果，不能将跳过或编译成功外推为旧手机、OEM 或其他主控宿主已验证。运行入口见 [ADB 能力测试](../../packages/adb/test/README.md)，迁移状态与局限见[本轮记录](../implementation/architecture-refactor-validation.md)。
