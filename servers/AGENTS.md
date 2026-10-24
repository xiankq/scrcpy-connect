# 被控临时执行产物

本目录保存被控设备临时运行的代码与固定产物；主控宿主及被控系统的边界见[架构](../docs/implementation/architecture.md)和[兼容条件](../docs/implementation/android-target-compatibility.md)。

## 来源与生成链

| 修改对象 | 先读 |
| --- | --- |
| scrcpy 来源、标准脱糖、协议版本或 DEX | [vendor 构建与来源](vendor/README.md) |
| Binder、剪贴板、通知、通话或媒体 worker | [companion 契约与构建](companion/README.md) |
| 原生元数据、目录枚举或原子发布 | [文件服务契约](helpers/README.md) |

源码、固定构建输入、产物、manifest 与应用共享 assets 的摘要构成同一条链。修改来源后使用对应构建器同步产物并检查一致性；仅替换二进制、更新摘要或降低编译目标不能作为兼容修复。协议消息和启动选项变化同时核对能力接口与执行端。应用校验资源后向能力包传入明确字节，Rust 不嵌入一套重复 JAR／助手或读取应用资源目录，具体打包见[工具链契约](../docs/implementation/repository-tooling.md#被控执行产物的共享打包)。

scrcpy 保持一份固定版本的服务端，通过功能条件与标准脱糖支持旧设备。修改 Android／Java 调用时，除编译下限外还需核对实际方法签名、静态字段、接口默认方法及类加载时机；真实权限拒绝与接口缺失分别处理。

## 部署与回收

应用决定部署所服务的业务与明确执行参数；通用能力仅持有本次实际进程、流和独占目录租约。修改启动或 worker 流程时，核对进程监督器，并覆盖就绪前取消、输入 EOF、超时及子进程退出，清理限于本次拥有的身份；文件服务仍需核对回读产物与执行 inode，详细边界以兼容文档为准。

受控 JAR／助手、许可证及对应源码归档属于构建输入，不按临时目录清理。构建缓存、测试 APK、模拟器和设备夹具按[工具链的产物边界](../docs/implementation/repository-tooling.md#构建与产物边界)处理。宿主夹具、产物重建和真实设备运行分别记录结论。
