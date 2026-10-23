# Android Binder companion

临时 DEX JAR，通过已授权 ADB 以 shell UID 2000 运行，不安装 APK。入口在访问 Context/Binder 前核实身份，必要时从工程系统的 root 降权；失败即退出。源码在 `src/com/interop/companion/Main.java`，Rust 编排在 `crates/interop_core/src/companion.rs`。

## 能力与限制

| 入口 | 行为与边界 |
| --- | --- |
| 通知 | 动态 Binder listener、当前快照及变化对账；正文取系统提供的文本，打开原 `contentIntent`。动作引用随进程/修订失效。打开仅确认系统接受，清除不表示已读；不提供快捷回复 |
| 通话 | 读取系统聚合状态，观察引用不是具体 call ID。所有 `calls.action` 返回 `call_targeting_unavailable`，音频状态保持 unknown；不能安全定位的全局接听/挂断不开放 |
| 剪贴板 | 首次 get/set 才初始化，Rust 优先复用现有 scrcpy 控制通道。只读首项已有文本，不解析 URI/Intent。set 读回核对；未知写入不重试 |
| `apps.list(filter:"running")` | API 29+ 当前用户标准任务，非进程活跃度；缺权限/接口不冒充空列表，不回退安装目录。达到512项边界失败 |
| `apps.icon` | 目标当前用户的真实包资源，96×96透明PNG、上限128KiB；缺包/图标显式失败。缓存须保留设备、用户和包名归属 |
| `media.stat/thumbnail` | 独立有界队列与解码子进程，只回传小JPEG和源事实，不下载原件补救 |

Binder 调用使用真实 `com.android.shell` 归因；旧系统仅在已知签名不存在时选择兼容签名，权限拒绝不触发绕过。剪贴板检查锁定、权限与 AppOps，不修改它们；非文本、锁定和拒绝分别失败。文本 UTF-8 上限262130字节，转义后仍须满足1MiB消息边界；变化来自 callback，不写日志或持久化。

缩略图队列最多一个运行、一个排队；JPEG 最大256KiB、64–512px（默认256），图片输入上限256MiB/100MP，视频64GiB。源以 `O_NOFOLLOW` 打开并核对文件身份，Rust 再验源戳/摘要。取消须确认子进程回收，无法确认返回 `media_cleanup_unknown`；8秒 watchdog 限制解码。API 21–23保留同一FD的EXIF兼容路径；视频仅API 27+，旧版返回 `thumbnail_api_pending`。

固定AOSP依据、权限及跨版本签名见[Android shell能力研究](../../docs/research/android-shell-interop-capabilities.md)，媒体细节见[缩略图管线](../../docs/research/media-thumbnail-pipeline.md)。

## 协议与观察生命周期

- 随机 abstract socket 与256位认证token；token不落盘、不写日志。协议v1为带 `requestId` 的UTF-8 JSON line，响应与事件独立传输。
- 单消息1MiB，通知快照768KiB；超限显式 `truncated=true`。通知和动作仅存内存，完整内容交回原应用。
- 共享helper启动不自动注册观察。Rust `observation.start/stop/status/list` 管理持久意图；断线保留意图但内容标为 unknown，主动停止后重连不重启。
- `observation.set(enabled, epoch)` 回传状态与清理确认；停止注销通知/通话listener并清动作，保留剪贴板和媒体工作。helper UUID、连接、epoch及事件水位共同拒绝旧结果。
- socket关闭后注销并退出；未连接启动期限20秒。Rust持有shell stream，等待退出并清理本次JAR。依赖和所有权见[架构](../../docs/implementation/architecture.md)。

## 构建与测试

先在根目录 `flutter pub get`。构建使用JDK 21、SDK 36、build-tools 37.0.0；完整输入和摘要以 `manifest.json` 为准。

```sh
dart servers/companion/build.dart
dart servers/companion/build.dart --check
dart servers/companion/tests/compatibility.dart
dart servers/package.dart
```

`--check` 校验输入/产物摘要并在临时目录重建逐字节比较。修改源码或构建脚本后提交重建JAR、manifest及共享打包结果，规则见[工具链](../../docs/implementation/repository-tooling.md)。兼容测试检查旧AIDL、进程等待和API 21字节码边界，不证明OEM权限。

设备测试只使用已授权的隔离AVD：

```sh
bash servers/companion/tests/build-fixture.sh
dart servers/companion/tests/android-probe.dart \
  --adb "$ANDROID_ADB" --serial emulator-5556 --calls --skip-receiver
INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  ANDROID_ADB="$ANDROID_ADB" ANDROID_TARGET_SERIAL=emulator-5556 \
  cargo test -p interop-core --test companion_android -- --ignored --nocapture --test-threads=1
```

同一环境下可将测试名改为 `observation_android`；它要求隔离AVD已有文字剪贴板并在结束后恢复。`companion_clipboard` 仅需 `INTEROP_CORE_TEST_ENDPOINT`，同样使用 `--ignored --nocapture --test-threads=1`。

通知快照回归先构建[通知夹具](../../tool/e2e/notification_fixture/README.md)，再运行：

```sh
dart servers/companion/tests/notification-snapshot.dart \
  --adb <absolute-adb-path> --serial emulator-5556
```

拒绝覆盖已有夹具，核对BigText/Inbox/MessagingStyle、更新/撤回、旧动作失效与重新附着；finally仅清理本run资源，不改产品权限/AppOps。API 36 AVD结果及其他设备待验范围见[验收记录](../../docs/implementation/validation.md)。
