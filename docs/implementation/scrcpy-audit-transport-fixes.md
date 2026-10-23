# scrcpy 传输与控制审计实施记录

本记录对应 [传输与控制源码审计](../research/scrcpy-source-audit-transport-control.md) T01–T29，记录 2026-10-23 本次工作区的实施与验收。它是版本实施证据，不定义产品默认值或替代领域、产品、架构规范。媒体解码、渲染、包体积及平台交付由本批总清单分别记录。

“已修”表示本项可定位的实现缺陷及相应主机回归已处理；不表示各 OEM、物理 USB、所有平台 GPU 或端到端时延均已实测。保留的架构成本和产品取舍仍列在表内。

## 逐项结果

| 项目 | 本批状态 | 行为与保留边界 |
| --- | --- | --- |
| T01 输入 capture 代际 | 已修 | `session.touch/key/text/scroll` 必须携带正整数 `captureGeneration`，Rust 对当前 capture 严格核验，包含迟到的释放。页面按原绑定保存发送代际，不能在发送旧请求时改取新代际。生成协议来自 `protocol/commands.json`。 |
| T02 控制接收饿死 | 已修 | 独立控制 reader 与 writer；等待 classic WRTE 回执或 writer 队列饱和时，剪贴板 ACK、设备事件和 EOF 仍可消费。pending clipboard replies 在两侧共享并短暂加锁。 |
| T03 鼠标语义 | 部分补齐 | 增加 mouse pointer 标识、hover、滚轮、按钮位及 actionButton，保留拖动中的附加按钮变化。hover/scroll 同样受前台与当前所有者 admission 约束。未实现相对鼠标、UHID、游戏手柄与完整触控板 pan/zoom；不能宣称与上游所有输入模式等价。 |
| T04 键盘语义 | 已修审计中的基本缺口 | 常用物理字母、数字、标点、F1–F12、导航及修饰键走原始 key，传整体 Shift/Alt/Ctrl/Meta/Caps/Num 状态及 repeat。Home 为 Android MOVE_HOME，工具栏主屏幕仍为 HOME。未扩展为所有键位、布局、UHID 与游戏设备的完整兼容矩阵。 |
| T05 Unicode 文本剪贴板路径 | 保留兼容策略 | 非 ASCII 仍设置剪贴板、粘贴并等待协议 ACK，后续输入保持顺序；兼容限制、剪贴板副作用与网络回执成本保留。T02 消除 ACK 被本地控制 writer 堵住的缺陷，未把协议 RTT 变成零。 |
| T06 IME 历史增长 | 已修 | 已提交编辑历史超过 128 grapheme 时，保留 sentinel 与最近 64 grapheme 的可编辑后缀，不再随整个会话无限增长。组合文本提交、emoji 边界和后续插入有回归。 |
| T07 压力范围 | 已修 | Flutter 事件边界按 pressureMin/pressureMax 归一化并夹到 0–1；释放为 0，退化范围使用有效缺省。Rust 线协议校验保留。OEM 笔硬件尚未实测。 |
| T08 Dart 输入队列 | 已修 | 有界 LinkedList，默认容量 256，正常新输入最多占一半，为释放留余量；move/hover 共用一个完成 Future 并保留最新位置，O(1) 合并与出队。溢出明确拒绝、撤销新的控制 admission 并清理已持有输入，不静默积累。不是无限数量按键释放均能入队的保证。 |
| T09 JSON/FRB 成本 | 保留架构成本 | 仍经 Map/JSON/FRB、session 定位与返回值。未引入另一条未经生成契约管理的快通道；净 CPU 与时延比例仍需 profile。 |
| T10 显式编码探测二次部署 | 保留安全前置检查 | 默认整屏已有缓存快路径保留。显式格式与应用窗口的冷探测仍可能部署 probe 后再部署 capture，以先确认能力再产生应用副作用。未冒进共用会被上游 CleanUp.unlinkSelf 删除的临时 JAR。 |
| T11 capture JAR 上传与大小 | 保留并明确边界 | 每 capture 唯一临时部署及既有协商压缩保留。未删除 API21 所需 desugaring、受控源码或许可证；本批没有测得 JAR 大小或 probe 复用带来的额外缩减。伴随服务上传的压缩改进见 T12。 |
| T12 独立音源、保活与 companion | 保留所有权，优化上传 | 独立设备音源、保活及业务 helper 的寿命、隔离与显式回执保留。keep-active 与 companion 改为使用同一协商压缩选择；协议不支持时仍无压缩，不在部分写入失败后静默换协议重传。 |
| T13 进程身份验证 RPC | 保留安全校验 | 启动 PID、kernel starttime、完整 nice-name 的验证保留，并继续与首帧工作并行。未用省一轮请求换取 PID 误认风险。 |
| T14 forward 建链与重试 | 保留并待实测 | 继续直接连接 localabstract 与有界重试；未把与上游 reverse 的结构差异伪装成已经证实的慢路径，也未宣称 reverse 必然更快。 |
| T15 虚拟 display 身份 | 已修 | 从当前拥有的 scrcpy exec 完整日志行 `New display: ... (id=N)` 获取 ID，拒绝不完整、非正或冲突 ID。仅应用窗口启用 info 日志，不再按全局同名显示的启动前后差集猜归属。 |
| T16 应用窗口额外往返 | 部分消除 | T15 删除前后两轮 dumpsys display；metrics、task/旧任务位置核验、必要 resize 与恢复校验保留。未移除防止迁移错误任务的业务确认。 |
| T17 ADB 与 packet 分配复制 | 部分消除 | Frame payload 用受 remaining 长度约束的 `read_buf` 填充容量，消除整块预清零；视频 packet 预留 64 字节尾部并转交 `packet_owned`，避免再扩容复制。ADB Frame 到 scrcpy 报文重组的拷贝、内核与 nusb transfer 缓冲仍存在，不能称端到端零拷贝。ABI2 的实现验收由媒体清单负责。 |
| T18 USB relay | 已修 | `UsbTransport` 直接实现在 nusb endpoint 上的 AsyncRead/AsyncWrite；移除两个 relay task、Tokio duplex、临时 payload Vec 与 OUT 完整报文二次组装。保留 24 字节头边界状态、header/payload 分开的 submit_end、flush、短包/ZLP 与背压。物理 USB 各平台仍需设备验收。 |
| T19 burst 默认与协商 | 无需修复 | 产品开启意图及双方 delayed_ack 能力协商保留；不能把产品默认误报为 classic，亦不能由 Rust 标志推断官方 adb 内部真实 transport 流控。 |
| T20 共享 transport 抢占 | 保留协议边界 | 既有控制 priority 保留，不能抢占已经开始的 ADB frame 或手机发送顺序。未增加媒体/文件带宽预留；饱和文件传输下的触控与视频实测仍需单列。 |
| T21 NODELAY | 无需修复 | 既有 smart socket/TCP NODELAY 保留；未把 TCP flush 计为额外网络 RTT，USB flush_end 的帧边界用途也保留。 |
| T22 暂停与恢复策略 | 保留产品取舍 | 暂停期间消费但不送解码，恢复需新 SESSION/配置/关键帧；减少主控暂停期解码工作，仍付出恢复成本。未宣称与上游持续解码并保留最新帧等价，亦未宣称暂停会停止被控编码或带宽。 |
| T23 自动 reset 堵住视频 reader | 已修堵塞与迟到回执竞态 | 自动 RESET_VIDEO 由独立有界任务等待已完成控制写入，视频继续读取和返回 ACK。只允许一个 reset 在途；capture segment 原子标记保证新 SESSION 先到时，旧 write receipt 不会重新把它标记 awaiting。保留 800ms/8帧、4秒 cooldown 与确认超时策略；它不能检测稳定存在的初始时延。 |
| T24 画质全局串行 | 部分修复，保留资源上限 | 全局只允许一个 transient replacement 的资源预算保留。排队新增 queued/depth/reason 状态事件、30秒上限与窗口 lifetime 取消；等待失败有明确错误。旧 encoder 的 RESET_VIDEO barrier 改为仅排空先前控制写入的本地 Barrier，避免重启即将废弃的 encoder。不是改成多设备无上限并发。 |
| T25 远端退出证明 | 已修错误完成语义 | 先 drop 本地 exec 请求 supervisor 清理，再经独立 shell 核对 `/proc/PID/stat` 的 kernel starttime；仅原身份消失、PID 已复用或原进程已退出时置 process_closed。3秒内不能确认则 stop 回执明确 `processCleanupVerified:false` 与错误，不宣称远端清理成功。断线、OEM 卡死无法由主控保证对端即时消失；原 display lease 的额外恢复检查保留。 |
| T26 上游低延迟 encoder 设置 | 无需修复 | 保留上游 surface/priority/latency/repeat 设置。性能对比必须统一分辨率、帧率、码率、codec 和 encoder，不能把显式重复缺省值计为优化收益。 |
| T27 本机剪贴板轮询 | 部分优化 | Flutter view 恢复焦点时立即检查外部复制，不等待下一轮 tick。前台持续期间仍以1秒轮询兜底；Flutter 公共 Clipboard API 没有统一跨平台变更订阅，本批没有引入每个平台的新插件。设备激活时“远端先作为本地初值”语义不变。 |
| T28 companion 剪贴板读取 | 保留明确回执 | 读取仍区分空、未知、锁定与非文本；写入优先已有 capture control，不能为了合并服务放弃失败语义。helper 的启动与往返成本仍存在。 |
| T29 power、发现、健康与诊断 | 保留产品工作 | 本批没有删除产品需要的健康监测、发现、安全查询或诊断。多窗口轮询合并等其他范围的实施由总清单记录；本文件不将未做的 CPU/wakeup 采样算成性能通过。 |

