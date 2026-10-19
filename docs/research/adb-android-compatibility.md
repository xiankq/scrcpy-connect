# ADB 低版本兼容与开源实现参照

研究日期：2026-10-19。第 1–6 节保留源码研究阶段的证据分类；后续实施及实际 API21／23 验证见[被控兼容边界](../implementation/android-target-compatibility.md)。本文固定上游源码，研究独立 Rust ADB 主机与较低 Android **被控设备**版本；不更改产品规格、ADR、主控平台最低版本或现有实现。遵循 [ADR 0001](../adr/0001-apk-free-controlled-device.md)、[0002](../adr/0002-rust-adb-and-flutter-monorepo.md)、[0006](../adr/0006-controller-without-debugging.md)：Rust 主机直接连接 adbd，经 FRB 接 Flutter；不依赖外部 adb；被控不 root、不装 APK，可临时执行 JAR；主控普通应用身份。

**结论：先补足同一 ADB 主机的旧协议协商与同一服务端的功能门控，Android 5.0/API21 是当前 scrcpy 上游明确支持的被控基础下限。不能因为音频、独立应用窗口需要较高版本，提前拒绝该设备的基础连接、文件与整机远控。** ADB 库本身可继续研究更旧 adbd；本次没有证据可把完整远控下限降至 Android 4.x。复用其他语言项目的协议行为和接口设计，不改变既定技术栈。

证据分为：**上游明确支持**（固定发布/文档声明）、**源码事实与工程推断**（实际阅读的分支及影响）、**本项目未验证**（没有执行设备、编译或端到端测试）。第三方的测试和自述不构成本项目验收。本次只读源码并写此报告；临时副本隔离于系统临时目录，不运行其构建脚本或设备操作。

## 1. 固定来源与复用约束

| 对象 | 实际阅读版本/提交 | 许可证与用途 |
| --- | --- | --- |
| AOSP 旧 ADB | `android-4.4.4_r2`（`efbf36f2dad8f083de6f48dbb682461d7cfa9781`）、`android-5.0.0_r1`、`android-7.0.0_r1`（`88f64719d75620d144af5bba39a00a3f178ae60a`） | 所读 ADB 文件头 Apache-2.0；协议及旧 daemon 的直接依据 |
| AOSP 新 ADB | `9084198a2d4b0f6a0f174260fb42da33485b684d`，既有研究使用的 Android17 分支快照 | Apache-2.0 文件头；现代 host 如何兼容旧 daemon；不声称等于某 Platform Tools 二进制构建 |
| scrcpy | **v5.0.1**，`a60891aea193d92e7e5c3942700eca63f9d19a5f`；官方 latest 发布于 2026-10-08 | Apache-2.0；被控 JAR 的当前兼容行为，不直接采用其调用外部 adb 的主控实现 |
| Tango / ya-webadb | `7bcec613f3441a7f20bdf3e5e8646bce63fe790d`，`@yume-chan/adb` 源码版本 `3.0.0-beta.4` | MIT，另有 AOSP `adb.NOTICE`；优先参照其旧/新服务接口与能力分离 |
| libadb | `bc681df985967e083cdd7c02df45f942495393a5`，workspace `0.5.0` | MIT；Rust handshake/checksum/service 实现参照 |
| DroidMux | `9adeb6258166e9b88808bc6e67845c73763f070c`，workspace `0.1.0` | MIT OR Apache-2.0；Rust bounded shell/sync 设计参照；尚未发布不是成熟度证明 |
| dadb | `55cb08849b9b17c1e627156a0de11d91d36034de`，源码 `VERSION_NAME=2.0.0` | Apache-2.0；直接 TCP 主机、超时与错误分类参照；不能当旧 Android shell 的标准答案 |
| adb-shell | `149ffbcff47b5a7fbd476cfdb26931e85be0c09c`，源码 `0.4.4` | Apache-2.0；legacy AUTH、shell、FileSync 与故障用例参照 |
| adb_client | `37b5febd743b3e5971d746953d2b141e47b8f811`，workspace `3.2.3` | MIT；直接 transport 与 5037 server 模块分离参照，不整体替换现有核心 |

