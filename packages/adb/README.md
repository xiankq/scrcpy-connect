# adb

One ADB service API over an owned official desktop server or mobile Rust ADB. Device identity, reconnect policy and durable file tasks belong to callers; see [architecture](../../docs/implementation/architecture.md).

`AdbHost.prepare(bindings: ..., dataDirectory: ...)` selects the backend. Desktop requires the pinned executable in `adb/` beside the app (`Contents/Resources/adb` on macOS); `binaryDirectory` is a test override. It never falls back to PATH or direct desktop adbd. 独立 SDK 通过本包自己的 FRB 动态库运行，调用方显式选择原生宿主：

```dart
final bindings = await createNativeAdbApi();
final host = await AdbHost.prepare(
  bindings: bindings,
  dataDirectory: dataDirectory,
);
final devices = await host.client.devices();
```

`initializeNativeAdb()` 只初始化桥接，不创建服务器或设备连接。移动端连接与配对会在首次使用时原子创建指定路径的持久身份；`prepareAdbIdentity(absolutePath)` 可提前显式创建或验证。已有损坏身份、符号链接或过宽 Unix 权限会报错，不会覆盖旧密钥。

组合宿主通过 `AdbHost.prepare(bindings: adapter, ...)` 在创建资源前注入同库 `NativeAdbApi`；桌面适配器同时实现 `NativeAdbServerApi` 和 `NativeAdbHandshakeApi`。准备完成后不能更换原生库。`AdbDevice.nativeOwner` 是不可序列化的宿主身份；不同动态库的设备句柄不可混用。需要与 scrcpy 组合时，使用 scrcpy SDK 提供的配套 ADB client，两者在同一动态库内共享连接。

`prepare` 与 `restore` 必须显式提供同库 bindings，不隐式初始化独立 ADB 动态库。发布构建的 link hook 按编译器记录的 `initializeNativeAdb` 可达性保留独立库；只使用组合宿主时不重复打包。没有可达性信息的调试和测试构建保留独立库。

`NativeAdbClient` 另提供 `AdbConnectionClaims.claimConnection(device)`：撤销旧句柄的普通服务、文件及新捕获准入，等待旧操作及未提交文件片段清理，再换发操作与关闭句柄。底层 Client、连接登记及已有 scrcpy 捕获保持不变；后续断开新句柄仍会撤销该连接的捕获 lifetime。旧客户端迟到关闭只触及旧句柄，不能关闭后继；认领失败保留原句柄供重试或断开，期间不恢复普通操作准入。借用登记不能认领。

`AdbDevice.id` 是可更换的操作句柄；`connectionFacts.connectionId` 是不可持久化的底层连接身份，用来核验认领前后为同一 Client。`serverAddress` 只报告实际代理端点，不能证明官方服务器进程或 transport ID 未被复用。认领不验证设备身份，也不接管其他客户端仍在进行的握手。`OfficialAdbClient` 暂不提供连接认领；服务器控制权限与设备连接权限分别交接。`serverId` 仅对原生登记实际拥有的服务器返回，外部服务器为空；它不是设备身份。`admissionScopeKey` 报告最近一次确认交付的技术 scope 名称；未确认认领不修改它，同一物理 Client 的独立借用不继承它。该字段只提供归属事实，不授予操作或关闭权限。

`host.client` provides `devices/connect/disconnect/pair`, binary shell events and regular-file push/pull. `client.services` adds:

| Group | API and constraints |
| --- | --- |
| Facts/raw | `connectionFacts`, `open`, `connectSocket`, `exec`, bounded `serviceResponse`; raw services have no generic stdin half-close |
| OPEN facts | `createOpenProbe` owns one bounded OPEN attempt; layer, actual write and response facts are separate from caller health policy |
| Shell/Binder | `shell`, `abb`, `abb(exec: true)`, `cmd`; shell_v2 supports separate binary stdout/stderr, exit, stdin, `closeStdin` and PTY `resize`. Legacy shell retains merged output/unknown exit |
| Controls | `reboot`, `tcpip`, `usb` acknowledge requests, not reconnection |
| SYNC | `stat/lstat/list/push/openPush/pull/pushFile/pullFile`; raw-byte names, bounded data and explicit none/Brotli/LZ4/Zstd compression |
| JDWP | `jdwp`, `trackJdwp`; bounded PID snapshots, not app identities |
| Reverse | `reverse`, `reverseList`, `reverseRemove`, `reverseRemoveAll`; the last affects all device listeners |

