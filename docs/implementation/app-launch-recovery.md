# 应用打开记录与恢复

独立应用窗口和手机主屏上的 `session.launch` 都在发送 START_APP 前，将设备、包名、操作 UUID 和关联会话 UUID 写入应用持有的本机私有记录。账本、未决门禁与用户意图归应用 Dart，通用 scrcpy 只执行明确控制请求。ADB 写入回执不代表 Android 应用完成启动；编码／渲染失败也不证明应用没有打开。生产切换状态见[本轮重构记录](architecture-refactor-validation.md)。

主屏打开采用独立操作 UUID，不占用主屏会话的身份。返回未知结果时，`sessionId`／`launchOperationId` 指向这次操作，`linkedSessionId` 仅说明原主屏归属。检查和关闭必须使用操作 UUID，不能把原主屏当成待关闭记录。

## 生命周期

- 提交前持久化 pending；同设备、同包名存在 pending／unknown 时拒绝第二次打开，包括独立窗口与主屏之间的绕行。
- 主屏收到写入回执后关闭操作记录，回执仅表示请求已发送；独立窗口确认编码输出后标为 observed，后续渲染失败仍可降为 unknown。
- 断开连接释放捕获资源，保留未决记录。应用业务所有者重建把 pending／observed 转为 unknown，只恢复可核对的记录，不恢复纹理、媒体令牌、进程或自动启动意图。
- 明确关闭只结束本次记录和所属控制资源，不强停真实应用。按设备关闭唯一会话时也关闭解析出的准确记录。再次打开必须来自用户的新选择。
- 记录最多 1024 项／2 MiB，仅回收已关闭项；未决项不被容量回收。损坏或超限记录拒绝初始化，不能静默丢弃后重新提交副作用。

[AppLaunchStore](../../app/lib/media/capture/app_launch_store.dart) 保持原 v1 记录格式；同 isolate 的后继接管串行等待既有提交，并撤销旧许可。写入提交结果未知时封存当前实例，后续操作必须重开读取实际文件；不能用仍停留在旧版本的内存覆盖未知提交。无效格式保留原字节，容量只回收已关闭记录。跨 isolate 接管仍须由应用宿主先排空旧业务所有者，不能与旧 Rust 账本同时写入。

落盘失败不解除当前应用所有者的 unknown 门禁。渲染失败时先确保捕获取消和内存记录成立，再报告持久化问题；先前已经写入的 pending／observed 在重建后仍按 unknown 处理。

## 排队与取消

START_APP 使用独立提交许可。控制队列取出时，只有尚未取消的许可才能进入实际写入；超时、调用者取消或明确关闭会撤销排队许可。前一条 ADB WRTE 的回执恢复后，也不能发送已经撤销的启动。

若写入已经开始，取消不能撤销 Android 可能已经执行的动作；此时终止所属控制流，避免继续使用可能截断的协议流，并保留待核对结果。不能据此承诺任何取消都会保留原主屏控制会话。

## 历史证据与回归边界

旧原生业务实现的真实 Android 测试原位于 `rust/app/core/tests/app_launch_android.rs`，现已随旧 Runtime 移除。2026-10-18 在隔离 API36 目标显式执行通过。故障代理只阻塞或丢弃真实 adbd 的指定 ACK，独立 ADB 客户端检查真实应用任务。这是迁移前的副作用证据，不能代替当前 Dart 接线验收。当前主机回归见 [app_launch_store_test.dart](../../app/test/media/capture/app_launch_store_test.dart) 和 [app_launch_test.dart](../../app/test/app_launch_test.dart)。

迁移后需保留主屏同 UUID 打开、缺包导致首帧失败、断开／业务所有者重建后阻止重放、已编码后渲染清理、记录写盘失败、按设备关闭、主屏回执丢失、排队超时后关闭及迟到 ACK 恢复等断言。`session.launch` 受应用的恢复核验屏障约束。

页面/生命周期/会话视图回归另外核对：主屏未知结果必须匹配本次设备、包名、原主屏 UUID 和独立操作 UUID；断开事件先到不能丢弃迟到的准确操作记录。原主屏的 UP／CANCEL 清理按旧 UUID／绑定代次排队，核对和关闭操作记录不等待输入或 pause 回执。关闭后也不会自动打开应用，只有用户明确选择重新打开才提交新意图。

旧实现当时使用的命令如下，仅用于追溯历史，当前工作区不再提供该入口：

```sh
env CARGO_BUILD_JOBS=2 INTEROP_ADBD_PORT=15556 \
  cargo test -p interop-core --test app_launch_android -- --ignored --test-threads=1
```

该证据不等于 Android 杀进程现场、实际解码器故障、旧系统副屏回退或所有 OEM 的恢复验收；完整应用／IME／多窗口恢复仍需分别验收。
