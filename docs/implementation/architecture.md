# 架构职责与资源所有权

本文维护必须遵守的依赖、资源所有权与恢复边界，不承担重构完成声明。当前变更与验证见[重构验收记录](code-and-build-refactor-validation.md)。领域用语见[词表](../../GLOSSARY.md)，架构取舍见[ADR](../adr/)，产品行为见[产品规格](../../designs/prod/README.md)。

## 依赖方向

Flutter 页面通过 `AppDependencies` 调用应用的业务模块；设备连接策略、偏好、文件任务、活动与呈现归 `app/`。`packages/` 仅承载通用设计系统、ADB、scrcpy 和媒体解码，公开参数与行为对应上游概念。应用通过类型化适配组合原生能力，产品命令契约归应用传输层，使用 `ApplicationCommand` 与 `ApplicationCommandException`；这些 Dart 命令不构成应用原生桥。媒体字节不进入 Dart JSON。

`ApplicationSession` 负责组装、准入和生命周期，不作为命令分派器的业务回调目标。`ApplicationBusinessCommands` 借用设备、观察与活动所有者执行聚合业务；`ApplicationCommandDispatcher` 借用文件、偏好和媒体缓存所有者完成传输适配。`PreferenceCommands`、`MediaArtifactCoordinator` 由组装层创建，媒体缓存任务由组装层按依赖顺序关闭。命令在任何准备、取消或文件副作用前完成统一校验；内部执行传递 `ApplicationCommand`，字符串入口只负责解析适配。参数与快照仍沿现有命令契约使用 Map，enum 不代表业务数据已经全面类型化。

`MediaCaptureOperations` 直接借用会话、音源与捕获能力，提供 ready、stop、presentation、source/status 等操作。本机输出调用此捕获接口，不经应用总路由重新返回 `ApplicationSession`；捕获与输出分别保留实际所有权。

`adb` 提供统一 ADB 调用与受控进程生命周期。公开 `AdbHost` 持有服务器、客户端及精确关闭权，实现位于 `packages/adb/lib/src/adb_host.dart`；`adb.dart` 只作为公共导出入口。Android/iOS 使用 `interop-adb`，桌面使用随包分发的官方 platform-tools，通过私有 adb-server 的 smart socket 执行；不接管用户已有的服务器。原生传输不定义产品重连策略。Dart `ConnectionPolicy` 区分产品编排与原生执行参数；重新附着读取存活传输的实际事实，不用新策略重新解释旧传输。`ConnectionSetupCoordinator` 编排配对、USB、转 IP 与取消，`ReconnectionCoordinator` 拥有自动重连计时和前后台决策。USB 离线后等待新的系统授权。

每个 ADB 客户端只有一份 `AdbServices` 操作登记；便捷 shell、push/pull 与显式服务入口使用同一会话及文件 scope 所有者。官方服务器客户端直接持有其 bindings，不嵌套额外的直连客户端。媒体解码器的控制器只借用原生控制地址，平台持有实际输出；销毁确认前保留平台句柄，失败后沿同一控制器重试。

`AdbHost.prepare/restore` 必须接收明确的 bindings，不隐式加载另一个原生库。独立使用 ADB 时先取得 `createNativeAdbApi()`；scrcpy 组合宿主传入同库实现。独立 ADB 的构建资产在 release 链接时按初始化入口可达性裁剪，不因 Dart 类型依赖而强制分发第二份 ADB/TLS/RSA/文件实现；没有可达性信息时保留资产。决定见 [0009](../adr/0009-native-composition-and-host-checks.md)。

直连执行通过 `AdbConnectOptions`、`AdbTcpOptions` 和 `AdbKeepaliveOptions` 传入握手、burst 和 socket 参数；类型归 `adb`，产品取值由 `ConnectionPolicy` 与当次偏好组合。SDK 不接收健康阈值、重连策略或整份应用配置。官方服务器拒绝显式直连选项，USB 不应用 TCP 字段；通用机制默认和输入限制见 [ADB 接口](../../packages/adb/README.md)。

握手准入在能力包内部登记，单次操作接收 `AdbCancellation`。需要跨 isolate 接管时，调用方另选稳定的技术 scope 名称，并按当前 scope 句柄比较接管；SDK 不在 scope 中保存产品策略或设备记录。接管先撤销旧准入，等待旧握手与未交付连接的本机清理，再交出新权限；已确认交付的连接保留，后续必须按原句柄认领。旧 scope 不能关闭后继 scope，清理失败保留同一所有者供重试。

原生取消信号与结束确认分别处理；关闭等待真实 worker，未完成的握手保留原句柄重试权，迟到连接不能越过应用准入或丢失清理所有者。连接交付前再次核对整个异步调用的准入。传输的取消通知不等于读写任务退出，成功释放必须核验本机 driver 与持有 socket／FD 的任务已经结束；调用方的等待超时不能丢弃资源完成登记。配对成功是对端已发生的事实，不被本机取消意图或登记清理错误抹掉；取消也不承诺撤销对端信任。

能力包将连接阶段、协议阶段、配对结果未知和清理未确认分别转换为公开 Dart 错误码，具体契约见 [ADB 接口](../../packages/adb/README.md)。应用只对明确的失败阶段选择后继候选，不解析 Rust 展示文本，也不把信任结果未知或清理未确认当作可重放配对的网络失败。

`DeviceDiscovery` 在应用 Dart 中使用 `multicast_dns` 查询配对、TLS 和普通 TCP 服务；结果有容量、TTL 与扫描代次限制。发现只提供候选，GUID 必须匹配已保存的真实配对事实，交付连接前仍须核验实际设备。配对端口不作为连接端口保存。二维码只匹配当次随机实例，密码仅交给实际配对调用；取得成功 GUID 后先记录信任，再处理取消或后续连接失败。清理失败与已知配对成功分别报告，不要求用户重放配对。