Desktop services pin the official server's transport ID; reconnect requires a new handle. Each session allows one pull-based reader and one pending write of at most 64 KiB. Stream pause applies backpressure; cancellation/`close()` drains the service without closing its device. `addStream` chunks input and cancels its producer on close. Use SYNC `finish()` or shell `closeStdin()` for EOF; do not write concurrently. Cancellation, deadlines and abandoned-handle expiry bound work.

直连与官方服务器客户端的便捷 shell、push/pull 均与各自显式 services 共用唯一操作会话登记和精确关闭权；官方客户端不再嵌套第二个直连客户端。普通 shell 事件在 `AdbServices` 内统一转换。文件上传与下载统一由 `AdbSyncRequest` 进入同一原生 SYNC 执行器，原生绑定不另设平行的 transfer 入口。事件流缺少真实终态时返回 `result_unknown`，不能把 EOF 当作执行成功。`AdbPath.bytes` 和 SYNC 请求在构造时复制路径，并只公开不可修改的字节；异步解析连接期间修改输入数组不能改变当次目标。原生空闲回收按最后一次实际读取和在途读取判断，正常消费间隙不立即过期；释放失败保留原操作重试。

`connectionFacts.inboundActivity` 是同一 `connectionId` 内只比较是否变化的不透明标识。`createOpenProbe(device, service: ..., timeout: ..., cancellation: ...)` 返回独立 `AdbOpenProbe`；调用方保存对象、读取 `result`，最后 `close()`。结果明确区分直连 ADB 与官方 smart socket 层，报告 `openWritten` 和响应结果；写出前容量或排队超时不证明对端沉默。关闭只取消并排空本次探针，不关闭共享设备或客户端，失败可用同一对象重试。创建后取消或 facade 关闭导致交付失败且精确清理失败时，`AdbOpenProbeCleanupFailure.probe` 交还重试所有者。SDK 不决定闲置间隔、失败阈值或重连。

需要在上传失败后精确重试清理时，使用 `sync.openPush(...)` 先取得并保存 `AdbServiceSession`，再绑定取消。并行读取 `events` 和写入输入，调用 `finish()` 后等待完整终态；成功或失败都须关闭本次 session，关闭失败保留该对象重试。入口不接收取消令牌，调用方须等待迟到创建结果并回收；不能通过关闭共享 `services` 代偿本次资源。普通 `push` 保持返回字节数的便利接口。

Push may leave a remote partial. Pull refuses an existing destination and removes its own partial on failure. A stalled streaming producer may delay remote SYNC status; cancellation/deadlines still apply. Byte paths are literal; string paths are UTF-8 without shell expansion.

`createNativeLocalFiles()` 提供无需设备连接的本机文件能力。调用方明确传入允许范围、目录条目上限、复制字节预算和期限；SDK 不安装应用默认值。`LocalFileScope` 通过目录描述符访问范围内路径，返回保真的文件身份和原始名称。复制句柄持有源与独占创建的未发布片段，提交核验原片段且禁止覆盖；关闭先取消并排空，再按精确身份清理未发布片段。提交结果未知时不重试或删除可能已发布的文件。借入的 provider FD 被复制，调用方仍须持有原始租约直到复制完成或关闭确认。Linux/Android 提供该机制，其他宿主明确拒绝，不以普通路径 rename 代替相同安全保证。

本机所有者在打开描述符前预留资源：每进程最多 64 个范围及 64 个在途范围创建，每范围最多 16 个根、32 个复制句柄及 32 个并发操作；全进程最多 128 个复制句柄和 256 个并发操作。达到容量返回 `LocalFileErrorCode.busy`，无效根数量返回 `invalidArgument`。打开失败归还容量，清理未确认继续占有原名额；同 key 接管沿用原范围名额，满额时仍可精确恢复。根目录的祖先只需搜索权限，授权根本身保留可读目录描述符用于列举和同步；Android 私有目录不会因为 `/data` 无法列举而被拒绝。

`capabilities` exposes backend differences: desktop `authorize:false` only reuses an authorized transport; forced TLS requires a discovered secure mDNS fullname. Android mobile alone supports `connectUsbFd`. The API does not wrap every adb CLI command or elevate target permissions.

