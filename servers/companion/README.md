# Android Binder companion

`src/com/interop/companion/Main.java` 编译成临时的 DEX JAR，在被控手机上以 shell 用户（UID 2000）运行，提供 ADB 和 scrcpy 没有的能力。主控侧的调用代码在 [CompanionService](../../app/lib/core/companion/companion_service.dart)。

## 能力

| 能力 | 能做什么 | 不能做什么 |
| --- | --- | --- |
| 通知 | 动态注册通知监听、返回通知快照、触发通知原来的 `contentIntent`。清除通知后通知列表会更新。 | 不改通知的已读状态，已读由原应用自己维护。 |
| 通话 | 汇总观察通话状态；打开手机当前的系统通话界面。`calls.openPhoneApp` 打开当前用户的系统电话应用（不带号码），不依赖通话观察。 | 不能定位到某一通具体通话：所有 `calls.action` 都返回 `call_targeting_unavailable`。通话音频状态为 unknown。 |
| 应用 | Android 10（API 29）及以上：当前用户的标准任务和真实图标。 | 不伪造已安装应用列表；API 29 以下返回 `apps_running_unavailable`。 |
| 缩略图 | 在独立的子进程里解码，限定大小，只输出 JPEG。视频缩略图需要 API 27 及以上。 | 取消后无法确认子进程已清理时返回 `media_cleanup_unknown`。 |

文本剪贴板走 scrcpy 控制协议，不由 companion 实现。

## 协议

- 认证过的 socket 上逐行传 JSON（协议版本 1），用 `requestId` 对应请求和响应。消息大小上限、方法签名兼容性和字段定义以源码为准。
- token 和通知动作只保存在内存里，不落盘。
- 启动 companion 不会自动开始观察通知；用 `observation.set(enabled, epoch)` 明确开关监听。
- socket 关闭后，companion 注销监听并退出。主控必须等进程退出后再删除 JAR。

## 构建

先在仓库根目录运行 `flutter pub get`。重建需要 JDK 21、Android SDK platform 36、build-tools 37.0.0。

```sh
# 更新 JAR、manifest 和共享资源
dart --disable-dart-dev servers/build.dart --update companion assets
# 离线核对
dart --disable-dart-dev servers/build.dart --check companion
# 临时重建并比较，不替换产物
dart --disable-dart-dev servers/build.dart --rebuild companion
```