USB 枚举通过公开 `AdbTransportDiscovery` 返回物理路径等传输事实，不根据序列号外形猜测 USB。枚举或平台描述符中的序列号仅选择待核验记录，实际连接仍由 `DeviceProbe` 核对。Android 设置流程先取得 `NativeAdbConnectionAttempt`，失败后确认其精确握手和未交付连接释放，再关闭平台租约；成功后平台租约随 `DeviceConnection` 保持到 SDK 实际断开。临时专用身份在所有实际工作退出后，先由 `ApplicationHost.releaseIdentityClient` 关闭对应客户端，再删除临时密钥；关闭失败保留同一责任供重试。

Android 原始 USB 描述符由进程登记持有，授权与普通释放绑定创建时的平台权限。`ApplicationHost` 通过 `UsbLeaseRecovery` 先比较旧权限并封存授权和普通释放，再接管 SDK scope、排空旧握手、精确捕获与连接，最后确认平台原始描述符实际关闭并开放新权限。引擎重启只封存准入和撤销待定授权，不提前关闭已交付描述符；Activity 更替只回收未交付资源。SDK 对失效连接句柄的断开成功不能替代排空证明，也不能在封存期间换取平台释放成功。

恢复回执丢失时保留同一接管候选，关闭失败保留原条目和关闭权供重试；初始化失败的宿主也须完成这条顺序后才能退出。平台实例固定使用自身权限，旧回调不能采用后继权限释放资源。授权 UI 的取消仅按原权限和 attempt 精确匹配，无匹配时可确认取消；该确认不表示 SDK 或描述符已释放。平台原始资源的完成确认由宿主在 SDK 排空之后执行，普通取消不能绕过这一条件。

转 IP 借用当前精确连接，先由 `ConnectionOwner.retireForChange` 撤销准入并排空活动，再提交一次 `tcpip`。监听切换回执与后续 TCP 连接分别记录；原 SDK 连接及平台租约确认释放后才尝试重连，并核对原设备序列号。退休清理重试不重复提交监听切换，失败或取消不抹去已确认的切换事实。

官方 adb CLI 退出和服务器定向断开回执都不能确认服务器在途建连已排空。命令已发出但未取得完整成功回执时，SDK 返回 `official_connect_result_unknown` 并在原生服务器登记中保留未知状态，阻止全部后续命令及握手准入，避免地址别名绕过；已交付的精确句柄仍可使用和释放。恢复需由持有者终止原服务器并准备新宿主，不能只更换客户端。客户端关闭仅确认本机及已知精确资源，未知服务器任务由宿主关闭收敛；其定向断开失败不得阻止外层继续终止原服务器，精确握手或连接释放失败仍须保留重试并报告。

应用偏好模块拥有产品默认值、迁移、校验、revision 与 `preferences.json` 原子保存。仅在偏好文件不存在时只读迁移旧 `devices.json` 设置；损坏或较新格式保留原字节并失败。同一私有目录固定一个 isolate 所有者，revision 冲突由调用方重新确认。写入 flush 后原子替换，断电后的目录持久性未验证。应用把解析后的明确选项传给能力，不向 Rust 安装整份产品设置。应用先保存再应用；回执丢失保留 `saved=true/applied=unknown`，由显式核验恢复应用状态；提交本身无法确认时保留 saved=unknown，不盲目覆盖或回滚。`VideoQualityPolicy` 合并设备偏好，`DeviceQualityCoordinator` 串行保存、重建和逐窗结果，`VirtualDisplayPolicy` 计算等比虚拟尺寸。`DeviceCapabilityFactsReader` 从精确连接、授权身份及公开 SDK 读取有界事实，离线检查不建立连接或生成密钥；`DeviceCapabilityPolicy` 将这些事实解释为产品状态，未知不等于不支持。通用能力只验证当次协议请求的执行条件，不拥有产品支持矩阵。

Flutter 与业务组装位于 `app/`；该目录不承载 FRB、其生成代码或 Rust。`packages/` 隐藏绑定并只公开 Dart 能力接口，Rust 实现统一归同名的 `rust/adb/`、`rust/scrcpy/`、`rust/media_codec/`。通用层不包含产品状态、默认值、业务流程或聚合命令路由；容易用 Dart 或成熟包实现且没有性能压力的能力留在 Dart。`servers/` 保存被控执行产物；`protocol/` 是应用命令契约来源。Dart workspace 共用根锁文件和 `.dart_tool`，页面布局与路由规则见[导航契约](flutter-navigation.md)。

### 模块位置与接口

手写文件与主要类型按实际职责命名：设备记录值对象为 `DeviceRecord`，持久化所有者为 `DeviceRecordStore`；命令分派器、业务协调器和租约登记分别用 `Dispatcher`、`Coordinator`、`Registry` 表明职责。复数名可以表示数据集合，但不能掩盖持久化、任务编排或资源所有权。`MediaIntentRegistry` 登记并取消在途启动意图，`AudioOutputCoordinator` 和 `VideoOutputCoordinator` 管理本机输出的启动、状态协调及回收；文件名与主类型对应。`readAndReconcileMediaSnapshot` 明确表达读取状态同时回收失效输出；错误呈现位于 `presentation/remote_failure.dart`，画面坐标换算位于 `media/source_coordinates.dart`。目录限定的范围应覆盖文件职责；`FileCatalog`、`FileMutationCoordinator`、`TransferCoordinator` 分别位于 `files/catalog/`、`files/mutations/`、`files/transfers/`，独立拥有目录快照、文件变更与持久传输。`ApplicationSession` 直接组合这些所有者，`FileCommands` 仅解析和分发文件命令，不另设聚合文件所有者。`ControlPageRegistry` 登记页面租约，`ApplicationBackgroundCoordinator` 执行平台与音频策略的协调；本机和被控文件共用 `FileExecutor`，本机缓存准入使用 `FileCacheLeases`。应用命令分派位于 `application/application_command_dispatcher.dart`，平台事件适配位于 `application/events/application_platform_events.dart`；应用内请求契约为 `transport/application_request.dart`／`ApplicationRequest`，平台与系统交付调用应用命令时使用 `applicationRequest`，不暗示依赖 Rust 产品核心。文件浏览的排序、筛选和标签位于 `presentation/file_browser_presentation.dart`，系统通知交付与撤销由 `platform/system_notification_coordinator.dart` 持有。相关调用、测试文件和当前文档同步命名，不保留只为兼容旧名的别名或转发文件。