`OfficialAdbClient` 实现 `AdbTransportDiscovery.transports(...)`，返回官方 `devices -l` 的序列号、状态、USB 路径及 transport ID 等事实，保留离线和未授权传输；调用方据此选择候选，不根据序列号格式推断传输类型。它不保存应用设备记录或自动接纳候选。

直连 `connect(..., directOptions: AdbConnectOptions(...))` 与 Android `connectUsbFd(..., options: ...)` 明确接收 burst、公钥注释和 TCP 参数。默认保持经典流控、`interop-adb` 注释及关闭 keepalive/user timeout；产品默认值由调用方传入。USB 只应用握手参数，不应用 TCP 字段。官方服务器自行管理握手与 socket，拒绝显式 `directOptions`，不会虚构配置成功。参数与期限在准备身份或连接端点前验证；无效参数不会创建密钥。

公钥注释限制为 1024 个 UTF-8 字节且不含 NUL、CR、LF；TCP keepalive 的 idle/interval 接受 1000–32767000 毫秒，retries 为 1–127，内核时间精度可能向下取整为秒。user timeout 为 1–2147483647 毫秒且只支持 Android/Linux。Dart 的时间须为整数毫秒，不静默截断更小单位。应用健康检查、重连间隔和设备身份绑定不属于这些执行选项。

`connect`、`pair` 与 Android `connectUsbFd` 接收 `cancellation: AdbCancellation`。原生适配器在执行前登记单次握手准入，取消通知真正的协议等待，调用结束前等待实际原生 worker 与本机资源回收；迟到成功连接按原句柄精确断开。`client.close()` 同样撤销本客户端的在途准入，不取消其他客户端的握手。身份准备涉及本机磁盘操作，取消会等待它实际完成；取消本身不删除已创建的长期密钥。Android 原始 USB FD 在工作线程启动前复制，平台连接仍按接口要求持有至设备断开。

需要独立重试 USB 握手清理时，调用 `NativeAdbClient.beginUsbFdConnection(...)` 同步保留本次 `NativeAdbConnectionAttempt`，再等待 `attempt.result`。失败或取消后调用同一 `attempt.close()`，等待迟到登记及本次未交付连接释放；失败可重试，不关闭共享客户端或其他连接。成功交付后关闭责任转给接收者，`attempt.close()` 不断开已交付设备。原始平台 `UsbDeviceConnection` 的租约随成功连接持有至其实际断开；尚未交付时须等尝试清理确认后再释放。此入口要求适配器支持 `NativeAdbHandshakeApi`。

需要跨 isolate 接管移动端客户端时，可从 `NativeAdbAdmissionApi` 读取调用方命名的技术 scope，以旧 `scopeId` 比较接管，再把返回的 `AdbAdmissionScopeInfo` 传给 `NativeAdbClient(..., admissionScope: scope)`。首次创建要求没有旧 scope；接管撤销旧握手准入，等待实际 worker 与未交付 Client 释放后才换发权限。已确认交付的连接保留，可由新客户端精确认领；认领本身也属于同一 scope 的准入操作。旧 scope 的关闭不能影响后继，失败保留原 scope 供重试。scope 只保存技术权限，不保存产品连接策略、设备记录或自动重连意图；`AdbHost.prepare()` 不会自动选择这项调用方命名的恢复边界。

`AdbHost.prepare` 与 `AdbHost.restore` 可显式接收 `admissionScope`。原生登记在同一权限检查中预约服务器及关闭责任，接管先撤销旧命令和未交付握手，再等待实际退出；已确认服务器保留，由当前精确 lease 恢复。迟到创建、认领与确认不能越过 scope 接管。`NativeAdbClient(..., ownsAdmissionScope: false)` 借用外层 scope，仅释放本客户端拥有的资源；外层所有者负责最终关闭 scope。

`client.services.attachFileScope(ownerKey, admissionScope: scope)` 在原生层原子核验父权限并登记文件域。父域接管或关闭先撤销文件准入，再等待 worker、FD 和关闭帧排空；失败保留原登记供重试。旧 scope 的迟到附着和关闭不能撤销后继文件域。自定义适配器缺少 scoped 文件能力时明确失败，不回退为无权限约束的附着。

该 scope 的建连握手只用于移动直连、USB 与配对；官方 smart socket 建连使用其服务器所有者的握手权限，不能用移动 scope 绕过。精确认领既有 Client 是独立入口，可在 scope 内交接原生已登记的连接。

