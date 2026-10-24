# Android 分享来源与进程归属

2026-10-17核查URI授权、FD交接和任务复用。现行任务与来源所有权见[架构](../implementation/architecture.md)，交付结果与恢复见[内容交付](../implementation/content-delivery.md)；本页保留系统契约与真实反例。

## URI 信任

接收者自己的读权限不足以证明外部调用者有权分享该URI。只接受可解析provider的content URI，要求读grant，并拒绝属于本应用包名或UID的provider，包括authority别名，以免外部intent借用接收者权限读取私有内容。

API35+的 `ComponentCaller.checkContentUriPermission` 提供启动时调用者权限证据，只覆盖intent data、EXTRA_STREAM、ClipData；它不是当前权限查询，接收者仍须有实际访问权限。较旧API没有等价caller归因。[ComponentCaller](https://developer.android.com/reference/android/app/ComponentCaller#checkContentUriPermission(android.net.Uri,%20int))

出站FileProvider仅暴露必要目录。源码XML中的窄路径仍需核对最终合并资源；不能开放整个files/cache或用入站显示名构造私有文件路径。[FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)、[目录暴露风险](https://developer.android.com/privacy-and-security/risks/file-providers)

## 打开、准入与复制

`openAssetFileDescriptor` 交付FD、startOffset及declaredLength，provider的SIZE字段不是可信复制边界。Android适配只查询DISPLAY_NAME；应用需要先打开provider取得声明区间，再执行Dart预算准入，因此不能声称超大内容在provider open之前已被拒绝。[ContentResolver](https://developer.android.com/reference/android/content/ContentResolver#openAssetFileDescriptor(android.net.Uri,%20java.lang.String,%20android.os.CancellationSignal))

regular file需按声明区间读取，非seekable源不支持非零offset。复制时继续核验实际字节限额；声明长度检查不能覆盖实际超限路径。取消signal也不能强制终止不配合的provider或已经阻塞的OS read，必须限制worker、队列与保留FD。原FD与native重复FD分别释放。

来源lease与Dart任务日志分别拥有生命周期。已交给任务或发布结果未知的来源不能因取消分享UI就回收；完整、已持久化的任务证据才允许reconcile。具体限额与日志格式以[内容交付](../implementation/content-delivery.md#外部分享接收与传输来源)、[文件所有者](../implementation/file-ownership.md)为准，研究不复制第二份常量表。

## 已发现的系统与夹具反例

| 反例 | 保留结论 | 一手依据 |
| --- | --- | --- |
| singleTop允许外部分享另建MainActivity，原Activity从共享engine分离后恢复生命周期不会自动重附着 | 进程engine存活不等于所有Activity view可用；当前singleTask的复用与SAF取消边界分别核验 | [任务与返回栈](https://developer.android.com/guide/components/activities/tasks-and-back-stack) |
| ACTION_SEND的EXTRA_STREAM会自动迁移到ClipData并添加grant flag | 负例夹具只省略flag可能仍收到真实grant；先设置ClipData才能保持预期的无grant输入 | [Android16 Intent](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android16-release/core/java/android/content/Intent.java) |
| provider只宣告513MiB却在openFile抛错 | 只证明打开失败；须交付真实FD与超限declaredLength才能验证声明长度准入 | [FixtureProvider](../../tool/e2e/share_fixture/src/dev/scrcpyconnect/sharefixture/FixtureProvider.java) |
| am start返回0或delivered-to-top | 只说明intent分发，不证明Flutter resumed、模式更新或内容已取回 | [Activity manifest](https://developer.android.com/guide/topics/manifest/activity-element) |

历史九模式样本通过text/image/multi/alias、拒绝与slow显式取消，但不覆盖120秒deadline、恶意provider饱和、所有任务/多显示布局或系统picker与新分享并发。

当前入口：[Dart来源存储测试](../../app/test/files/share_store_test.dart)、[分享协调测试](../../app/test/files/share_coordinator_test.dart)、[真实文件能力测试](../../app/test/files/share_coordinator_native_test.dart)、[真实页面流程](../../app/integration_test/incoming_share_test.dart)及[driver](../../tool/driver/incoming_share.dart)。测试声明负责环境与清理，不在研究中保留临时PID、日志路径和重复命令。