| 目录 | 责任与依赖 |
| --- | --- |
| `app/lib/application/` | 启动、依赖注入、不可变应用快照与查询失效；`transport/` 定义请求契约、JSON 读取和无状态命令适配，不依赖界面 |
| `app/lib/connection/` | `DeviceCoordinator` 组合记录、身份、探测与连接所有者；`DeviceDetailsReader` 查询同一实际连接的只读事实；配对、重连和能力校验分别编排 |
| `app/lib/companion/` | `CompanionClient` 负责部署与 RPC；`CompanionCoordinator` 复用精确连接的部署；`ObservationCoordinator` 拥有观察意图、事件代次及恢复策略 |
| `app/lib/files/` | 目录快照、文件变更、持久传输和文档交付分别拥有生命周期，由应用会话直接组合 |
| `app/lib/media/` | 捕获与输出组合、画质策略、页面与音源租约、输入、缓存租约及缩略图调度 |
| `app/lib/platform/` | 本机剪贴板、系统通知、诊断与系统入口的应用适配 |
| `app/lib/presentation/` | 文件列表排序、筛选、面包屑与标签等展示逻辑，以及依赖路由、对话框的页面动作 |
| `app/lib/pages/`、`router/`、`widgets/` | 业务页面、typed route 组装及共享界面；不成为应用编排层的依赖 |
| `packages/design_system/lib/src/` | 主题、辅助偏好、材质、采样几何、导航、控件和叠层分别成库；公共入口只导出组件契约，不通过 `part` 共享内部状态 |
| `app/lib/preferences/` | 产品默认值、迁移、校验、revision 与原子保存 |
| `app/lib/files/catalog/`、`mutations/`、`transfers/` | `FileCatalog` 拥有浏览与固定搜索/图库快照；`FileMutationCoordinator` 拥有文件变更批次；`TransferCoordinator` 拥有持久传输、恢复和缓存预留，`TransferJournal` 负责日志持久化 |
| `packages/adb/`、`packages/scrcpy/` | 公开类型化 Dart 能力，内部维护加载、FRB 适配及生成物；不公开产品 Runtime、设备记录或聚合业务命令 |
| `rust/adb/` | ADB 传输、认证、shell、sync 与流复用；不拥有产品设备记录或重连策略 |
| `packages/scrcpy/` | scrcpy 启动选项、控制、捕获与协议；接收明确连接和服务产物，不读取应用设置或页面状态 |
| `rust/media_codec/src/` | `packet` 拥有包存储、双重容量限制及按字节和包数限制的完整 GOP 历史；`backend` 拥有解码上下文、换纹理和硬软回退；`image` 拥有帧与像素转换；入口负责 ABI 与线程生命周期 |

页面摘要使用 `DeviceSummary`，可以呈现离线缓存；连接探测的 `DeviceFacts` 只表示当次实际查询结果。`DeviceAudioViewCoordinator` 持有页面声音租约，`DeviceAudioSourceCoordinator` 持有精确捕获，二者不互授资源关闭权。输出层的 `request` 调用应用命令，不能从命名或回调类型暗示应用依赖某个 Rust 产品核心。通用 scrcpy 客户端为 `ScrcpyClient`，捕获生命周期对象为 `ScrcpySession`；两者不包含 Flutter 界面职责。`ScrcpyOptions.logLevel` 是明确的服务端参数；应用的独立窗口需要 info 输出核验新显示编号，整机、音源和保持唤醒捕获显式选择 warn，通用层不根据显示参数推导这一产品选择。设备应用的图标读取位于 `phone_app_icon.dart`，打开方式选择与导航位于 `phone_app_launcher.dart`，调用方按所需职责导入。

能力事实读取器位于 `connection/device_capability_facts_reader.dart`，同文件保留其返回的事实类型；文件名说明它主动查询的职责。传输状态、导出资格、路径与标签的展示投影位于 `presentation/transfer_presentation.dart`。路由资源读取、失败重试与页面保留由 `router/route_resource_view.dart`／`RouteResourceView` 承载，不限定为设备记录。

通用包不反向依赖应用，也不通过自身公共导出入口读取内部基础类型。跨包仅导入公开接口，不访问另一包的 `src/`。`tool/check_architecture.dart` 核验 manifest 分层、实际 import/export、条件导入及手写模块依赖环；FRB/Riverpod 生成库由生成检查负责。typed router 是组装入口，仅到 `pages/` 与 `route_resource_view.dart` 的页面注册依赖不参与环检查，其余路由出边仍受核验，应用业务模块禁止依赖页面或路由的规则仍独立检查。

