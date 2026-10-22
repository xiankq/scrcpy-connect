# 通知测试 APK

该 API36 测试 APK 在真实应用进程中发布合成通知，用于核对通知快照、更新、撤回、打开、清除和系统提醒。它不进入产品分发，不声明网络、ADB 或联系人能力，也不提供产品快捷回复。

```sh
dart tool/e2e/notification_fixture/build.dart
```

APK 输出到 `/tmp/connect-notification-fixture/notification-fixture.apk`；签名密钥和中间产物也留在 `/tmp`。脚本不安装 APK、不修改设备权限。

## 操作

包名为 `dev.scrcpyconnect.notificationfixture`，入口是 `.NotificationFixtureActivity`。每个命令要求 `[A-Za-z0-9_-]{1,80}` 范围内的 `runId`，每次测试使用新的随机值。

| Action | 行为 |
| --- | --- |
| `CREATE_SNAPSHOT` | 创建 BigText、Inbox 和 MessagingStyle 通知 |
| `UPDATE_SNAPSHOT` | 更新同一 BigText 通知的标题和正文 |
| `CREATE_REQUIREMENTS` | 创建两个可清除通知和一个 `FLAG_NO_CLEAR` 通知 |
| `POST_REQUIREMENT` | 新增 ID 5 通知 |
| `WITHDRAW_REQUIREMENT` | 由夹具应用撤回 ID 5 |
| `OPEN` | 记录原通知内容 PendingIntent 的打开次数 |
| `CLEANUP` | 取消本 run 通知、记录清理快照并移除 Activity task |

Tag 和 channel 均为 `notification-fixture-<runId>`。快照标题为用户可见的固定展开/收件箱/聊天内容；requirements 标题为 `<runId>-<id>`。操作状态保存在 `files/runs/<runId>.json`，打开回执在 `files/opens/<runId>.json`，清理回执在 `files/cleanup/<runId>.json`。

`am start` 返回成功只表示系统接受启动请求。测试驱动必须读取私有状态确认通知已发布，再通过产品 companion 的 `notifications.list` 核对同一来源、ID、更新与撤回。打开回执必须核对 run、通知 ID 和精确次数；不能由系统接受 PendingIntent 推导原应用已完成业务处理。

## 安全生命周期

测试驱动只操作本轮明确分配的隔离 AVD：

1. 先读取 `pm path dev.scrcpyconnect.notificationfixture`，已有安装时拒绝运行，不使用 `install -r`。
2. 安装本轮新构建 APK，再只授予该测试包的 `POST_NOTIFICATIONS`；不修改产品权限、listener grant 或 AppOps。
3. 使用唯一 `runId` 启动命令，等待私有状态，通过产品实际观察链路核对通知。
4. 在 `finally` 中执行 `CLEANUP`，独立确认本 run 通知和状态消失。
5. 只卸载本轮创建的测试包，并确认 `pm path` 为空；清理失败必须保留在报告中。

本地构建不证明设备安装、权限或系统通知行为。实际证据范围见[验收记录](../../../docs/implementation/validation.md)。
