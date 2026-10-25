# Android Binder companion

`src/com/interop/companion/Main.java` 编译为临时 DEX JAR，以 shell UID 2000 运行。应用编排见 `app/lib/stores/companion_coordinator.dart`。

| 能力 | 当前边界 |
| --- | --- |
| 通知 | 动态 listener、快照和原 contentIntent；不提供快捷回复，清除不等于已读 |
| 通话 | 聚合观察；无法定位具体通话，所有 `calls.action` 返回 `call_targeting_unavailable`，音频 unknown |
| 剪贴板 | 只读首项文本；写入读回确认，未知不重试，不修改权限/AppOps |
| 应用 | API 29+ 当前用户标准任务与真实图标，不伪造安装列表 |
| 缩略图 | 独立有界解码子进程，只传 JPEG；视频 API 27+，取消未确认返回 `media_cleanup_unknown` |

协议为认证 socket 上的 v1 JSON line，以 requestId 关联响应。token 与通知动作只存内存；消息上限、签名兼容及字段以源码为准。`observation.set(enabled, epoch)` 显式启停 listener，启动 helper 不自动观察。socket 关闭后注销并退出，调用方须等待进程收尾再删 JAR。

```sh
dart --disable-dart-dev servers/companion/build.dart
dart --disable-dart-dev servers/companion/build.dart --check
dart --disable-dart-dev servers/companion/build.dart --rebuild
dart --disable-dart-dev servers/companion/tests/compatibility.dart
dart --disable-dart-dev servers/package.dart
```

根目录先 `flutter pub get`；重建使用 JDK 21、SDK 36、build-tools 37.0.0。`--check` 离线核对，`--rebuild` 比较而不替换，无参数更新 JAR/manifest。

真实通知回归先构建[通知夹具](../../tool/e2e/notification_fixture/README.md)，再运行：

```sh
dart --disable-dart-dev servers/companion/tests/notification-snapshot.dart \
  --adb <absolute-adb-path> --serial <isolated-avd>
```

仅用专用授权目标，拒绝覆盖已有夹具；结束清理本 run 通知与安装，不改产品权限。主机 `app/test/companion` 与字节码兼容检查不证明 OEM Binder 可用。