## 修改入口

- `crates/adb/src/protocol.rs`、`usb.rs`：ADB payload 初始化与 USB endpoint 适配。
- `crates/interop_core/src/scrcpy.rs`、`scrcpy_display.rs`、`scrcpy_keep_active.rs`、`companion.rs`：控制并行收发、输入协议、display 身份、reset、画质排队、进程退出证明及上传压缩。
- `protocol/commands.json` 与 `dart run tool/protocol_codegen.dart` 的生成输出：capture fence 与滚动命令，不手工维护生成物。
- `app/lib/pages/devices/workspace/remote/`、`app/lib/services/clipboard_coordinator.dart`：有界队列、键鼠/压力、IME 与焦点回归检查。
- 对应主机协议/Flutter 回归及直接发送输入的 integration fixture：携带其原 capture 代际；未为旧夹具放开 Rust fence。

`crates/interop_core/src/media/`、`packages/media_codec/`、`packages/device_runtime/` 的媒体实现与平台包产物不属于本子任务修改范围。已对 ABI2 ownership/通知/detach 作只读交叉检查，并将暂停清队列缺 source_waker 通知的问题交媒体负责人修复；其最终测试见媒体实施记录。

## 已执行验证

- `INTEROP_TEST_MKSH=<临时解包的 mksh> cargo test -p interop-core --lib --no-fail-fast`：193 passed、16 ignored、0 failed。包含真实 ADB classic writer 背压下剪贴板协议 ACK 可前进、严格 capture fence、鼠标/滚轮 wire 字段、视频 reset 回执滞后时继续消费媒体、新 SESSION 优先、全局画质排队可观察且可取消、display 日志归属。ignored 设备用例不计通过。新增进程证明测试明确标为需要实际 mksh 的 ignored 测试，不能因工具缺失早退计 pass。
- `INTEROP_TEST_MKSH=<临时解包的 mksh> cargo test -p interop-core --lib process_cleanup_proof_waits_for_exit_and_handles_reused_pid_without_signalling -- --ignored --nocapture`：另行执行 1 passed；实际等待存活子进程退出，并验证 PID starttime 不匹配时只认定原身份已释放、不会发信号给复用进程。mksh 通过 `apt-get download` 与 `dpkg-deb -x` 临时解包，没有安装到系统。
- `cargo test -p interop-adb --no-fail-fast`：99 个非忽略测试通过。包括 USB 头/载荷零长度及 512/65536 边界、跨片段边界，以及现有流控、关闭、协议与同步回归。需要设备或专门网络环境的 ignored 用例未执行。
- 在 `app/` 运行输入队列、remote input、生命周期、质量 barrier、clipboard、presentation 六组 Flutter 测试：76 passed、0 failed。包括 10,000 move 合并共用 Future、有界队列、原始修饰键/repeat/鼠标/capture 身份、IME 长历史截断后继续输入与焦点返回不等待轮询 tick。
- 定向 Dart analyze：remote 页面目录、clipboard coordinator 及相关输入测试无问题；完整主应用 analyze/测试与平台构建由总验收记录汇总。
- 以上为 Linux 主机协议和 Flutter 组件级证据。Android arm64/Android16 真机、Android emulator 实际投屏、Windows/macOS/Linux GPU、各平台物理 USB、长时间温升功耗与可导出的端到端延迟分布，不能由本页的单元/夹具结果替代。
