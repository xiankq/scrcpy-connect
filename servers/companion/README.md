# Android Binder companion

`src/com/interop/companion/Main.java` 编译为临时 DEX JAR，以 shell UID 2000 运行。应用编排见 [CompanionService](../../app/lib/core/companion/companion_service.dart)。

| 能力 | 当前边界 |
| --- | --- |
| 通知 | 动态 listener、快照及原 contentIntent。清除更新通知列表，阅读状态由原应用维护。 |
| 通话 | 聚合观察及打开当前系统通话界面；`calls.openPhoneApp` 按当前用户打开无号码的系统电话应用，不依赖观察。无法定位具体通话，所有 `calls.action` 返回 `call_targeting_unavailable`，音频 unknown |
| 应用 | API 29+ 当前用户标准任务与真实图标，不伪造安装列表 |
| 缩略图 | 独立有界解码子进程，只传 JPEG；视频 API 27+，取消未确认返回 `media_cleanup_unknown` |

协议为认证 socket 上的 v1 JSON line，以 requestId 关联响应。token 与通知动作只存内存；消息上限、签名兼容及字段以源码为准。`observation.set(enabled, epoch)` 显式启停 listener，启动 helper 不自动观察。socket 关闭后注销并退出，调用方须等待进程收尾再删 JAR。

```sh
dart --disable-dart-dev servers/build.dart --update companion assets
dart --disable-dart-dev servers/build.dart --check companion
dart --disable-dart-dev servers/build.dart --rebuild companion
```

根目录先 `flutter pub get`；重建使用 JDK 21、SDK 36、build-tools 37.0.0。`--check` 离线核对，`--rebuild` 比较而不替换，`--update companion assets` 更新 JAR、manifest 与共享资源。文本剪贴板走 scrcpy 控制协议，不由 companion 实现。
