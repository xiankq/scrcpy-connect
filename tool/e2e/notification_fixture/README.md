# 通知夹具

API 36 独立 APK 发布合成通知，供 companion 核对快照、更新、撤回与原动作。

```sh
dart tool/e2e/notification_fixture/build.dart
```

产物为 `/tmp/connect-notification-fixture/notification-fixture.apk`。仅用专用授权 AVD，拒绝覆盖 `dev.scrcpyconnect.notificationfixture`；每轮使用唯一 runId。动作及回执字段见 `NotificationFixtureActivity` 源码。

只授予夹具 POST_NOTIFICATIONS，不改产品 listener/AppOps。结束执行本 run 的 CLEANUP 并核对资源消失，仅卸载本轮安装。