## 状态与资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| 应用 Dart 所有者 | 设备记录、授权身份选择、业务协调、命令分发、活动及快照栅栏；能力包只执行明确请求 |
| DeviceCoordinator / ConnectionOwner | 协调器组合设备业务和实际连接投影；所有者登记每设备准入代次、在途尝试及取消、可重试的旧资源清理；能力层只识别实际连接句柄 |
| DeviceDetailsReader / DeviceProbe | 设备只读分组查询及连接准入探测；共用有界文本查询与电池解析，读取后核对精确连接，不用缓存补齐动态事实 |
| DeviceCoordinator 重连租约 | 只有当前重连协调器可提交自动尝试；租约释放或替换取消其待定尝试，已交付连接继续由 ConnectionOwner 管理 |
| AppLaunchStore | 应用打开意图、持久副作用记录与防重准入；不拥有远端应用任务或捕获 |
| CompanionClient | 同一精确连接上的唯一部署、认证通道、请求对应和关闭权；失败保留资源及未确认状态供重试 |
| CompanionCoordinator / ObservationCoordinator | 前者复用同一连接的部署、分发功能 RPC；后者持久化 wanted、核对真实连接和观察 epoch，状态读取不部署，迟到列表不覆盖新事件 |
| SessionCoordinator / DeviceAudioSourceCoordinator | 前者拥有逻辑会话、精确捕获及有界质量交接资格；后者为同设备共用实际 PCM 来源，分别等待真实渲染和播放回执 |
| PhysicalDisplayRecovery | 已核验连接准入前的遗留显示恢复；固定原 owner、持久终态与精确本机流，失败保留重试 |
| PhysicalDisplayLease | 同一逻辑手机窗口及精确连接上的尺寸覆盖、在途调整、远端恢复证明与租约记录释放；不随画质捕获代次替换 |
| ScrcpyServerQueries / ScrcpyQueryProcess | 固定清单查询的上传与部署、精确监督流、真实退出证明和可重试收尾；不拥有窗口、连接或画质偏好 |
| 应用活动所有者 | 原子协调逻辑窗口与音源准入、代次核验及摘除；质量重建以绑定旧捕获的有界交接租约保留声音；异步执行与回收不占用登记事务 |
| DeviceKeepAwakeCoordinator | 同设备窗口共享的保持唤醒意图、精确控制捕获和失败重试；本机关闭与远端退出、恢复证明分别报告 |
| FileCatalog | 浏览、搜索与图库快照、扫描取消及目录事件 |
| FileMutationCoordinator | 新增、重命名与批量删除的准入、精确执行批次及可重试回收 |
| TransferCoordinator | 持久传输任务、冲突、取消、恢复、缓存预留与托管来源发布交接 |
| ShareCoordinator / ShareStore | 外部分享导入、授权交接、待处理批次及传输来源保留；产品账本只在应用 Dart |
| DocumentsCoordinator / DocumentSources | 前者规划系统文档复制及精确资源收尾；后者通过独立来源账本持有暂存内容、页面持有权和传输发布关系 |
| AdbFileExecutor | 适配通用文件事实查询、字节传输、原子提交与资源租约，保留精确执行回收责任；任务与预览预算归应用协调器，详见[文件所有权](file-ownership.md) |
| AppMediaCache / DeliveryJournal | 受管目录、字节预算、缓存租约与持久交付回执；准入、交付提交及删除遵守同一 gate → journal 顺序 |
| interop-adb writer | 普通/优先队列、单流顺序、ACK、burst credit 与有序关闭 |
| scrcpy MediaSource / media_codec PacketQueue | 捕获源的原生 sink 附着与分离、包所有权交付；解码端约束容量并保存完整 GOP 重放 |
| ApplicationSession | 组装 Dart 业务所有者、公开 SDK 宿主、本机输出与启动恢复；拥有组装资源的关闭次序，失败保留精确清理责任 |
| ApplicationBusinessCommands / ApplicationCommandDispatcher | 借用业务所有者进行执行和契约适配，不创建资源所有者或接管其关闭权 |
| MediaCaptureOperations | 直接适配精确捕获操作，借用会话、音源与 SDK，不依赖应用总分派器 |
| ApplicationEvents / StateRecovery | Dart 业务事件统一排队与水位、文件及平台订阅；观察者失败不影响其他投递，缺口恢复和瞬态通知分别处理 |
| ApplicationSnapshotReader | 借用各所有者的实际状态，按业务版本栅栏组合快照；不部署助手或启动捕获，保持唤醒证明不覆盖窗口捕获证明 |
| 应用偏好模块 | 偏好校验、迁移、冲突检测与原子持久化 |
| adb | 统一 ADB 调用、移动端适配与桌面私有官方服务器 |
| media_codec | 裁剪 FFmpeg 解码、帧与 PCM 输出、Flutter 组件 |
| AppController | 应用级不可变状态、可见页面焦点与能力协调；页面声音租约由 DeviceAudioViewCoordinator 持有 |
| DeviceAudioViewCoordinator | 按设备共享音源的页面租约、启动取消、停止去重与迟到回执清理；控制器只投影错误 |
| CommandQuery | 按主题与设备归属响应失效事件，串行合并在途查询；不为其他设备或无关功能的事件发起读取 |
| AppPresentationHost | 根界面的剪贴板、提醒、来电与分享呈现调度，帧回调持有独立取消身份 |
| RemoteWindow | 单窗口的页面与声音租约、会话释放及最后窗口锁屏顺序 |
| RemoteInputOwner | 单窗口的指针、持键、组合编辑、输入队列和绑定代际；页面只持焦点与控件 |
| RemotePresentation | 单窗口的会话绑定、输入许可、可见性、恢复与启动结果 |
| RemoteInputQueue | Dart 单页串行输入与每触点最新 move；Rust 负责有界录取、批写和失败撤销 |
| SessionViewRegistry / SessionViewLease | 窗口租约登记、可见性操作与精确关闭；旧租约不能操作后继窗口 |
| AudioOutputCoordinator / VideoOutputCoordinator | 本机播放器的启动、状态协调及释放；保留失败或超时的具体旧输出直到释放确认 |
| Android ProcessFlutterHost | 进程 FlutterEngine、Activity 与当下系统授权 |

