# 通知测试APK

API 36独立应用发布合成通知，核对快照、更新、撤回、打开与清除，不进入产品分发。

```sh
dart tool/e2e/notification_fixture/build.dart
```

APK为 `/tmp/connect-notification-fixture/notification-fixture.apk`。包名 `dev.scrcpyconnect.notificationfixture`，入口 `.NotificationFixtureActivity`；每轮使用新的 `runId`，格式 `[A-Za-z0-9_-]{1,80}`。

| Action | 行为 |
| --- | --- |
| `CREATE_SNAPSHOT` | BigText、Inbox、MessagingStyle通知 |
| `UPDATE_SNAPSHOT` | 更新同键BigText标题/正文 |
| `CREATE_REQUIREMENTS` | 两个可清除及一个 `FLAG_NO_CLEAR` 通知 |
| `POST_REQUIREMENT` / `WITHDRAW_REQUIREMENT` | 发布/撤回ID5 |
| `OPEN` | 记录内容PendingIntent打开次数 |
| `CLEANUP` | 取消本run通知、写清理回执、移除task |

Tag/channel为 `notification-fixture-<runId>`；状态、打开、清理回执分别在 `files/runs/`、`files/opens/`、`files/cleanup/` 的 `<runId>.json`。

只操作分配的隔离AVD：先确认包未安装，拒绝覆盖；仅授予fixture的 `POST_NOTIFICATIONS`，不改产品权限/listener/AppOps。`am start`回执不足以验收，须读fixture状态并通过companion核对真实通知；打开须核对run、ID和次数。finally执行CLEANUP并确认本run资源消失，仅卸载本轮安装，清理失败写入报告。[设备证据](../../../docs/implementation/validation.md)。
