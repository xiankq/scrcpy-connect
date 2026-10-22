# 验证证据与边界

本文记录在指定环境中实际执行的验证及不能由结果外推的范围，不承担产品规则。行为见[产品规格](../../designs/prod/README.md)，资源所有权见[架构](architecture.md)，可重复构建见[工具链契约](repository-tooling.md)。

## 证据层级

| 证据 | 可以说明 | 不能据此说明 |
| --- | --- | --- |
| 静态稿与对象扫描 | 组件引用、布局和代表状态 | Flutter 成像、系统授权或真实设备行为 |
| Widget、协议与故障夹具 | 指定状态、协议形状和交错处理 | 目标 Android、OEM 或完整业务链路 |
| 真实 adbd 或 AVD 流程 | 该环境中的系统接口、编码解码、写入和清理 | 其他设备、网络、平台或长期稳定性 |
| 构建、渲染与性能样本 | 指定产物、renderer 和负载的结果 | 未测宿主或通用性能承诺 |

成功、拒绝、取消、超时、权限撤销、断线和结果未知分别核对。界面重建、短暂断连、进程死亡与系统 Task Manager 停止不能互相代替。ignored 设备用例不计作通过。

## 本轮工程验证

2026-10-22 在 Ubuntu 24.04 x86_64、Flutter 3.47.7、Dart 3.13.5、Rust 1.99.1、JDK 21 上执行：

| 检查 | 结果 |
| --- | --- |
| `tool/check.sh` | 通过；协议 153 条命令、FRB 2.13.0 生成物、服务端 manifest/JAR/helper、共享压缩资源和 Java 兼容夹具一致 |
| DESIGN.md | 官方 0.4.0 parser 0 error、71 warning；warning 为项目扩展 token、孤立 token 和对比度提示，未被隐藏 |
| Dart/Rust 静态检查 | 全仓 Dart analyze（fatal infos）、analyzer 插件检查、Rust workspace Clippy `-D warnings`、Dart format 415 文件、`cargo fmt --check` 均通过 |
| Rust 测试 | `cargo test --workspace` 全部默认非 ignored 用例通过；真实 adbd、USB、mDNS、FFmpeg 等环境用例保持 ignored |
| Flutter 测试 | `app` 423 项、`design_system` 25 项、`interop_bridge` 191 项全部通过 |
| 工具测试 | `tool/test` 与 `tool/e2e/tests` 69 项、设计 token Node 测试 3 项全部通过 |
| Android | 三 ABI debug APK 构建通过；签名、ZIP/CRC、16 KiB 原生对齐、Manifest、Flutter/Rust ELF 和六份共享资源检查通过 |
| Xcode 工程 | iOS/macOS scheme XML 可解析，工程对象引用全部可解析；当前 Linux 环境未执行 Xcode 编译 |

Android APK 的包名和签名身份未因显示名调整而改变。当前检查覆盖 debug 三 ABI 包，不等于 iOS、macOS、Windows 包已构建或已安装。

## 控制、连接与恢复

远控输入的 Dart 队列按页面串行派发；每个触点只保留尚未发送的最新 move，down/up/cancel 不合并且作为顺序屏障。Rust 对普通输入使用有界录取，在等待 ADB 回执时合并连续 move，并按完整消息边界批写；队列满、过期、写入失败和画质重建分别有独立回归。该设计避免无界 Future、结果未知后重放和跨新会话回填旧输入。

ADB writer 对普通流保留有界 FIFO，并为控制帧提供独立优先额度；单流 ACK、burst credit、有序关闭与反向流额度仍由传输层核验。视频积压以源 PTS 的相对增长检测，满足条件时通过优先通道请求新的视频段；它不假设主控与被控时钟同源。

自动重连由 Bridge 的租约协调器管理，原生连接代次负责拒绝旧尝试和旧清理结果。应用级后台重连条件只有 `backgroundKeepAlive`；旧 `backgroundConnection` 已从默认值、产品条件和协议输入中移除，读取旧存储时会被迁移清除。显式停止、系统停止、重新附着、身份替换和事件缺口均不能自动复活已结束的工作。

通知快捷回复已从协议、companion、UI、测试夹具和驱动中移除。产品范围内的通知操作只有接续原内容与清除，清除不推断原应用消息已读。

## 设备与系统证据

下表是仓库中保留下来的实际设备/AVD 结果。除“本轮工程验证”外，这些 opt-in 流程本次没有在真实设备上重新执行。