同一 Client 上的流与设备连接分别拥有生命周期；活动、页面租约和播放器也不能互相代替。旧清理、旧回执和旧连接结果不得作用于新连接。`connectionId` 只标识当前存活连接，不持久化。同一官方客户端的端点占用按实际连接保留，撤销业务准入或修改设备记录不释放占用；只有精确断开确认后才允许另一记录使用该端点。

`ApplicationSession` 组装业务所有者，应用先决定逻辑窗口与活动归属，再以精确 ADB 句柄调用 scrcpy 的公开 Dart 能力。SDK 拥有实际捕获及其取消、控制、媒体源与清理，应用保存逻辑 `sessionId` 到捕获引用的对应；不在 Rust 登记平行的产品活动。观察者只释放订阅，不取得捕获停止权。媒体与控制消息保留捕获身份，renderer generation 仅标识该捕获内的输出。ADB 与 scrcpy 需要共用连接时使用配套宿主，不把独立动态库的句柄相互传递。

`ScrcpySession` 分别保存捕获和各观察者的释放确认；其中一项失败不能撤销另一项已经确认的释放。重试关闭仅处理未完成项，不能用已经移除登记的捕获句柄再次停止，也不因观察者失败跳过捕获停止。

异步远端执行不持有活动登记事务或状态读写锁。停止先撤销原所有者的准入，再等待状态投影和资源回收。能力层核对原连接、捕获或执行句柄；应用核对业务代次、身份选择和仍有效的用户意图。

Dart isolate 重启后，先核验仍存活的技术资源，再重建应用业务状态。通用宿主登记只能包含实际服务器、连接、捕获与操作的资源身份和执行事实，不保存产品设备标识、整份 `ConnectionPolicy` 或设备记录。官方 ADB 宿主登记持有实际进程所有权与专用启动 ACK，Dart 保留参数构造、密钥目录和输出解释；跨 isolate 的原生资源所有权是这部分生命周期位于 Rust 的原因。恢复按登记中的当前 lease 比较并轮换权限，匹配不可变启动事实；PID、端点和磁盘配置不能授予关闭权。交接先排空旧 CLI 和未交付握手，保留已交付连接与捕获；旧 lease 关闭无害，未知结果跨交接保留，新 lease 只允许关闭。恢复不生成新密钥或启动替代服务器；关闭失败保留同资源重试权。恢复连接必须接管原句柄，重新按序列号建立 Client 不算恢复。无法核验或匹配不唯一时保留未知，不自动启动画面或声音。

