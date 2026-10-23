# scrcpy 传输与控制审计实施记录

2026-10-23 工作区的 T01–T29 结果；上游机制见[固定源码研究](../research/scrcpy-source-audit.md)，当前资源责任见[架构](architecture.md)。

## 逐项结果

| 项 | 结果与保留边界 |
| --- | --- |
| T01–T02 | touch/key/text/scroll 必带原绑定 captureGeneration，Rust严格核验，迟到释放也拒绝。独立control reader/writer，classic WRTE确认或写队列饱和时，clipboard ACK、事件及EOF继续消费。 |
| T03–T04 | 补mouse pointer、hover、scroll、按钮/actionButton，基本物理键/修饰状态/repeat；Home为MOVE_HOME，工具栏为HOME。未实现UHID、相对鼠标、游戏手柄及完整触控板/键位矩阵。 |
| T05–T07 | 非ASCII仍走剪贴板粘贴并等ACK；IME超过128 grapheme保留sentinel及最近64，pressure按范围归一化0–1。兼容副作用和协议RTT保留，OEM笔未测。 |
| T08–T09 | Dart队列256，普通输入最多一半、留释放余量；move/hover O(1)合并并共享Future，溢出拒绝/撤销准入并清已持输入。Map/JSON/FRB调用路径保留，未做净CPU占比profile。 |
| T10–T13 | 默认整屏缓存快路径保留；显式codec/应用窗口先probe再capture。每capture独立JAR、音源/保活/companion独立寿命，PID/starttime/nice-name校验保留；keep-active/companion共用协商压缩，失败不静默换协议重传。API21 desugaring及源码许可证均保留。 |
| T14–T16 | localabstract直连/有界重试保留；display ID来自拥有exec完整New display日志，拒绝冲突。删除启动前后dumpsys差集，保留metrics、任务归属/resize/恢复核验。未测forward/reverse性能优劣。 |
| T17–T18 | ADB payload按remaining以read_buf填充，视频预留64字节并移交ABI2。USB直接适配nusb，删除duplex/relay与临时payload；保留头边界、submit_end、flush、短包/ZLP和背压。报文重组/内核缓冲仍复制；物理USB各平台未验。 |
| T19–T21 | 保留burst双方delayed_ack协商、control priority及NODELAY；不能抢占在途ADB frame/对端发送顺序。无媒体带宽预留，饱和文件传输下需单列实测。 |
| T22–T23 | 暂停继续消费但不解码，恢复等新SESSION/配置/关键帧。自动RESET由单个有界独立任务等待写回执；segment防止旧回执覆盖新SESSION，保留800ms/8帧、4秒cooldown。无法检测稳定初始积压，暂停也不停止对端编码/带宽。 |
| T24 | 保留全局一个transient replacement预算；排队发布depth/reason，30秒上限并随窗口取消。旧encoder只做本地控制Barrier，不再RESET即将废弃encoder。 |
| T25 | drop exec请求supervisor清理，独立shell核对PID/starttime；仅原身份消失/退出/复用时process_closed。3秒未证实则processCleanupVerified:false，保留display恢复检查。断线/OEM卡死无法保证对端即时退出。 |
| T26–T29 | 上游encoder低延迟配置保留；本机剪贴板焦点返回立即检查，前台1秒轮询兜底。companion空/未知/锁定/非文本回执、健康/发现/诊断均保留，未做CPU唤醒/功耗测量。 |

## 实现与验证入口

- `crates/adb/src/{protocol,usb}.rs`：payload、USB及流控回归。
- `crates/interop_core/src/scrcpy*.rs`、`companion.rs`：控制并行、capture fence、display、reset、画质排队、退出证明、压缩；`protocol/commands.json` 是生成契约。
- `app/lib/pages/devices/workspace/remote/`、`app/lib/services/clipboard_coordinator.dart`：输入队列、IME、键鼠与焦点回归。

Linux主机协议与Flutter回归通过，覆盖classic背压下ACK前进、capture/wire字段、reset迟到回执与新SESSION、取消/排队、display归属、USB头/载荷与512/65536边界、10,000 move合并。严格Clippy和定向Dart分析通过。设备/专门网络用例未计通过。

进程退出证明需要真实mksh，使用 `INTEROP_TEST_MKSH=<mksh> cargo test -p interop-core --lib process_cleanup_proof_waits_for_exit_and_handles_reused_pid_without_signalling -- --ignored --nocapture`，已显式执行通过，核对等待子进程和PID复用不发信号；缺工具必须失败。整库入口为 `cargo test -p interop-core --lib` 与 `cargo test -p interop-adb`。物理USB、OEM、温升功耗、端到端延迟分布不在本页主机夹具覆盖内。