底层 Client 的取消通知与释放完成分别核验；断开成功前等待持有传输 socket、服务流及本机 reverse 桥的任务退出。超时保留精确连接或握手登记，再次关闭继续等待同一资源；它不证明远端进程或 reverse 映射已经删除。外部仍持有的流与 writer 必须按其接口释放，不能把仅设置 `closed` 标记当作资源已收尾。

官方桌面后端的 CLI 退出不能证明 adb-server 中的在途建连已经结束。发出建连命令后未取得完整成功回执，会返回 `official_connect_result_unknown`；`already connected` 还需同服务器、同目标的 `get-state` 确认为 `device`，否则仍为未知。定向断开请求也不能解除该未知状态。原生服务器登记保留该未知状态，拒绝全部后续新命令与握手；新客户端和新 isolate 也不能绕过。已交付的精确连接句柄仍可使用和释放。须关闭持有的原服务器并准备新宿主，不能仅新建客户端或换一个地址别名重试。未知状态下 `client.close()` 只确认本机命令、握手与已知连接的回收；定向断开失败保留记录并允许外层宿主继续终止服务器，不能把客户端关闭成功当作服务器在途任务已停止。

配对取消不表示撤销对端信任；如果已取得真实成功 GUID，就保留该结果，结束握手登记失败留给同一客户端的 `close()` 重试。对端写入可能先于本机失败或取消，调用方须先核验再决定是否重试。自定义 `NativeAdbApi` 适配器需同时实现 `NativeAdbHandshakeApi` 才能接受显式握手取消；不能实现时会在开始执行前明确拒绝。原生的 cancel 只发通知，close 才确认握手结束，失败保留原句柄的回收权。

连接与配对错误由各能力包的 FRB 适配器转为 `AdbException`，调用方按 `code` 判断，不解析异常文本。`connection_refused`、`host_unreachable`、`network_unreachable` 和 `connect_timeout` 表示建立 TCP 连接阶段的失败；`handshake_timeout` 表示连接已建立后的协议等待超时。单次操作共用期限，阶段切换不重新计时。配对写出身份后未取得完整结果返回 `pairing_result_unknown`，取消不能将其覆盖为普通取消；调用方不能据此自动重放配对。`adb_cleanup_unconfirmed` 保留本机资源释放未确认的事实及原所有者的重试责任，也不能视作可换地址重试的网络故障。官方 CLI 的 `official_connect_result_unknown` 仍遵循上文的服务器级恢复规则。

Close the host after device activity cleanup. `AdbHost` 的原生登记持有服务器进程所有权、专用启动 ACK 管道、CLI 与未交付握手；Dart 负责参数、私有 key home 和 CLI 输出解释。`nativeConfiguration` 是诊断与迁移事实，恢复必须在同一原生库的登记中匹配当前 lease，再比较并轮换控制权限；端点、PID 或磁盘配置不能授予关闭权。认领等待旧 CLI 和未交付握手退出，保留已交付连接与捕获；旧 lease 迟到关闭无害。未知状态跨认领保留，新 lease 只允许关闭原资源。关闭失败保留原进程所有权与租约供重试，确认实际退出后才删除本次私有 key home。Bundled artifact preparation is in `tool/prepare_adb.dart`. See [test setup](test/README.md) and [validation](VALIDATION.md).

Linux 原生进程通过嵌入的独立监督器保存真实目标 Child 与退出码，避免 Dart 的进程回收线程抢走状态。监督器只执行明确传入的参数和环境，不解释 ADB 输出；关闭先通知监督器终止并等待目标，再确认监督器退出。控制流断开会触发目标回收；监督器异常死亡且未收到目标退出回执时，保留清理未知，不能以监督器退出冒充目标已收尾。监督器自身使用启动时移交的 pidfd，不按 PID 回查或终止；需要支持 pidfd、可执行 memfd 及 `/proc/self/fd` 的宿主环境，不支持时在目标执行前失败。

监督器由 `rust/adb/api/build.rs` 使用目标工具链构建并嵌入能力库，没有单独的 Dart asset 或应用桥。Android 目标编译共享该实现，但移动后端不启动桌面官方 adb；交叉编译不代表 Android 策略允许执行 memfd。macOS 尚未完成同等的精确进程监督，Windows 使用原生进程句柄；平台编译与实际验收范围见[重构记录](../../docs/implementation/architecture-refactor-validation.md#进程监督与文件变更复核)。