Linux 官方 ADB 的目标 Child 与退出码由独立监督器持有，避免嵌入宿主的进程回收线程抢走状态。原生登记先撤销准入并回收目标，再等待监督器退出；缺少目标退出回执时保留清理未知，监督器退出不能代替目标退出。监督器的终止与退出核验使用启动时移交的 pidfd，不按复用 PID 发送信号。该机制不定义 ADB 命令含义或业务策略；目标工具链构建、嵌入及平台范围见[工具链契约](repository-tooling.md#原生媒体与官方-adb)。

原生连接认领轮换操作与关闭句柄，底层 Client 身份和连接登记身份保持不变。普通服务、文件操作与新捕获共用可撤销准入，已有捕获继承连接 lifetime。认领撤销三类新准入，排空旧服务与文件操作并保留已有捕获；断开新句柄才撤销连接 lifetime。旧句柄不得在交接后关闭或登记后继资源。认领失败保留旧句柄重试权及已撤销准入；借用连接不能被接管。连接事实中的底层身份、代理端点和 transport ID 只是执行事实，不证明设备身份或官方服务器进程归属，也不能代替在途握手与服务器任务的独立收敛。`admissionScopeKey` 只报告最近一次确认交付的技术域；未确认认领不改变它，同一物理 Client 的独立借用不继承它，也不能仅凭它取得关闭权限。`serverId` 仅报告实际拥有的原生服务器关联；连接与捕获继承其运行 lifetime，不继承可轮换的控制 lease。

重新认领连接后，应用可按当前连接句柄排空该底层连接既有的 scrcpy 捕获。排空在登记短锁内固定捕获集合并撤销这些捕获，随后在锁外等待实际清理；等待期间新增捕获不归旧排空操作所有。清理失败保留精确捕获及重试权，不关闭共享 ADB Client，也不影响另一个独立登记的连接。应用完成旧捕获排空后再重建逻辑活动，不能用丢失 Dart 对象或清空列表代替资源退出。桌面与移动宿主都认领并排空旧代已交付连接；桌面筛选还须匹配已成功认领的实际服务器 `serverId`。旧连接先排空捕获，再完成物理显示恢复与本机流释放，最后断开；任一步失败保留同一连接及其依赖的服务器，沿原对象重试。

scrcpy 启动先保存清理责任，再通过 START→PID→RUN 交付运行授权。原生监督任务独立持有双向流，启动请求取消或日志消费者释放后仍发送 STOP 并有界等待本次唯一 DONE；该回执在监督器等待原任务退出后发出。丢失 DONE 时按原 PID 与内核启动时间核验退出；启动可能已交付且身份也未知时保留原捕获，禁止删除 JAR 冒充回收。关闭顺序为本机任务收敛、远端主进程退出证明、关闭帧写出屏障、部署文件移除。旧 shell 缺少退出码时，文件移除还须核验本次完整成功标记，EOF 不作为删除成功。主进程退出不证明上游 CleanUp 子进程结束或设置恢复，应用不得据此发布恢复完成。

物理显示覆盖由应用 Dart 的 `PhysicalDisplayLease` 持有，通过公开 ADB 双向执行原语运行应用私有监督脚本；不增加 Rust 显示业务或应用桥。START 后先保存原覆盖与精确监督身份，Dart 收到 OWNER 后才发送 RUN 允许首个修改。调整带单调请求序号，修改意图先于实际 `wm` 调用登记；关闭先封存新调整、等捕获与已受理 worker 退出，再按原 owner 恢复并读回。当前值与已确认覆盖不同且没有未知修改时保留外部变更；未确认修改产生无法归属的值时保留 unknown，不能把系统改写请求值当作外部修改完成。恢复证明在设备端持久保存，Dart 接收后才 ACK 清理；断流和本机 exec 关闭不代替该证明。后继窗口只能在原租约恢复确认后取得物理显示，匿名或无法核验的记录不猜测接管。长启动、恢复与 ACK 程序均由短 bootstrap 经标准输入传递，兼容旧 adbd 的 OPEN 负载限制。同一流的脚本与授权写入串行化；短命令同时要求完整回执、真实事件终态和精确本机流释放，后到 DONE 不掩盖协议或关闭错误。

`PhysicalDisplayRecovery` 在当前 gate 内发现持久 owner；Dart 先固定 owner，才在原流授权恢复，收到 DONE 后另发同 owner 的 ACK。发现或恢复失败不能改为操作后继 owner。所有新连接均在身份核验、原连接活动退休之后、业务交付之前通过此恢复阶段，原比例窗口同样不能绕过。若原生事实确认同一精确连接已经 closed，且捕获已排空，只排空本机显示流，不发恢复或 ACK、不宣称远端恢复；远端 current 留待下一条已核验连接处理。未知连接状态不能使用此延期路径。

固定 scrcpy 编码器与应用清单查询使用独立的 `ScrcpyQueryProcess`。START 前不创建查询子进程；收到停止态 PID 与内核启动时间后才发送 RUN。取消经原监督流发送 STOP，由仍持有原 job 的监督器终止并等待该子进程，再发本次完整 END；输出超限不阻止读取监督终态。流丢失后的精确进程检查只读等待退出，不在检查后按裸 PID 发送信号。子进程退出及本机流释放均确认后才能删除 JAR；失败保留同一部署与进程责任重试，START 可能交付且身份与终态均未知时继续阻止清理。

伴生服务关闭先通过原认证通道确认媒体子进程已回收。有效失败回执保留原通道供重试；通道失效仍独立核验精确主进程，但主进程退出不能证明媒体子进程已回收。子进程未确认时保留部署输入，不删除仍可能被使用的 JAR。

窗口最后一个音频所有者撤销时，在同一登记事务内撤销音源；质量重建的交接租约受原窗口与捕获身份约束，成功、失败、请求取消、设备停止或期限到达都会释放。音频启动上传沿用音源取消令牌，远端临时文件清理等待本机上传结束和关闭发送排序；官方 ADB 的 socket 关闭、协议关闭帧写出与远端服务退出不是同一回执，清理失败保留未核验状态。

分享接收的 `ShareCoordinator` 使用独立于文档交付的稳定复制 scope，`ShareStore` 是分享批次及发布租约的唯一写入者。`DocumentSources` 在独立根目录复用同一账本实现，文档与分享各自保留来源所有权，组合接口只路由发布交接和引用核对。已交接给传输的来源只有完整引用核对才能回收，未知提交不重放；分享格式、授权交接及持久性边界见[内容交付](content-delivery.md#外部分享接收与传输来源)。

`TransferCoordinator` 为每个传输批次保存一份运行状态，统一持有设备归属、准备请求、worker、当前执行任务、缓存租约及编辑准入。任务日志负责持久历史，不能作为在途 worker 的唯一索引；删除最后一条终态记录后，设备停止仍须等待该设备的批次收尾。识别托管来源归属的异步查询也先登记为准备责任，设备停止或关闭须撤销并等待其退出；迟到查询结果不能重新发布任务。单项取消只撤销同一任务的执行令牌。准备租约在首条持久提交后才交给批次，释放失败保留原责任；所有运行字段退出后才删除批次登记。

目录传输在入队前共同计算已选与待处理条目，限制为 10,000 项、64 层及源与目标路径合计 16 MiB；枚举只请求剩余额度，不能先展开整棵目录树再检查总量。托管来源回收先固定当次来源覆盖集合，再等待持久写入队列稳定，从完整任务历史筛出引用这些来源的批次；无关历史不占来源证明预算，同批次所有消费者仍共同决定终态。目录来源覆盖其后代文件，覆盖集合以外的新来源不被推断为无人使用。失败、未知或未持久确认的消费者继续保留来源。

## 连接与屏幕

`DeviceHealthCoordinator` 在应用中按 `ConnectionPolicy` 解释入站活动及公开 OPEN 探针事实；`DeviceCoordinator` 负责精确连接退休和持久离线投影。通用包不保存产品健康阈值或重连状态，事实层级与失败处理见[连接健康](connection-health.md)。

连接快照由应用所有者按统一 Dart 事件水位发布，不为本地业务更新伪造原生序号。`ApplicationSnapshotReader` 在读取前后核验业务版本；等待资源读取期间发生分享、传输、窗口或设置变化时重新读取，避免旧快照覆盖新终态。高频媒体帧推进事件序号但不推进业务版本，避免持续帧使状态读取饥饿。分享消费使用精确的 `share.consumed` 事件，不代表全局状态缺口。连接、断开、重连和重新附着都不触发屏幕动作。每个明确新建的远控窗口至多尝试一次唤醒；`ControlPageRegistry` 在 `media/` 登记同设备整机与独立窗口的页面租约，旧页面释放不能摘除后继租约；调用方只有主动关闭最后窗口才按偏好锁屏。后台、遮挡、短断线和重新附着不触发唤醒或锁屏。

保持唤醒独立于点亮/锁屏，使用固定 scrcpy 的 control-only 服务。最后窗口关闭、偏好禁用或断线时取消该设备服务；回收必须核对原连接以及 PID、starttime 和 nice-name。没有打开窗口时，保持连接不产生页面或声音租约。

明确唤醒由 `DevicePowerCoordinator` 在原精确连接上发送一次固定 `KEYCODE_WAKEUP`。发送前按协商能力选定 shell_v2 或旧 shell；旧 shell 需当次随机回执、真实退出状态和完整 EOF。退出成功只证明命令完成，屏幕是否已亮、是否解锁仍为未知；超时或回执缺失不自动重放。应用版本由 `package_info_plus` 读取实际安装包元数据，不在产品常量或 Rust 中维护另一份版本。

应用持有默认全局授权身份和设备专属身份的选择及对应关系；能力层提供密钥校验、指纹及私密原子安装。替换身份只失效使用该身份的连接、活动与在途准入；私钥不进入普通设置、快照或事件。桌面不同身份使用独立官方服务器的 key home；同一服务器不能通过替换磁盘文件伪装成身份已切换。候选配置在同一目标握手与身份核验成功前不替换原端点。

应用通过协议能力有界查询可选设备数据并记录采集时间。结果只更新同一存活连接；离线或过期数据不冒充实时值。电量、充电和未知状态分别判断。

## 恢复、持久化与媒体

应用文件模块以版本化、连续序号的任务日志保存传输，串行刷新后才进入下一执行阶段；压缩时先刷新临时文件，再原子替换。旧 Rust 检查点和 journal 只作为迁移输入，成功迁移前不删除。损坏、截断或代际倒退拒绝猜测恢复。`finalizing` 与取消未确认的任务在重启后保留 `result_unknown`，未知写入不自动重放。原生执行层仅提供事实、字节 I/O、原子提交和租约，不再拥有平行任务状态。ADB 的便捷文件上传、下载与显式 SYNC 调用共用 `adb_sync`，不再暴露独立的 `adb_transfer` worker；独立 ADB 库与 scrcpy 组合库使用同一执行契约。

系统文档操作由应用 `DocumentsCoordinator` 及 `DocumentLimits` 规划，独立的通用 `LocalFiles` scope 限定本机路径和描述符资源，不依赖 ADB 连接。复制句柄持有实际源与未发布片段，提交使用原片段身份；取消及关闭先排空复制，再释放平台原始描述符。范围关闭失败保留同一所有者重试，发布结果未知不重试或自动清理。通用层不保存 URI、系统交付账本、产品预算或文档命令。

平台授予的文档暂存及截图库根在使用前固定为同一实际路径，账本与复制使用该根；传入的逻辑路径仅在这些根内按相对路径映射，业务来源与持久交付身份不改变。scope 的恢复名称仍沿用最初平台逻辑路径，二次核验环境不改变它。路径别名不授予共同父目录，也不允许请求访问根内的符号链接或通过父目录穿越。

文档暂存由 `DocumentSources` 在应用内统一计费，默认总预算 8 GiB；单次复制同时受剩余总预算和本次操作预算约束，不能每次导入重新获得完整额度。已知大小的文件在复制前还核对本机剩余空间，保留 32 MiB。旧版没有账本的文档目录继续计入总量，无法完整核验时拒绝新增，不因缺少登记就删除或视为免费空间。

文档复制完成后，页面持有权保存在来源账本中；页面替换结果、关闭或收到迟到结果时归还持有权，清理失败保留原来源供恢复。等待旧来源归还后，再核验页面和操作仍有效才能打开选择器；迟到归还失败保留来源身份及错误。提交传输先分配实际批次身份并绑定持久发布租约，再用同一身份规划和提交任务；不能按同路径的旧完成历史认领新提交。旧版没有批次身份的未知租约继续保护来源。本次取消的未发布证明只核对本次批次，页面归还不解除发布中、未知或已绑定任务的租约。启动先排空旧复制 scope 和平台资源，再归还不可能跨进程存活的页面持有权；传输来源仍按覆盖证明核对后回收，不能按目录年龄或页面消失直接删除。

Android 文档与外部分享资源登记属于进程，Activity 仅持有当前平台附着。Activity 销毁撤销附着和准入，原始 PFD 与迟到返回的描述符仍归同一登记；新 Activity 或 isolate 先确认原生复制排空，再认领并关闭旧平台资源。保留 Dart engine 的 Activity 重建也须经过该栅栏，不以应用 Session 没有重建为由跳过。精确旧操作的关闭不能释放新代次的资源，失败保留同一所有者供重试；进程退出是独立边界。

画面质量重建保留逻辑 `sessionId` 和真实应用 task，只替换捕获进程与虚拟 display。`captureGeneration` 标识捕获所有者，renderer generation 标识同捕获内输出；旧 generation 的迟到 ready、输入和尺寸结果必须失效。重建期间撤销旧输入绑定，只允许释放按键、指针和明确关闭。

画质交接先封存尺寸准入并等待已受理调整落定，再固定可回滚的窗口快照；不能用旧快照覆盖迟到的尺寸事实。物理租约和创建时的 `displayAuto` 随逻辑窗口保持，`displaySize` 仅投影已确认的尺寸；偏好变化不改写既有窗口的创建模式。

当前官方 scrcpy JAR 不提供协作捕获暂停。页面暂停保留会话并停止本地呈现，`capturePaused=false`，恢复通过 `RESET_VIDEO` 取得新画面。旧扩展 JAR 的暂停回执不适用于此路径。

后台由 `ApplicationBackgroundCoordinator` 在应用进入时按偏好请求。Android 连接 FGS 与音频播放 FGS 分别拥有通知和资源；没有画面不停止连接服务。系统 Task Manager stop 持久化为停止状态，只有用户明确操作才能重新准入，后台恢复不自动创建画面或声音。

连接通知的停止动作进入应用 Dart，同时撤销设置流程和实际连接准入，等待精确活动、SDK 连接及平台租约依次释放。设备停止意图与重连技术租约分别维护：换发租约不清除停止意图；用户明确恢复后，后续掉线可以使用新租约重连。实际连接成功事件仅结束重连协调器本次等待，不向仍在返回途中的成功尝试再次发送取消。设备活动的关闭责任按原 `DeviceConnection` 保留至排空成功，不能因界面快照已撤去连接而丢失。

## 契约与生成

`protocol/commands.json` 定义应用命令、字段形状和核验策略，产品聚合命令归应用，不进入通用 Rust API。能力包独立的类型化 FRB 契约封装实际协议及原生执行事实，配置位于工作区顶层，生成物归对应能力包。新增活动通过应用活动投影和停止，新增远控转换通过 `RemotePresentation`，页面不另建平行状态。

`TransportKind` 在保存、导出和恢复中区分 tcp、wireless、tls、usb。TLS 授权拒绝保留结构化错误，产品策略不解析展示文本。生成文件与来源一并维护，修改来源后重新生成。

应用媒体模块负责会话呈现规则，`media_codec` 负责解码与平台输出。Rust scrcpy 读取器通过有界 packet-source ABI 交出原始压缩包，Rust 媒体核心直接调用裁剪 FFmpeg；没有 Matroska 封装或 HTTP 中转。scrcpy 按服务端协议解析尺寸，不代替解码器限制输入；`media_codec` 在创建、两版来源 ABI 与像素转换入口统一核验自身单边 16384 的资源上限。音视频启动参数与首通道元数据统一由 `Options` 和 `Session` 处理，音频读取器只解释编码标识及 PCM 包。Dart 只持有控制、状态和 Flutter Texture。FFmpeg 只包含远控视频解码、必要 parser/bitstream filter、像素转换与平台硬解接口；AV1 以静态 libdav1d 提供软件回退。声音协商为 PCM，直接进入平台输出。

来源查询只借用捕获描述，不创建可独立关闭的中转。播放器通过原生 ABI 附着和分离来源；应用不发送虚假的 `media.close`，停止捕获仍归原捕获所有者。输出从可见快照移除后，音视频协调器继续保留具体播放器、设备和代际的清理责任；等待超时只结束调用方本次等待，真实操作留在登记内。否定回执或实际失败允许重试，销毁确认与观察取消分别记录，已确认播放器不重复释放。设备断开及全局关闭核对这些旧输出，未确认时失败并保留重试权；旧输出也计入数量上限。

Android 使用 MediaCodec，Windows 使用 D3D11VA，Linux 使用 VAAPI/NVDEC，Apple 使用 VideoToolbox；实际后端、硬件帧和回退由运行状态报告。平台接口可用不代表特定设备已验证，MediaCodec 名称也不能单独证明物理硬解。压缩包的所有权交接与解码后 GPU 帧的共享分别核验，不把整条链路概称为零拷贝。选择理由见 [ADR 0007](../adr/0007-capability-packages-and-native-media.md)。

媒体 source ABI v2 移交含解码 padding 的独占包存储，通过容量通知恢复背压生产者；旧借用 ABI 保留兼容复制。解码完成、平台纹理准备和 Flutter 最终显示分别取证，启动不强制 GPU 回读。PCM 以设备已播/排队水位调节采样漂移，部分写入保留尾部，暂停和输出释放由音频 worker 串行执行。

### 本机运行日志

应用进程持有唯一 `DiagnosticLog`，bootstrap 将其注入应用协调器与音视频输出；provider 重建和启动重试沿用同一写入队列。结构化 `DiagnosticReporter` 只转写命令标识、错误码、耗时、代际、释放回执与解码后端等白名单字段，设备和会话标识经每进程随机盐散列；不重定向原生自由文本日志，也不保存参数、异常正文或堆栈。设置页读取最近记录并手动导出 JSONL。

日志位于应用支持目录 `diagnostics/`，四份文件各至多 512 KiB，内存最近 300 条、待写队列 256 条，溢出记录丢弃数量。文件 IO 串行，正常批次延迟至多约 250 ms 发起写入，错误与退出前台主动请求 flush；崩溃或系统强杀仍可能损失未落盘记录。重启跳过损坏行并截断当前文件的不完整尾行，存储失败保留有界内存记录且不阻断播放。产品行为见[设置与本地数据](../../designs/prod/information-architecture.md#设置与本地数据)。

## 材质启动与渲染

`app/lib/main.dart` 先创建进程级 `DiagnosticLog`，再初始化 `GlassMaterial` 并启动 `bootstrapApplication`。支持 shader 时使用 premium 光学路径，不支持时使用明确的磨砂回退；降低透明度、高对比或实体偏好移除光学与模糊，减少动态效果关闭弹性位移。

页面直接使用库的 `GlassIconButton`、`GlassTabBar.bottom` 和 `GlassMenu`。浅色 premium 底栏由 `NavigationSelectionLens` 组合 regular 轨道、静止镜片和官方前景栏；暗色、辅助偏好与不支持 premium 的分支保留官方轨道和选中面。该组合依赖锁定版本的零光学快速路径，升级库时需重新核对。

普通材料通过局部 `GlassSurfaceGroup` 共享背景采样，不跨 Navigator。固定设置行使用实体 `ContentPanel`/`SettingsGroup`，动态文件、通知和任务列表保持开放内容流。`PageFrame` 把页头和底栏延伸到透明背景之上，滚动内容通过 `PageChromePadding` 消费避让；对话框、抽屉、菜单和提示统一经设计系统入口创建。

## 平台交付边界

仓库不配置自动 CI/CD。`tool/check.sh` 执行主机检查，`tool/check.sh --android` 额外构建并核验指定单 ABI 调试 APK；三 ABI 发布验证使用 `tool/android.dart build`，`tool/build_host.dart` 手动构建对应宿主。整包编译、协议夹具、模拟器和物理设备运行是不同证据，详见[验收记录](validation.md)。