版本由官方 release API、隔离 clone 的 `git rev-parse HEAD`、源码包元数据核对；HEAD 与同号已发布包不自动等价。许可证分别见 [scrcpy](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/LICENSE)、[Tango MIT](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/LICENSE)及 [AOSP NOTICE](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/adb.NOTICE)、[libadb](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/LICENSE)、[DroidMux](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/LICENSE-APACHE)、[dadb](https://github.com/mobile-dev-inc/dadb/blob/55cb08849b9b17c1e627156a0de11d91d36034de/LICENSE.txt)、[adb-shell](https://github.com/JeffLIrion/adb_shell/blob/149ffbcff47b5a7fbd476cfdb26931e85be0c09c/LICENSE)、[adb_client](https://github.com/cocool97/adb_client/blob/37b5febd743b3e5971d746953d2b141e47b8f811/LICENSE)。若移植源码，保留相应许可/归属、修改声明和实际涉及的 NOTICE；根 MIT 不能覆盖来源文件中仍适用的 AOSP 声明。这里记录所查文件，不替代逐依赖发布审查。

## 2. AOSP：低版本先解决的协议行为

### 2.1 协议版本、payload 与功能必须分别协商

源码事实：Android 5 的 `A_VERSION=0x01000000`、`MAX_PAYLOAD=4096`；Android 7 仍是 **同一个 1.0.0**，上限已为 **256 KiB**；现代 AOSP 是 1.0.1、1 MiB。协议版本不能代替 Android API，也不能单凭版本给每个连接写死 payload。现代 `atransport::update_version()`分别取 `min(remote_version, A_VERSION)` 和 `min(remote_payload, MAX_PAYLOAD)`。[Android5 adb.h](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/adb.h#25)、[Android7 adb.h](https://android.googlesource.com/platform/system/core/+/88f64719d75620d144af5bba39a00a3f178ae60a/adb/adb.h#31)、[现代常量](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.h#33)、[现代协商](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#1177)

工程推断：连接状态应保存协议版本、对端 banner、协商 payload、共同 feature；没有 `features=` 的旧 banner 是空能力集，仍可使用基础服务。发送分片服从已协商 maxdata；1.0.0 被控仍可接收支持范围内的 shell/sync，不能仅因低于本地主机的最高版本拒绝它。`shell_v2`、`stat_v2`、`ls_v2`、`sendrecv_v2`、压缩和 `delayed_ack` 各自门控，不把“旧版”简化为一个全局开关。

### 2.2 CNXN/AUTH 校验在获知版本前就必须兼容旧设备

源码事实：现代 `send_packet()` 在协商前沿用最低协议，给 CNXN/AUTH 计算校验；协商到 1.0.1 才将 `data_check` 写零。`send_connect()`明确将握手 payload 限制在 **4 KiB**，因为此时不知道对端容量。校验是无符号 payload 字节求和，不是旧 `protocol.txt` 命名暗示的 CRC32。[现代 transport.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp#565)、[握手容量限制](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp#329)、[求和实现](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp#113)

可移植接口：`ChecksumPolicy::{Required, Omitted}`由握手状态及协商版本决定；不要让 frame encoder 永远写零，也不要让 reader 永远按现代省略规则放过旧连接的损坏帧。所有握手消息的物理长度单独受保守上限约束；CNXN 的 arg1 声明本地主机接收能力，不等于可在握手中立刻发送同样大的 payload。libadb 的首个 CNXN 明确使用 `Checksum::Compute`，`Checksum::for_version()`再切换策略，可参考其拆分。[libadb handshake](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/connection/handshake.rs#L215)、[checksum](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/protocol/checksum.rs#L17)

### 2.3 旧 OPEN 必须保留字符串末尾 NUL

源码事实：Android5 `handle_packet(A_OPEN)` 将收到 payload 的**最后一个字节原位改成零**，然后才解析服务名。如果主机发送 `shell:echo hi` 而不带 NUL，实际命令会被截掉最后一个字符。Tango 按协商版本，1.0.0 开启 `appendNullToServiceString`，1.0.1 可省略。[旧 daemon OPEN](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/adb.c#587)、[Tango transport](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/transport.ts#L130)

工程推断：有时“连接成功但 sync/socket/shell 不工作”可能是 OPEN 名被截断，不能只测 CNXN。服务名容量校验须计入 NUL；也须保留 `abb` 参数内部 NUL 与末尾服务终止符的不同职责。经典旧连接要求 OPEN.arg1=0、空 OKAY；不能把 `delayed_ack` 的初始额度或信用包发给没有共同 feature 的 daemon。[旧 OPEN/OKAY 状态](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/adb.c#587)

### 2.4 shell v1 不是缺一个退出码的 shell v2

源码事实：Android5 的 `shell:` 使用 PTY，`exec:`使用 RAW subprocess；`shell,v2,raw:`不在其服务分支中。Android7 的官方 host 仅在采用 shell protocol 时发送 close-stdin frame，并明确说明旧连接直接关闭可能丢失尚未读取的尾部输出。[Android5 services.c](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/services.c#424)、[Android7 stdin/服务串](https://android.googlesource.com/platform/system/core/+/88f64719d75620d144af5bba39a00a3f178ae60a/adb/commandline.cpp#550)

工程推断：上层应区分 `RawExec`、`LegacyPty`、`ShellV2Raw`、`ShellV2Pty` 的真实语义；legacy 输出混合、退出码未知，不可伪造 `Some(0)`。无 v2 时的 RAW 启动在 API21 以上可参考 `exec:`；不能把 legacy `shell:`包装成二进制安全管道，PTY 可能改变换行/终端行为。关闭 stdin、resize 等若无真实协议支持应显式报告能力缺失。服务端 JAR 的 stdout 日志与独立视频 socket 分离，避免 legacy shell 输出语义污染媒体字节。

边界反例：Android4.4.4 的源码有 `shell:`，没有 Android5 新增的 `exec:`分支。因此 Tango 为兼容旧系统使用 `exec:`的设计，也不能转述为“所有 Android4.x 已支持”。[Android4.4 services.c](https://android.googlesource.com/platform/system/core/+/efbf36f2dad8f083de6f48dbb682461d7cfa9781/adb/services.c#360)

### 2.5 Sync v1 是独立基础协议，不依赖 shell 工具

源码事实：Android5 的 sync service 已包含 STAT/LIST/SEND/RECV；STAT 实际调用 `lstat()`，mode/size/mtime 为32位字段，失败返回全零而没有 errno。旧文件同步是字节流协议，不要求被控存在 `cmd`、`abb_exec`、压缩或64位 stat。[旧 file_sync_service.c](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/file_sync_service.c#84)、[旧同步命令分发](https://android.googlesource.com/platform/system/core/+/android-5.0.0_r1/adb/file_sync_service.c#457)

可借鉴 Tango 的 `lstat`、`stat`区分：`lstat`选 v1 或 v2；真正跟随符号链接的 `stat`在没有 stat_v2 时显式不支持，而不是把 legacy STAT 假装成跟随查询。LIST、SEND/RECV及压缩分别按 feature 选择；通用 metadata 用可缺省字段，不能为 v1 编造 uid/gid/errno。Sync DATA 的协议块长与外层 ADB WRTE maxdata 是两层上限，parser 必须接受头/数据跨多个 WRTE。[Tango stat types](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/request/stat.ts)、[Tango sync service](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/service.ts)

## 3. 当前 scrcpy：基础下限和功能下限分开

上游明确支持：官方 latest 为 [v5.0.1](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1)。固定源码 README 仍声明 Android5.0/API21；server build 的 `minSdkVersion=21`、`compileSdk=36`、`targetSdkVersion=36`同时存在，后三者不能混作被控最低版本，也不约束 Flutter 主控最低版本。[固定 README](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/README.md#prerequisites)、[server build.gradle](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/build.gradle#L3)

| 被控能力 | 上游声明/固定源码条件 | 对本项目的工程影响 |
| --- | --- | --- |
| 基础整机画面与控制 | API21 / Android5.0 起；具体 ROM、编码器与输入授权仍有设备条件 | 不应被音频或新虚拟显示的下限抬高；本项目仍需真机验证 |
| 新虚拟显示 | `Server.scrcpy()`明确拒绝 API29 / Android10 以下的 `newDisplay` | 独立应用窗口与整机远控支持状态分别给出；一个不支持不否定另一个 |
| 默认输出音频捕获 | API30 / Android11 起；Android11 启动时需解锁以完成 shell 前台 workaround；Android12+ 正常路径 | API21–29 可继续视频；音频流禁用是协议状态，不必导致整次会话失败 |
| playback/dup 音源 | `AudioPlaybackCapture.checkCompatibility()`要求 API33 / Android13；应用可 opt out | 不把“Android11有音频”扩展成所有音源/重复播放模式均可用 |
| 相机镜像 | `Server.scrcpy()`要求 API31 / Android12 | 属独立条件，不能用它决定基础整机远控是否可连 |

来源：[服务端门控](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java#L71)、[音频上游说明](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/audio.md)、[direct capture](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioDirectCapture.java#L107)、[playback capture](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioPlaybackCapture.java#L130)。低于 API30 的编码音频路径直接 `writeDisableStream(false)`并返回，为“视频继续而音频不可用”提供了具体协议参照。[AudioEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioEncoder.java#L205)

源码事实：官方当前客户端仍处理旧 TCP 连接的 reverse 失败，转为 forward；源文件注释点名旧 Android/TCP 场景。这里借鉴的是隧道方向与就绪握手，不是引入外部 adb。独立 Rust 主机可直开 `localabstract:`被控 socket，本项目是否已实现由本地审计判断。不要把 reverse 失败提升为“该设备不支持远控”。[adb_tunnel.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/adb/adb_tunnel.c#L132)、[adb_tunnel.h](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/adb/adb_tunnel.h#L28)

工程推断：继续维护一套固定、可复现构建的 server，在其中按 SDK 与运行时能力门控即可获得上游兼容设计；本次证据不支持为旧设备另建多条旧 server 发布轨道。更新到 v5.0.1 也不能仅替换 JAR，必须审核对应 options、控制消息和媒体协议与本项目改造；源码支持 API21 不等于本项目产物已在 API21 验收。现有 server 扩展的具体最低调用由并行本地审计另行说明。

## 4. 哪些嵌入式项目最值得借鉴

### 4.1 优先：AOSP + Tango 的兼容行为，libadb 的 Rust 接口

Tango 是本轮最有用的跨语言兼容参照：直接 daemon transport 与 server transport 分离；transport 同时保存版本/maxpayload/双方 feature，版本驱动 checksum 和 OPEN NUL；subprocess 把无协议模式与 shell-v2 模式分开，只有双方有 shell_v2 才提供 shell protocol；无协议 process 的 `exited`无退出码，raw spawn 采用 `exec:`、PTY采用 `shell:`。[transport](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/daemon/transport.ts)、[subprocess service](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/subprocess/service.ts)、[legacy service](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/subprocess/none/service.ts)、[legacy process](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/subprocess/none/process.ts)

值得移植的是可表示差异的 Rust 类型与边界测试，不引入 JS runtime。Tango 新能力与兼容分支存在，并不证明每个历史版本都经其作者真机测试；sync mkdir workaround 旁还保留 Android8 待测 TODO，应照实看待。[sync service](https://github.com/yume-chan/ya-webadb/blob/7bcec613f3441a7f20bdf3e5e8646bce63fe790d/libraries/adb/src/service/sync/service.ts)

libadb 的优势是协议核心与 runtime/transport 可分；`ConnectionConfig`控制宣告的接收容量，`Connection`独立保存协商版本与对端发送容量；先 legacy checksum 后按版本切换的结构可以直接对照本项目修复。它也把 shell v1/v2 作为不同模块。不能因同为 Rust 就整库替换：TLS provider、nusb 版本、授权 FD、取消/背压及四端链接仍需按现有[依赖研究](pure-rust-adb-dependencies.md)和本项目资源所有权逐项复核。[ConnectionConfig](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/connection/config.rs)、[Connection](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base/connection.rs)、[shell 模块](https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/shell)

### 4.2 DroidMux：显式 legacy 可参考，默认配置不能直接套用

源码提供 `ShellOptions::legacy()`、`ShellOutput.exit_code: Option`、有界输出与取消；`open_shell`根据 options 选择 reader，`use_v2`却默认 true，无 feature 会报错，调用方必须选择 legacy。更细的注意点：`use_pty=false`的 legacy 服务仍拼成 `shell:`，在 Android5 的实际 daemon 中仍走 PTY；不能仅凭字段名断言 raw。适合借鉴退出码可缺省、输出限额、协议错误与取消，不照搬默认值。[options.rs](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-shell/src/options.rs)、[session.rs](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-shell/src/session.rs#L410)

Sync 模块有 v1/v2 stat 分支和 legacy 全零失败处理，可交叉检查解析边界；它带来的 libusb/ring/zstd 等启用路径已经在既有研究记录，不因降低被控版本而重选整套依赖。[sync protocol](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-sync/src/protocol.rs#L1064)、[依赖边界](pure-rust-adb-dependencies.md)

### 4.3 adb-shell：旧 wire / sync 测试参照

固定版本发协议1.0.0，计算字节和校验，读取 daemon maxdata；legacy shell 不依赖 shell_v2；FileSync 分别有 STAT/LIST/push/pull。它有同步/异步实现及大量异常测试，适合抽取小 payload、半包、认证拒绝、sync FAIL 等测试设计。其公开 API 很多路径返回完整输出，源码自己注明大响应内存风险；不采用这一内存模型作为视频/大文件架构。没有在所查路径发现现代 STLS/pairing 完整实现，不能拿它替换本项目现代无线主机。[constants](https://github.com/JeffLIrion/adb_shell/blob/149ffbcff47b5a7fbd476cfdb26931e85be0c09c/adb_shell/constants.py)、[device](https://github.com/JeffLIrion/adb_shell/blob/149ffbcff47b5a7fbd476cfdb26931e85be0c09c/adb_shell/adb_device.py)、[tests](https://github.com/JeffLIrion/adb_shell/tree/149ffbcff47b5a7fbd476cfdb26931e85be0c09c/tests)

### 4.4 dadb、adb_client：选取局部经验，避免名称造成误判

dadb 直接 TCP handshake 使用1.0.0，保存对端 maxPayload；当前 `Dadb.openShell()`却无条件开 `shell,v2,raw:`。它不是“因为 Kotlin/Java 就更支持老 Android”的证据。具体可参考 `AdbConnection`将阻塞写的停滞期限与读超时分开、失败后释放连接，并通过 `AdbAuthException`区分未授权和其他失败。所查代码固定10秒仅是上游策略，不建议照搬产品超时值。[AdbConnection.kt](https://github.com/mobile-dev-inc/dadb/blob/55cb08849b9b17c1e627156a0de11d91d36034de/dadb/src/main/kotlin/dadb/AdbConnection.kt#L98)、[Dadb.kt](https://github.com/mobile-dev-inc/dadb/blob/55cb08849b9b17c1e627156a0de11d91d36034de/dadb/src/main/kotlin/dadb/Dadb.kt#L35)

adb_client 当前 Rust 工程将直接 message device 与 server device 分目录；不能看到 `pair`/`forward`方法就认定它们直接操作 adbd，相关 server commands 属5037。其直接 handshake 发1.0.0，frame 的 `compute_crc32()`实际为字节求和，可作命名反例；直接 `connect()`对 CNXN 的路径没有持久记录对端版本/maxdata，不能把这段作为完整兼容协商模板。优先复用问题定位/命令编码经验，主机核心仍以 AOSP/Tango 协商为准。[message device](https://github.com/cocool97/adb_client/blob/37b5febd743b3e5971d746953d2b141e47b8f811/adb_client/src/message_devices/adb_message_device.rs#L49)、[message frame](https://github.com/cocool97/adb_client/blob/37b5febd743b3e5971d746953d2b141e47b8f811/adb_client/src/message_devices/adb_transport_message.rs#L60)、[server pair](https://github.com/cocool97/adb_client/blob/37b5febd743b3e5971d746953d2b141e47b8f811/adb_client/src/server/commands/pair.rs)

## 5. 本项目建议的优先顺序与验收证据

以下是依据外部源码的实施建议，**不是对本项目当前代码有无缺陷的结论**；具体本地问题由并行审计核实。

1. **先使旧 adbd 握手和基础 OPEN 完整。** 核查1.0.0接受、握手求和校验、4KiB握手容量、4096协商分片、旧OPEN NUL、无feature banner、经典ACK。协议fixture应模拟 Android5 行为，不能只让现代测试peer接受双方共同的错误。
2. **分离 legacy shell/exec/v2 语义。** 现代raw命令继续用v2；旧raw启动API21+使用exec；PTY明确标记；退出码未知保持未知，拒绝伪造close-stdin/resize。验证含二进制NUL、LF/CR、stderr与非零退出、尾输出、取消。
3. **保证临时JAR部署只需sync v1。** 走STAT/LIST/SEND/RECV，测试sync头跨WRTE、空文件、4096分片、多包大文件、全零STAT、权限失败和取消后丢弃不确定流。v2与压缩仅作共同能力，不是部署前提。
4. **建立同一server的功能支持状态。** 先看整机视频/输入，再独立判断新虚拟显示、音源与其具体模式、各扩展能力。不能用高版本虚拟显示或音频必要条件阻止API21设备整机远控。老TCP reverse不可用时，验证现有直开localabstract的启动与就绪流程。
5. **最后声明被控范围。** 优先覆盖API21、23、24、26、28、29、30及当前高版本的实际设备/模拟器；API21/23检验真正旧shell，API24检验仍1.0.0但shell_v2可用的组合。对每个样本记录实际CNXN版本/maxdata/features，不从API号硬编码协议。至少包含USB与旧TCP；API30+现代无线配对另测。可用时再加厂商真机，模拟器结果不能推导ROM输入/编码器/音频权限。

主控 Android、iOS、macOS、Windows 的编译交付与被控 Android API21 是两条验收轴。实现宜局限于既有 Rust 核心和必要平台接口；无需 Java/Kotlin/TS/Python运行时，也不为旧设备引入额外server轨道。降低被控范围的改动仍须维护取消、资源所有权、有界内存和四端编译；本次没有运行这些检查。

## 6. 尚不能由本轮研究证明的事项

- 本项目 API21/23 的可运行产物、厂商ROM互通、输入权限、编码器表现、长期USB/TCP稳定性。
- 本项目自有协同JAR及扩展Binder调用是否全部使用其声明下限允许的API；应以固定构建输入与本地审计/设备验收分别确认。
- 当前仓库server扩展与scrcpy5.0.1 options、控制协议、媒体标记能否直接混用；上游最低SDK支持不能代替这项兼容检查。
- Android4.x完整整机远控。ADB基础协议确实更早存在，但当前scrcpy明确下限仍API21，且4.4缺少本轮API21 legacy raw启动依赖的exec服务。

后续更新只补固定来源与实际证据；若决定改变产品最低版本，在产品责任文档维护，本文保留研究时点事实。