| 对象 | 已执行证据 | 仍不能说明 |
| --- | --- | --- |
| 首次授权与 TCP | 安全配置 API36 AVD 上拒绝未配对证书和错码，完成真实 PAKE、Required TLS 和撤权后拒绝旧身份 | 量产安全证明、物理 USB、其他 OEM 或真实 Wi-Fi 漫游 |
| USB 与扫码 | API36 双 AVD 通过系统相机扫码、应用 PAKE、mDNS 和连接端口发现；USB/IP 软件装置通过系统允许/拒绝、FD 交接、真实 adbd shell/sync 与拔除后重新获取 FD | 物理线缆、OTG 角色、厂商 USB HAL、被控 RSA 授权或电气链路 |
| 视频、窗口与比例 | 双 AVD 实际编码/解码 H.264、H.265、AV1、VP8、VP9，并核对首帧、Texture、截图、暂停恢复、停止和清理；整机与独立窗口通过比例、resize、质量重建及约 411dp 逻辑密度样本 | 物理 GPU、实体 ARM、其他 OEM、连续手感、并发负载或性能达标 |
| 输入、声音与后台 | API36 上核对真实触控/文字、中文与 emoji 精确一次、HOME 后释放输入、PCM 与播放时钟；应用级连接 FGS 与音频 FGS 分离，多窗口保活可随开关协调 | 物理扬声器可闻、Gboard 候选 UI、进程死亡后的长期后台、双向通话音频 |
| 文件与内容 | 真实 adbd 验证 push/pull、哈希、中文/非 UTF-8 名称、空目录、冲突、取消、链接循环和源变化；系统 provider 验证保存、目录选择与入站 grant | 所有外部 provider、目录整体事务、空间耗尽组合或设备未测权限 |
| 相册与媒体暂存 | API36 双 AVD 验证分页、部分可读、缩略图、原件取回、预览租约和清理后的实际回收 | 全盘删除联动、长期 ENOSPC、所有视频 API 或外部读取完成 |
| 通知与通话 | 独立 APK 与真实 Binder 验证创建、更新、撤回、原动作失效、打开和精确清除；通话使用系统聚合状态，无法可靠定位具体呼叫时保持受限并交回原电话应用 | 第三方消息服务、OEM/锁屏全部组合、双向音频或安全逐呼叫控制 |
| 主控系统提醒 | API36 双 AVD 验证通用隐私文案、源撤回、精确取消与 SystemUI 点击后进入来源设备 | Windows 发布（明确不支持）、其他主控、OEM 后台或所有通知渠道 |
| 玻璃材质 | API36/x86_64、Impeller OpenGLES、Mesa llvmpipe 上核对静止、按住、拖动、归位、滚动背景、实体偏好和减少动态的 8 个状态 | 物理 GPU、Apple 原生等效、完整连续手感、读屏或多视频性能 |

连接健康、无线重连、首次配对和媒体机制的当前责任边界分别见[连接健康](connection-health.md)、[无线重连](wireless-reconnect.md)、[首次配对](first-pairing.md)和[媒体暂存](media-cache.md)。被控版本与 API 条件见[兼容边界](android-target-compatibility.md)。

## 性能证据

当前历史样本仍受 debug/AVD、软件编码或软件 renderer 限制。2026-10-22 的受控回环代理单轮样本只支持“协商 burst 后输入到可读像素方向较好”，不支持无条件降低码率或帧率；目标端还出现 Choreographer 跳帧。具体方法、数值和时钟限制见[视频性能](video-performance.md)。

首帧、输入延迟、窗口确认和清理必须分别报告。首包、playing、Texture 挂载或 snapshot 可读不能替代真实新像素；一次成功输入也不能证明稳定 P50/P95/P99、热功耗或小时级稳定性。

## 未验证边界

- 当前没有物理 Android ARM/OEM 设备、物理 USB 数据线、OTG 角色、真实 Wi-Fi 漫游或全部被控 API 21–35 组合的复验。
- 当前没有物理 GPU、Apple 原生材质、读屏、连续多视频负载或长时间温升/功耗数据。
- iOS、macOS、Windows 整包未在当前 Linux 环境构建；显示名和 Xcode 工程只完成源码/对象结构检查。Windows 系统提醒发布不受支持。
- Linux C++ runner 未构建：当前宿主缺少 CMake；Linux runner 仅用于本地开发与成像，不是正式交付证据。
- 未执行需要隔离设备、官方 adb、FFmpeg、BoringSSL fixture、mDNS 或特定权限的 ignored 用例；它们继续保持待验证。

## 复现入口

从仓库根运行默认工程门禁：

```sh
./tool/check.sh
```

Android 整包检查要求 `ANDROID_HOME` 指向 SDK，并可在默认门禁后运行：

```sh
flutter build apk --debug --no-pub \
  --target-platform android-arm,android-arm64,android-x64
dart tool/check_android.dart app/build/app/outputs/flutter-apk/app-debug.apk
dart tool/native_contracts.dart
```

设备用例按测试声明提供隔离目标和 opt-in 参数；驱动、夹具与性能入口见 [E2E 工具](../../tool/e2e/README.md)。临时截图、日志和测试安装不作为长期输入。
