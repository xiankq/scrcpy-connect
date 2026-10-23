# 原文件取回、系统保存与分享

产品入口与失败恢复见[文件与内容规格](../../designs/prod/content-and-transfer.md)。本页维护交付账本、系统提供方和原子发布约束。来源固定于传输任务；ReceiveContentRoute从权威记录核对任务、设备、方向和私有路径，全局焦点不改变来源。

## 完成点与持久账本

| 阶段 | 确认依据 |
| --- | --- |
| 取回暂存 | 原件完整、源未变化、原子发布后任务canExport |
| 系统保存 | 复制/同步、提供方检查与关闭、目标元数据核验；不承诺云端已同步 |
| 系统分享 | 交给所选应用；关闭/未知单独呈现，不承诺接收方已发送或保存 |

Rust按 `(sourceId, localPath, kind)` 记录；选择器和写入前先可靠保存pending，完整回执落盘后才成功。重启将pending转unknown，不重放；不持久化URI/FD/授权。上限1024份原件、16384次操作、4MiB，满额拒绝，不淘汰旧结果。

重进只读核验；已保存的额外副本需明确确认，unknown先核对当前操作。迟到回执不能覆盖别的操作或既有终态；离页只取消自己仍在执行的操作，查阅pending的页面不取得取消权。拒绝admission后重读真实记录。完整回执过大只尝试最小unknown，不重写provider；仍持久化失败则保留pending。取消选择器保留来源，取消写入可能留下部分系统目标。

## 共享与系统适配边界

Dart DocumentsCoordinator负责树规划、容量、冲突和生命周期；Rust复制借用FD副本、核验与同步；Android只管选择器、URI/授权及原始PFD。成功完成lease必须 `checkError→close→checkError`，任一步失败仍释放并保留首错；失败/取消使用closeWithError，无实际lease不得确认成功。依据见[提供方研究](../research/provider-output-streams.md)。

仅接受rw、可核验空普通文件、可定位和同步的provider。URI不代表排他新建，不能回退到可能截断旧内容的w。管道、非空目标、权限失效或异常明确失败并保留来源。

冲突绑定operationId/conflictId，支持保留两份、跳过、取消与本次后续策略；过期决定拒绝，等待受操作期限/取消约束。不具安全替换能力时禁替换；全跳过显示本次未保存内容。私有来源保护归[媒体缓存](media-cache.md)。

## Android 私有文件的发布

Linux/Android使用 `renameat2(RENAME_NOREPLACE)` 原子发布：目标存在则保全旧目标和part，成功后核对身份并同步目录；无法确认则result_unknown，不重试提交、不删除结果。使用libc架构SYS_renameat2，不依赖API30动态符号。SELinux下硬链接可能EACCES；不支持的内核/文件系统安全拒绝，不回退覆盖rename或复制删除，也不提供同权限恶意写者的事务隔离。来源：[Bionic声明](https://android.googlesource.com/platform/bionic/+/06356e41c5ed7b12220b24c05ba4fdb873b126a7/libc/include/stdio.h#260)、[旧系统syscall策略](https://android.googlesource.com/platform/bionic/+/f711b078b9656f7dbb52a046a7f992a450e8fa13/libc/seccomp/arm64_policy.cpp#36)、[rename契约](https://man7.org/linux/man-pages/man2/rename.2.html)。

## 已执行证据与复现

| 入口 | 证据 |
| --- | --- |
| CopyManager及Bridge/JVM回归 | 独立Linux子进程禁linkat后成功发布、目标冲突保全；完成/中止、迟到/丢失lease、关闭错误及顺序 |
| `app/integration_test/content_delivery_test.dart` / `tool/driver/content_delivery.dart` | 2026-10-17双API36 AVD，系统取消→保存→离页重进saved→Sharesheet独立接收器；host核字节/hash/grant。文本、JPEG、MP4单项系统交付样本均不足2MiB |
| `document_conflict_flow_test.dart` / `document_conflict.dart` | 同日本地树提供方真实同名目录/文件、旧字节/inode保全、新副本、跳过/取消/离页无写入和过期决定；未制造第二个自然冲突验证后续策略 |
| `incoming_share_target_test.dart` / `incoming_share_target.dart` | 2026-10-18三AVD，用户固定目标A与目录，焦点改B仍只写A，host核hash、B无文件及consume不重提 |

从app运行对应driver/target；隔离参数见[E2E说明](../../tool/e2e/README.md)及driver声明，接收器仅装主控。媒体样本由host FFmpeg生成，不是产品依赖；当前不内置本地视频播放器。上述样本先于文件任务所有权迁移，现行所有者证据见[device_files验收](../../packages/device_files/VALIDATION.md)。云/管道provider、写入中进程终止后的unknown、批量大原件、权限撤销及提交断线仍待验证。
