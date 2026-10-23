# scrcpy 固定源码对照：ADB、启动、控制与恢复

日期：2026-10-23。仅做源码研究，未修改生产代码、启动设备或执行性能测试。

基线为项目 manifest 指定的 scrcpy 5.0.1，提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`；已校验源码归档 SHA256 `a0d699fc7388b8252416c49e6293639de39ab76a03e7302ddced56c284d45200`。本项目按当前工作区源码取样，包含尚未提交的重构，不能把以前 fvp/HTTP/容器路径的结论套到这里。

本文的“确认”指静态源码能直接证明该行为；“风险”指能指出成立条件与代码窗口、尚未用设备或并发夹具重现。未测量的分配、复制、调度或网络等待不换算成毫秒。

## 先给结论

当前热路径没有 Dart 媒体字节，也没有 fvp 或 HTTP 中转。但控制输入仍走 Flutter → Dart 业务层 → JSON → FRB → Tokio 控制 actor → ADB。Android USB 还有 `nusb → 64 KiB 临时 buffer → 128 KiB Tokio duplex → ADB Frame Vec → 视频 packet Vec` 的用户态搬运；Android/iOS TCP 没有 USB duplex，但有 ADB Frame Vec 到视频 Vec 的一次复制。三个桌面平台的 smart socket 后端直接把 TCP 数据读进视频 Vec，不经过移动端 ADB Frame 解析/路由，不能统一算相同复制次数。

最值得优先处理的是：输入缺少传到 Rust 的 capture 代际；控制读写共用单 actor 且写侧优先；桌面鼠标与键盘语义缺失；恢复画面必须重新启动编码器。应用窗口通过外部 dumpsys 差集辨认 display，正常 Dart 入口已按设备串行，但外部建屏幕仍可能产生歧义。其次才是上传、额外进程和微小复制。

## 1. 真实路径与上游区别

| 主控 | 当前路径 | scrcpy 桌面基线 | 直接结论 |
| --- | --- | --- | --- |
| Windows/Linux/macOS | Rust smart socket TCP → 私有官方 adb-server → USB/TCP/TLS → adbd → localabstract scrcpy socket | SDL/C 客户端 → 主机 TCP tunnel → 官方 adb-server → adbd → scrcpy socket；默认先尝试 reverse，失败才 forward | 都有官方 adb-server 与主机本地 socket；我们的桌面没有凭空多一个 ADB 服务中转层 |
| Android TCP、iOS TCP/TLS | Rust 直接解析 ADB，单 transport 复用视频/控制/音频/文件/companion | 上游桌面不提供这一宿主实现 | 少了主机 adb-server 进程与其本地 TCP hop，但要自己维护协议/认证/USB/流控兼容性 |
| Android USB | Java 授权 FD → nusb → Tokio duplex → Rust ADB → 视频 packet | 上游官方 adb 的 USB backend → tunnel | duplex 与 adapter 任务是本项目额外抽象；上游 USB backend 也有缓冲和复制，不能声称差额就是全部零拷贝 |

证据：[当前 smart socket 打开与 NODELAY](/home/xiankq/git/scrcpy-connect/crates/adb/src/server.rs:196)、[当前读取分支](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:1422)、[当前 USB 桥](/home/xiankq/git/scrcpy-connect/crates/adb/src/usb.rs:237)、[上游 tunnel 选择](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/adb/adb_tunnel.c#L124)、[上游三路 socket](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L625)。

## 2. 输入正确性与交互能力

### T01：输入代际只存在 Dart 队列，未进入 native 命令（高优先级，竞态风险）

`RemoteBinding` 包含代际，Dart 在队列出队前检查它；但 `send()` 实际发送的参数只附加 `sessionId`。Rust 对 touch/key/text 查找“当前同 sessionId 的 Session”，不要求 generation 或 captureGeneration。质量重建保留逻辑 sessionId 并替换 capture，且重建完成后 `qualityRebuilding` 会恢复 false。

成立窗口：旧请求已通过 Dart admission，跨 FRB/执行器延后；新 capture 已完成；旧请求随后进入 Rust。此时 key/text 没有任何 capture 检查；touch 只检查尺寸，画质修改后尺寸不变也能通过。UI 队列本身的 fence 不能证明跨 native 调度边界的 fence。当前 ready/frame 对代际的严格校验没有覆盖输入。

证据：[Dart 发包](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1159)、[Dart admission](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/remote_presentation.dart:712)、[Rust 当前 session 解析](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1379)、[重建保留 ID 并增加代际](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2164)、[touch 仅尺寸校验](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:3180)。上游单一 C controller 的会话/socket 寿命直接绑定；并无同一个逻辑 ID 经 FRB 定位新 capture 的这一层：[controller](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L20)。尚未安排竞态复现。

### T02：控制接收被发送队列与正在执行的 write 挡住（确认架构差异，超时风险）

`run_control` 是一个 actor，`tokio::select! { biased; requests.recv(); stream.read(); }`。请求持续 ready 时，接收分支没有公平性保证；处理 write/一个输入 batch 时也完全不读 control socket。剪贴板 ACK、设备消息、remote EOF 都要等这一 actor 回到 read。移动 classic ADB 的 `write_all` 还会等每个 WRTE 的远端 ACK；burst 模式可能只等 credit/本地入队；桌面 smart socket 是主机 TCP write。因此三者阻塞条件不同。

这可以令已经到达的剪贴板 ACK 在应用侧滞留，调用者先达到 6 秒 deadline；也会延迟断开检测。上游 controller writer 和 receiver 是两个线程，接收不依赖发送队列排空。不要把 6 秒说成平时固定延迟。

证据：[当前 biased select](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2852)、[batch 写入期间不读](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2950)、[classic/burst 写语义](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:1167)、[上游两个线程](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L219)、[上游 receiver 阻塞读取](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/receiver.c#L184)。

### T03：桌面鼠标只有手指式拖动，没有完整鼠标语义（确认功能缺口）

页面只监听 down/move/up/cancel；没有 pointer signal、hover 或 pan/zoom listener。发包忽略 `PointerEvent.kind/buttons`；Rust 的 actionButton/buttons 固定为 0，pointerId 使用 Flutter pointer 编号，不能表达 scrcpy 的 mouse pointer 与按钮组合。滚轮、触控板滚动、悬停、右键/中键/侧键、相对鼠标不能按上游方式工作。Android/iOS 外接鼠标也受同一页面限制。

证据：[页面 Listener](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1726)、[页面参数](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1259)、[协议两个按钮字段写 0](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:3204)、[上游 motion/click/scroll](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/mouse_sdk.c#L58)。这是明确缺少控制链路，和视频 GPU 性能无关。

### T04：键盘丢失修饰键、原始字母键与 repeat 语义（确认功能缺口）

页面只映射 escape/back/enter/backspace/tab/arrows/home/delete；字母走 `session.text`，没有把 Ctrl/Shift/Alt/Meta 状态交给 mapped key。Rust 虽允许 metaState，但页面没有传；repeat 字段恒为 0。因此 Ctrl+A、Ctrl+方向、Shift+Enter、游戏中的持续原始字母键等，无法获得上游原始按键的完整语义。Flutter KeyRepeatEvent 虽会再次发 down，Android repeat count 仍为 0。

证据：[页面 key](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1348)、[Rust key 序列化](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1642)、[上游 modifier/repeat](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/keyboard_sdk.c#L215)。上游还提供 UHID/相对鼠标/游戏手柄等路径；本项目 control actor 虽识别 UHID_OUTPUT 帧长度，却不处理其输出事件，不能据此宣称支持 UHID。

### T05：中文输入走剪贴板设置+粘贴+ACK，且串行挡住后续输入（确认行为与开销）

ASCII 文本会切成不超过 300 字节的 INJECT_TEXT；任何非 ASCII 则走 `clipboard_set(..., paste=true)` 并等协议 ACK。因 `RemoteInputQueue` 按次 await dispatch，中文提交后面的 key/touch 会等待这次 ACK 完成。该策略使中文可用，但改变目标剪贴板，增加消息尺寸、反向 ACK 与调度，并受 T02 影响；Android API<24 被明确拒绝。不能简单把“文本很短”当成没有网络 RTT。

证据：[当前 text 分支](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1666)、[队列串行 await](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/remote_input_queue.dart:103)、[clipboard pending ACK](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:3005)、[上游键盘 text 注入](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/keyboard_sdk.c#L298)。上游默认 SDK text 对任意 Unicode 也不保证可注入；这是我们的兼容策略与相应代价，不能写成上游完全解决了中文。

### T06：IME 保存全部已输入历史，每次提交重新分词（确认额外 CPU/内存增长）

`textChanged()` 把 previousText 与 next 全部 `.characters.toList()`，从头找共同前缀；提交后保存 `previousText=next`，只有变成空、失焦或重置才清空。连续输入 n 个字符时，累计比较与 grapheme 分词工作趋于 O(n²)，本地 TextEditingValue 历史占用 O(n)。这不是媒体热路径，但长时间键盘输入可能渐慢。上游 SDL text event 只处理事件文本，没有本项目这一整段历史比较。

证据：[当前 IME diff](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1309)、[上游事件文本复制](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/keyboard_sdk.c#L317)。未做长文本性能测试。

### T07：移动端笔压力直接套进 0..1，未归一化（条件兼容风险）

页面把 `event.pressure` 直接交给 Rust；Rust 严格拒绝不在 0..1 的值，没有使用 Flutter pressureMin/pressureMax。对实际报告范围超出 0..1 的触控/笔驱动，会导致动作被拒绝。该风险依具体设备事件取值，尚无设备复现。鼠标/普通触摸常见的 0/1 值不会触发。

证据：[直接传 pressure](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:1264)、[严格验证](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:3197)。上游接口也以归一化压力为协议输入；应在 Flutter 事件边界核对归一化语义，而非放宽线协议。

### T08：本地输入队列并非完全有界；move 合并仍累计所有 waiter（确认额外占用）

Rust actor 容量为 64；Dart `_pending` 是普通 List，没有最大值。每次合并 move 虽只保留最新坐标，但仍创建并追加一个 Completer 到同一 entry.waiters，且 `_pending.remove`/removeAt(0) 是列表搬移。一次慢的非 ASCII ACK 或控制请求期间，移动事件 waiter 与非 move 边沿仍能增长。与“只保留最新 move，所以内存恒定”的描述不符。

证据：[当前 Dart 队列](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/remote_input_queue.dart:25)、[合并时累计 waiter](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/remote_input_queue.dart:42)、[Rust 入队上限](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2367)。上游控制队列 60 条以上也会丢普通事件，只有 UHID create/destroy 是不可丢；不能把普通 up 的丢弃说成本项目独有：[上游 queue](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L95)、[上游 droppable 定义](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/control_msg.c#L358)。

### T09：每次 move 仍走 JSON 与 FRB request/response（确认额外工作）

最新 move 合并发生在 Dart/控制 actor 两处，中间每个真正 dispatch 的请求仍创建 Map、encode JSON、跨 FRB、serde_json::from_str、构造 Value、查 session/RwLock、构造 Vec、返回 accepted JSON，再解码回 Dart。Rust batch 还通过 extend_from_slice 再复制每条控制消息。上游 SDL event → C struct → controller 固定序列化 buffer → socket，少了 JSON/语言边界/业务层状态同步。

证据：[Dart nativeRequest](/home/xiankq/git/scrcpy-connect/packages/device_runtime/lib/device_runtime.dart:788)、[Rust JSON 解析](/home/xiankq/git/scrcpy-connect/crates/interop_bridge/src/protocol.rs:44)、[Rust 批量拼接](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:3134)、[上游固定序列化 buffer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L142)。这些操作数量已确认，净延迟和 CPU 百分比需 profile，不能靠源码报数。

## 3. 启动、服务器部署与进程

### T10：默认整屏不再强制 encoder probe；显式配置/应用窗口仍有第二次完整部署（确认）

默认 H264 + 默认 encoder + 整屏只尝试已有 catalog cache，同时做一次 dumpsys power；不再必然提前启动枚举进程。显式 codec/encoder 或独立应用窗口才枚举，缓存 miss 时会先上传一份完整 scrcpy JAR、启动 list_encoders、删除 JAR，再上传另一份 capture JAR。且 probe 要完整清理后才继续，即使已经发现设备休眠。相比上游正常直接启动服务增加了检查，但避免显式应用启动先迁移任务再发现 codec 不可用。

缓存按真实 Client 连接身份记录，使用 OnceCell 合并同连接的并发请求，最多保留 32 个 entries；peek 对不存在/失败/进行中的 probe 立即返回 None，不等待 probe。连接替换不复用 catalog，失败可重试。因此成功缓存后的 probe 是轻量本地读取/列表 clone；冷 miss 才是真实设备部署。证据：[EncoderCatalog](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/encoder_catalog.rs:18)。

证据：[当前 probe 条件](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:654)、[完整 probe 部署](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1918)、[power shell](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/device.rs:2037)、[上游正常 push 后直接 server](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L1055)。这是兼容/副作用约束的代价，并非无用途垃圾。

### T11：每个 capture 都上传 2,954,916 B JAR；“每次上传”本身上游也有（确认）

本项目每次 capture 用唯一临时路径，完整上传，然后每次 teardown 删除，无法复用远端已存在的同内容 JAR。当前 JAR 为保留 API21 兼容的 core-library desugared 构建，manifest 给出 2,954,916 B。实际 wire 量会受到协商压缩影响，不能直接按 2.95 MB 乘网络速率估算启动。

上游每次启动同样调用 `adb push`，所以不能把“上游不上传、我们上传”列为区别。我们的额外部分是更大的特定构建产物、多进程功能分拆以及 probe 二次部署。未获取固定官方 release JAR 的字节数，本文不编造倍数。

证据：[manifest](/home/xiankq/git/scrcpy-connect/servers/vendor/manifest.json:1)、[当前 capture 上传](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:840)、[压缩选择](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:42)、[上游 push_server](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L57)。

### T12：音频、keep-active、companion 各有独立进程/部署（确认，产品范围差异）

一个视频窗口用一个 scrcpy JVM；设备声音另起一个 scrcpy JVM；keep-active 再起 control-only scrcpy JVM；剪贴板 get/通知/电话由 companion JVM 提供。它们各有 shell supervisor + stdin watcher，且启动 keep-active/companion 使用无压缩 sync.push。设备多窗口与独立音源可以避免每窗口重复采音，但单窗口加全部功能时，进程数、JAR 上传、ART 类加载、Binder 初始化、shell/ADB logical streams 都超过上游一个 Server 内的 video/audio/controller AsyncProcessor。

证据：[keep-active 命令与 push](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy_keep_active.rs:99)、[音源独立启动](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/audio.rs:342)、[companion 部署](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/companion.rs:161)、[共享 supervisor 的两个 job](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/remote_process.rs:68)、[上游同进程 audio/video/controller](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java#L103)。独立进程隔离/设备共享所有权有实际用途，不应未经设计直接合并。

### T13：启动多一轮进程身份验证 shell（确认开销）

managed supervisor 先用 STOP/CONT gate 获取 PID+kernel starttime，再发送 identity。拿到元数据后另外开 shell 验证 `/proc/pid/stat` 与完整 nice-name。校验与等编码首帧并行，因此增加的是 `max(首帧,身份校验)` 的尾部，不能把全部 shell 时间直接相加。高 RTT 场景仍可能让首帧已经准备好但 ready 被 shell 往返挡住。上游通过所启动的 adb 子进程与 socket 监督，没有这轮远端 /proc 身份 RPC。

证据：[gate](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/remote_process.rs:15)、[验证 shell](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:331)、[与首帧 try_join](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1062)、[上游 server 线程](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L1055)。

### T14：我们的 forward 服务重试和上游 reverse 建链不同（确认差异，不能直接判慢）

本项目强制 server `tunnel_forward=true`，主控直接开 localabstract smart socket/ADB logical stream，首次失败按 40 ms 间隔重试（单次最多 600 ms）；上游通常先准备 reverse listener，由 server 主动连回，失败才走 forward，forward 重试间隔 100 ms。本项目省去 tunnel CLI 安装/移除，但服务刚就绪可能等下一个 40 ms tick，并且每次桌面重试重做 smart socket transport/service 协商。上游的 reverse 是否在特定网络更快需实测，不能凭“reverse”命名宣称少一个媒体 hop。

证据：[当前 socket 重试](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:942)、[smart socket 两阶段 request](/home/xiankq/git/scrcpy-connect/crates/adb/src/server.rs:203)、[上游 default reverse](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/adb/adb_tunnel.c#L124)、[上游 forward 重试](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L663)。

### T15：应用窗口 display 身份依赖文本 dumpsys 差集，存在并发歧义（高优先级，风险）

启动前遍历 `dumpsys display` 中名称为 scrcpy 的 ID，启动后再次 dumpsys，要求新增恰好一个。正常 DeviceRuntime 入口的 DeviceQualityCoordinator.open 已按设备串行启动，缓解项目内部两个 app 同时启动的竞态，不应把它描述成正常 UI 必现问题。但外部 scrcpy 进程同期建屏幕、或绕过 Dart 的 Core 调用仍可共享同一前置 snapshot：后置可见两个新屏幕而失败；若可见性错开，还需验证是否可能把另一 capture 的 ID 当作自己的。上游 Controller 与 NewDisplayCapture 在同一进程内部直接传递 displayData，不依赖主控扫描公共显示名。

此外当前 parser 精确匹配 `DisplayInfo{"scrcpy", displayId `，Android/OEM dumpsys 文本变化会导致识别失败；这是文本接口兼容风险，而不是 codec 是否支持。

证据：[当前差集](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy_display.rs:90)、[正常入口按设备串行](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/device_quality_coordinator.dart:45)、[前置扫描与后置扫描](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:702)、[后置/迁移](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1014)、[上游内置 capture/controller 连接](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java#L139)、[上游 displayData 映射](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/Controller.java#L482)。未执行并发设备复现。

### T16：应用窗口额外 shell 往返多于整屏（确认）

独立应用窗口还会依次查询 `wm size;wm density`、前置 `dumpsys display`、后置 `dumpsys display`、启动后 `cmd activity stack list`；改尺寸时额外 `wm density -d` 再发 RESIZE_DISPLAY；重建先核验旧 task、再迁移现有 task。除 identity 与首帧外，这些检查不都并行。跨网 RTT、dumpsys CPU 与 Binder 开销会增加启动/resize 尾延迟，不能用整屏测试结果代替应用窗口。

证据：[metrics](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy_display.rs:40)、[task](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy_display.rs:129)、[窗口 resize](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1690)、[首帧后的 task](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1083)。上游同一个 Server/Controller 可直接 resize capture：[上游 controller resize 调度](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c#L129)。

## 4. 传输、复制与公平性

### T17：移动 Rust ADB 有可定位的 payload 复制（确认）

接收 `Frame::read_observed_progress` 为每个 ADB payload 分配并清零 Vec，完整读完后 move 到 bounded route channel；`AdbStream::read` 再 `copy_from_slice` 到 scrcpy packet Vec。scrcpy 每个 payload 又 `vec![0;length]` 分配清零。Frame 到 channel 只是移动所有权，不应算复制；移动 direct ADB 不会因为 Rust 语言而自动零拷贝。

桌面分支 `server.read(output)` 直接读 caller packet Vec，跳过上述 Frame payload Vec 与 route channel。后续 MediaSource/FFmpeg copy 由媒体报告另列，不能漏算或重复。

证据：[ADB 分配读取](/home/xiankq/git/scrcpy-connect/crates/adb/src/protocol.rs:55)、[route move](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:665)、[consumer copy](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:1441)、[视频 Vec](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2699)。上游也把 socket payload 读入 AVPacket，不能写成压缩输入完全零拷贝：[demuxer](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c)。

### T18：Android USB adapter 额外两任务与 duplex（确认）

IN endpoint reader(64 KiB)，两 transfers；读进 64 KiB 临时 Vec，再 write_all 到 128 KiB Tokio duplex，由 ADB parser 再读出来。OUT 方向 ADB serializer 先写 duplex，另一个 task 把 wire header/payload 重新解析到临时 Vec，再写 nusb 并按 header/payload 结束 USB transfer。头与 payload 分开并 flush_end 是 ADB USB/ZLP 边界要求，不能擅自称多余；但 duplex 搬运与再次分配/解析是可消除的抽象成本。

证据：[完整 USB adapter](/home/xiankq/git/scrcpy-connect/crates/adb/src/usb.rs:237)、[二次 parse 分配](/home/xiankq/git/scrcpy-connect/crates/adb/src/protocol.rs:141)。不宣称上游官方 USB backend 没有自己的缓冲；本结论是当前本地具体搬运数，不是测得的差额。

### T19：burst 实际默认是开启意图，不能误报 app 默认 classic（确认）

`ConnectOptions` 库默认 false，但本产品 default settings `adbBurstMode=true`，连接把它传入；只有双方 advertised delayed_ack 才激活。旧设备或不支持的 peer 仍 classic，控制每个 WRTE 会等待 ACK；modern burst 则可按字节 credit 发送。桌面官方 adb 自己决定真实设备 transport 的流控，Rust 的 `Client::burst_mode()` 不代表官方 server 内部是否启用 delayed_ack。

证据：[产品默认](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/preferences.rs:253)、[传入连接](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/device.rs:633)、[双方协商](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:429)、[classic/burst 发送](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:1175)。

### T20：控制 priority 不等于端到端抢占；视频读 ACK 与文件共享通道（确认边界）

移动 transport 有 64 普通 writer、16 priority writer、128 control-response queue，actor 将控制 stream 设 priority。但一个已经开始写的大 Frame 不能被抢占，手机→主控方向也已经按 ADB transport 次序到达；视频消耗返回的 OKAY/credit 走普通 writer。大量 SYNC 上传可能令视频 ACK 与普通 frame 排队，控制优先也无法越过已经发出的 USB/TCP frame。

这些共享 transport 带宽与串行线协议瓶颈在官方 ADB 上同样存在，不能把“与文件共用一根 ADB 链路”全算自写 Rust 的缺陷。当前没有应用级媒体/文件带宽保留或 frame 大小适应的证据，若追求极致多业务并行延迟，应单独验证 saturated transfer + touch + video。

证据：[priority writer](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:489)、[read ACK 普通 writer](/home/xiankq/git/scrcpy-connect/crates/adb/src/client.rs:1449)、[控制设 priority](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2837)、[上游所有通道复用 ADB tunnel](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L625)。

### T21：本地 NODELAY 已设置，不应重复列为缺陷（确认）

桌面 smart socket query/connect/open 均 set_nodelay(true)；移动 TCP 选项默认 nodelay，应用由 connection policy 显式传入。上游只需要发送控制的客户端 socket 设 NODELAY，媒体以接收为主。额外网络代理未设置 NODELAY 不能外推为产品 socket 的缺陷。每个 ADB frame 之后 `writer.flush()` 对普通 Tokio TCP 不是另加一个网络 RTT，USB 的 flush_end 另有边界意义。

证据：[桌面](/home/xiankq/git/scrcpy-connect/crates/adb/src/server.rs:203)、[移动 TCP policy](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/device.rs:635)、[ADB flush](/home/xiankq/git/scrcpy-connect/crates/adb/src/protocol.rs:124)、[上游 NODELAY 原因](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/server.c#L708)。

## 5. 暂停、恢复与多窗口调度

### T22：暂停丢编码包，恢复强制重启 encoder；与上游“保存最新解码帧”不同（确认）

本项目 pause 设置状态后，run_video 仍从设备读流但不再将后续包送 decoder。resume 设置 awaitingSession，再发 RESET_VIDEO，等新 session/config/keyframe。上游暂停仅跳过 texture 更新，仍解码并持续保存最新 AVFrame；resume 能立即呈现已保存帧，无需网络/MediaCodec restart。

当前方案节省暂停期间主控解码/转换 CPU，但不节省被控编码或媒体带宽；恢复增加控制消息、网络传递、编码器 restart、配置、关键帧、decoder reset 与 renderer readiness。快速切页反复遮挡会反复走这个恢复链。此处不是无损优化，需以后台功耗对恢复延迟取舍。

证据：[pause/resume](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1591)、[丢包](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2783)、[上游暂停仍保存帧](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L994)。

### T23：自动 backlog reset 使用高阈值，而且等待 control write 会停读视频（确认策略差异）

arrival−PTS 相对最小值增长达到 800,000 µs，连续至少 8 个有效帧才触发，cooldown 4 秒。它不会检测稳定存在的初始延迟；低 fps 时 8 帧也会拉长触发时间。trigger 后 video reader await request_control，最长受 6 秒控制 deadline 限制，此时视频流本身不继续消费；read ACK/credit 随之停滞，可能放大正在恢复的 backlog。之后丢弃旧流直到新 session，而非在 host queue 中直接追至可解码新帧。

阈值是当前防积压的策略，不是极致延迟目标；它比没有任何保护好，但不能据此保证低延迟。上游基本 decoder/显示策略由媒体报告另述；不能把两边不同队列做简单等同。

证据：[guard](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2505)、[阈值常数](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:34)、[视频 await control](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2740)。

### T24：所有设备画质重建被一个全局 mutex 串行（确认跨设备等待）

`reconfigure_session` 开头拿 `self.quality_changes.lock()` 并持有到整个启动/回滚/keep-active 同步结束。任一设备的慢网络、旧进程恢复显示、首帧或回滚会阻塞其他设备完全独立的画质修改。重建还先向旧 encoder 发一次 RESET_VIDEO barrier，再启动新 capture；作为安全排空 barrier 有用途，但会让一个即将废弃的旧 encoder 再启动一次。

证据：[全局锁](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2028)、[旧 encoder barrier](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2111)、[physical override 等待 release](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:2125)。上游一个 scrcpy client 通常只有一条画面；这里是多设备产品新引入的调度问题，不是上游现成多设备锁实现可直接复制。

### T25：本地主动取消不等于已经确认远端退出（确认语义边界）

process monitor 在 cancellation 分支 `break` 后也立即将 `process_closed=true`，随后 drop ADB exec stream；它没有等 shell EOF、supervisor wait 或 `/proc` 消失。stop_session 等这个 bool 最多 3 秒，因此这个等待最多证明本地读任务退出，不能证明 Java 已完成退出/清理。physical display 重建另外检查 lease 路径消失，keep-active 有额外核验；普通 capture stop 没有同等级远端确认。

managed_shell supervisor 有真实进程所有权与 EOF 终止逻辑，通常可清理；本条不是认定一定泄漏，而是 stop receipt/资源回收完成的证据层级不足，短时尾部占用、OEM 卡住和快速重开需分别验证。上游同样涉及 remote cleanup，不能承诺对端进程在断线瞬间消失。

证据：[monitor cancellation 与 closed](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:914)、[stop 等 bool](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1282)、[supervisor wait](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/remote_process.rs:48)。

### T26：目标编码器本身仍保留上游低延迟设置，不能把所有延迟归 FFmpeg（确认）

项目使用未改 Java sources；repeat-previous-frame-after=100000 与上游默认相同；上游本身设置 surface input、real-time priority=0（API23+）、latency=1（API26+）、默认 I-frame interval 10 秒。项目额外显式写 repeat 参数不构成性能提升。默认产品 1280/60/4Mbps 与上游无限 max-size/max-fps、codec-specific bitrate 默认不等价，必须同分辨率、帧率、码率、codec、encoder 才能比较性能。

证据：[项目显式参数](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:855)、[产品默认](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/video_quality_policy.dart:4)、[上游 format 设置](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L310)、[上游 options](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c#L54)。

## 6. 剪贴板与业务附加链路

### T27：本机剪贴板只有 1 秒轮询，自动同步增加可见延迟（确认）

自动同步先读取设备剪贴板作为本地初值，然后 Timer 每 1 秒读本机 Clipboard；远端变化则由 companion 事件驱动。静态源码能证明主控复制文本到检测之间有 polling phase delay，不能称固定 1 秒，也不能把它计为视频延迟。上游客户端会在相应输入/粘贴事件中同步剪贴板，不经过本项目每秒主机读取这一常驻链。

证据：[本机 polling](/home/xiankq/git/scrcpy-connect/app/lib/services/clipboard_coordinator.dart:171)、[发送](/home/xiankq/git/scrcpy-connect/app/lib/services/clipboard_coordinator.dart:298)、[上游 key/clipboard serialization](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/keyboard_sdk.c#L270)。

### T28：设备剪贴板读取绕过 scrcpy，换来显式空值/错误回执但增加 helper（确认取舍）

scrcpy capture 关闭 clipboard_autosync；clipboard.get 始终交 companion。原因是上游 GET_CLIPBOARD 对空/不可读可以不回包，本项目要求区分未知/空/锁定/非文本。写入优先选现存 capture control channel，没有 capture 才用 companion。这会让“只想读取剪贴板”也依赖 helper 的部署、协议和生命周期；同时保留 capture + companion 两套剪贴板回执路径。不能把 companion 所有 CPU/进程开销都视作视频远控必需。

证据：[路由与原因](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:1809)、[capture 关闭 autosync](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/scrcpy.rs:855)、[helper deploy](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/companion.rs:161)、[上游 receiver clipboard](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/receiver.c#L82)。

### T29：额外 power 查询、mDNS/健康监测与诊断属于产品常驻工作（确认边界）

远控页面每 3 秒 refreshScreenState；Core 另有 connection health tick 与 discovery 事件处理；每条 dispatch 都经过 diagnostics.command。上游单进程工具不承担多设备恢复、通知、状态投影的同等工作。需要采样其 CPU/wakeup 与日志 volume，不能把所有背景唤醒都归解码器。页面 power 查询会和媒体共享设备 Binder/ADB 通道，静态源码不能给出实际可感知影响。

证据：[页面 timer](/home/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/remote/devices_workspace_remote_page.dart:446)、[核心 monitor](/home/xiankq/git/scrcpy-connect/crates/interop_core/src/device.rs:2103)、[每命令 diagnostics](/home/xiankq/git/scrcpy-connect/packages/device_runtime/lib/device_runtime.dart:861)。

## 7. 建议验证顺序（未执行）

1. 用可控 FRB/native 调度门让旧 touch/key/text 在同 ID capture 替换完成后才进入 Rust，验证 T01；命令必须携带 capture fence，不能只测 UI 队列。
2. 对控制 write 施加持续背压，同时发送剪贴板 ACK/remote EOF，验证 T02 与 6 秒超时的因果，而非只测发送侧 acceptance。
3. 同设备同时启动两个不同 app window，另起外部 scrcpy window，验证 dumpsys 差集归属与失败清理。
4. 对比相同 encoder 参数下 pause→resume 的首个新画面，分别记录控制传递、encoder session、首关键帧、解码与 Flutter texture；不要用 decoder 已缓存的旧 snapshot 代替恢复后新帧。
5. Android USB/TCP 分开采样 allocator/memcpy/任务切换；桌面三平台另测 smart socket，不跨后端套复制次数。
6. 同 transport 上行/下行文件满速时同时播放、触摸、中文输入，检查带宽竞争、video ACK、control admission 与尾延迟。
7. 完整输入验收覆盖滚轮、右/中/侧键、hover、修饰组合、repeat、长中文连续输入、笔 pressure range。

这些是可验证的工程工作列表，本文没有修改上述链路，也没有把推论伪装成设备验收结论。
