# Android 系统保存：提供方描述符、流与结果确认

研究日期：2026-10-17（Asia/Shanghai）。本报告只做文档与源码核查，没有运行 Android fixture、构建或设备验收。产品目标是通过 Android 系统保存文件，保护已有内容，保留未确认的结果，并把树规划、复制、配额与结果语义留在共享层。

## 结论与实施边界

**当前最小安全交付可以保留 `rw`、空普通文件检查、`lseek(0)` 和 `fsync`，把支持范围明确为“提供可核验的空、可定位、可同步文件描述符的文档提供方”。** 这是有效的真实系统保存实现，并不覆盖 Android 允许的全部提供方。遇到只支持 `w` 的提供方应明确显示不支持及保留本机内容，不能自动改用 `w`。需要补齐的是提供方错误检查、失败/取消信号，以及结果和目标 URI 的持有；不能把单纯 `close()` 返回当作远端提交确认。

**尤其不能把 `ACTION_CREATE_DOCUMENT` 返回值直接标成“由本次操作新建，可安全截断”。** 官方入门页称它不会覆盖同名文件，但 Android 17 固定源码仍有用户选择已有文件、确认后直接返回其原 URI 的路径。`w` 打开本身就可能截断，事后 `fstat` 或元数据检查来不及保护旧内容。下面记录这一文档与实现差异。

如果产品明确要求支持 `w` 管道提供方，应另加“本次调用 `createDocument` 得到新文档”的流输出能力，并接受比 `fsync` 文件输出更弱的完成证据；需要强一些的可见内容确认时，关闭后用 `r` 有界回读并比较内容。可靠管道提供错误传递机制，proxy FD 提供可定位 I/O；两者都不能凭空赋予外部提供方原子创建、覆盖保护或云端提交 ACK。

## 证据基线

Android Developers API 页面为 2026-10-17 在线版本，下面同时使用固定 AOSP `android-17.0.0_r1`，避免把可变分支当成版本证据：

| 源码仓库 | 固定提交 | 用途 |
| --- | --- | --- |
| `platform/frameworks/base` | [`94b4c163b7dfe5ce3607f7bb8456f9573f7de57d`](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/) | ContentResolver、DocumentsProvider、ParcelFileDescriptor、模式翻译、proxy FD |
| `platform/packages/apps/DocumentsUI` | [`4568ed0bc0a62f71d4126503ef92a91f42a22c4e`](https://android.googlesource.com/platform/packages/apps/DocumentsUI/+/4568ed0bc0a62f71d4126503ef92a91f42a22c4e/) | 系统保存对已有文件的实际处理 |

另外对照 Android 16 `android-16.0.0_r1`：frameworks/base 为 `99b01a65cc4c104933788b3143285ab6bae65827`，DocumentsUI 为 `b0f64324499a3f65aca817d3f221c716d953a800`。下面关键结果一致；Android 17 的 `FileUtils` 改为枚举模式字符串，没有给 ContentResolver 增加一个通用“不可截断的流”请求。

本仓库源码核查基于工作区、HEAD `b9bfe2a9a898738b33c85445aefda4f252104c91`；以下行号直接从源码检索，后续实施可能移动：

| 位置 | 当前行为 |
| --- | --- |
| `packages/interop_bridge/lib/src/documents/documents_coordinator.dart:661`，`_writeFile` | 查询同一 document ID、非目录/虚拟文档、已知大小必须为零、具备写能力，然后用 `rw` |
| 同文件 `:346`，`_copy` | `document.copy` 后才释放 lease；复制成功而释放报错时返回 `result_unknown`，不重试、不删除目标 |
| `apps/connect/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/PlatformDocuments.kt:110` | 只允许 `r`、`rw`，保留 PFD 所有权，向 Rust 借出整数 FD |
| 同文件 `:66`、`:229` | `releaseFd` 仅 `close()`；取消也仅 `close()`；没有 `checkError()` 或 `closeWithError()` |
| `crates/interop_core/src/documents/mod.rs:432` | `fstat` 要求目标为大小零的普通文件，然后 `lseek(0)`；`:499` 要求 `fsync` 成功 |
| 同文件 `:211` | Rust 对借用 FD 做 `F_DUPFD_CLOEXEC`，设置非阻塞；原 PFD 应在复制真正结束后才关闭 |

此方案与 [ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md) 的 Flutter/共享 Rust 主体、薄平台能力适配相容；与 [ADR 0006](../adr/0006-controller-without-debugging.md) 的主控普通应用权限约束相容。下面不提出主控调试授权、提供方白名单特权或新的常驻业务服务。

## 模式与 FD 类型的真实契约

[ContentResolver.openFileDescriptor](https://developer.android.com/reference/android/content/ContentResolver#openFileDescriptor(android.net.Uri,%20java.lang.String,%20android.os.CancellationSignal)) 明确：独占 `r`/`w` 可以返回 pipe 或 socket；`rw` 表示可 seek 的文件语义。`w` 是否截断取决于提供方。`openOutputStream(uri)` 默认也是 `w`，不能绕过此问题。

[DocumentsProvider.openDocument](https://developer.android.com/reference/android/provider/DocumentsProvider#openDocument(java.lang.String,%20java.lang.String,%20android.os.CancellationSignal)) 对提供方给出相同约束，并允许不支持该 mode 时抛 `UnsupportedOperationException`；声明可写不等于支持 `rw`。官方建议返回可靠 PFD 以观察调用方完成，不代表所有提供方实际上都使用可靠描述符。固定源码见 [DocumentsProvider.java:857](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/provider/DocumentsProvider.java#857)。

| 请求或检查 | 能证明什么 | 不能证明什么 |
| --- | --- | --- |
| `rw` | 向符合契约的提供方要求随机访问 | 所有可写提供方均支持；远端服务器已提交 |
| `w` | 给提供方单向流输出的自由 | 不截断；目标为空；返回普通文件 |
| `wt` / `rwt` | 明确请求截断 | 符合保护旧内容的保存语义 |
| `wa` | 请求追加 | 空目标或完整替换；不能拿追加模式实现新文件安全检查 |
| `fstat` 普通文件且大小零 | 此 FD 在检查时是空普通文件 | URI 一定新建；无其他写者；普通文件一定是物理本地盘 |
| `lseek(0)` | 此 FD 当前接受定位 | 全部 I/O、同步和最终提交均成功 |
| `fsync` 成功 | 该 FD 的同步请求成功返回 | 外部提供方另行上传已完成；其它云端副本已同步 |

“正常磁盘文件”的 API 措辞应按可观察能力理解，不能用来排除所有虚拟后端。API 26 起 [StorageManager.openProxyFileDescriptor](https://developer.android.com/reference/android/os/storage/StorageManager#openProxyFileDescriptor(int,%20android.os.ProxyFileDescriptorCallback,%20android.os.Handler)) 能为网络、云端等后端提供可 seek FD；实际 `fstat`/`lseek`/`fsync` 是否满足本项目约束，需要 fixture 验证。

固定 Android 17 [FileUtils.java:1540](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/FileUtils.java#1540) 把 `w` 翻译为 `O_WRONLY|O_CREAT`、`rw` 为 `O_RDWR|O_CREAT`，只有带 `t` 才加 `O_TRUNC`。这是使用 Android 标准解析器的实现行为，**不能覆盖 ContentResolver 明示的提供方差异**。调用者不能通过 ContentResolver 的字符串 mode 传 `O_EXCL`，也没有额外的标准模式同时承诺“任意提供方单向流、禁止截断、排他新建”。直接使用本地 `ParcelFileDescriptor.MODE_WRITE_ONLY` 并不能改变一个外部 DocumentsProvider 如何解释 `w`。

因此，“rw 必须可 seek”有官方契约依据；“所有系统文档 FD 必须是普通文件”“合法提供方必须支持 rw”“fsync 不支持就是平台 bug”都没有依据。当前 Rust 条件属于本项目安全兼容级别。

## 系统保存 URI 不等于排他新建凭证

[官方 SAF 入门页](https://developer.android.com/training/data-storage/shared/documents-files#create-file) 表述 `ACTION_CREATE_DOCUMENT` 不覆盖已有文件，同名时增加编号。但是固定 Android 17 的 [ActionHandler.java:528](https://android.googlesource.com/platform/packages/apps/DocumentsUI/+/4568ed0bc0a62f71d4126503ef92a91f42a22c4e/src/com/android/documentsui/picker/ActionHandler.java#528) 在 `ACTION_CREATE` 下存在 `saveDocument(replaceTarget)`：确认后返回原 document URI；[ConfirmFragment.java:70](https://android.googlesource.com/platform/packages/apps/DocumentsUI/+/4568ed0bc0a62f71d4126503ef92a91f42a22c4e/src/com/android/documentsui/picker/ConfirmFragment.java#70) 的确认按钮直接 `finishPicking(mTarget.getDocumentUri())`。返回 Intent 没有一个标准字段让接收方区分“刚新建”与“用户选择了替换目标”。这是实际源码反例，不能仅依赖入门页推断新建属性。

工程含义：

- 单文件 picker 返回 URI 后，保留 `rw` 的非截断打开及 FD 空文件检查；拒绝非空目标，提示选新名称。即使用户在系统界面点击替换，当前产品也无需承诺原子覆盖。
- 先查询 `COLUMN_SIZE == 0` 再以 `w` 打开仍有检查/打开间竞态；未知大小也不是零。打开时就可能截断，不能靠 Rust 收到 FD 后再发现非空来保护旧内容。
- 仅依据 mode 名称、URI 新出现、随机建议文件名、系统 picker 成功、元数据大小零，都不能建立排他新建证明。

真正较强的新建来源是本次对已授权父目录调用 [DocumentsProvider.createDocument](https://developer.android.com/reference/android/provider/DocumentsProvider#createDocument(java.lang.String,%20java.lang.String,%20java.lang.String))：契约要求创建新文档并分配新的稳定 document ID，提供方可以调整显示名称。固定 [DocumentsProvider.java:252](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/provider/DocumentsProvider.java#252) 可核查。应在原生 operation 的 handle 元数据中记录 `createdByThisOperation`，禁止 Dart 任意布尔参数把导入、历史 URI 或 picker 返回值升级成此权限。

这仍是符合契约的提供方模型，不是与恶意提供方或其它并发写者之间的系统事务。现有树导出 `_create` 对已有 ID、名称/类型变化、同名竞争的拒绝有防御价值；若收到复用旧 ID 就必须在打开写流前拒绝。不能把 `createDocument` 异常自动当“肯定没创建”，否则重试会制造未知副本。

## close、可靠错误通道与提交确认

[PFD 的公共 API](https://developer.android.com/reference/android/os/ParcelFileDescriptor) 区分几件事：`getFd()` 只是借用，PFD 仍拥有 FD；`detachFd()` 会破坏原创建者期待的可靠关闭信号。`closeWithError` 向观察错误的 peer 报告本端失败；`checkError` 检查 peer 已发送的错误或崩溃；`canDetectErrors` 只表明有错误通道。

固定 [ParcelFileDescriptor.java:845](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/ParcelFileDescriptor.java#845) 显示 `close()` 发送本端 OK 状态后关闭资源；`:872` 的状态报告是 best effort，`:360` 最终 OS close 使用 `IoUtils.closeQuietly`。关闭时读到的远端状态被保存，但 `close()` 本身并不因这个状态自动抛异常。所以“try close/catch close_failed”会遗漏已经到达的 peer 错误。

[同文件 :983](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/ParcelFileDescriptor.java#983) 的 `checkError()` 在没有错误通道或尚未收到状态时直接返回；它不等待 ACK。`close()` 关闭通信通道后，后到的远端提交失败也无法再被读取。因此无异常既不代表收到了明确成功状态，也不代表提供方已完成上传。

薄平台适配可以这样改进，不必承接复制业务：

1. 把 lease 完成区分为 `complete`、`abort` 与幂等资源释放。共享层传入真实复制结果，平台层只转换为 PFD 信号。
2. 成功复制在关闭前调用 `checkError()`；无论检查结果如何都必须关闭。正常关闭后再调用一次 `checkError()`，可读取关闭时缓存的错误。保留首个错误，确保关闭异常不覆盖先前的复制失败。后一次检查只能捕获已到达/缓存状态，不能命名为“等待远端提交”。
3. 复制失败或取消走 `closeWithError`，对没有可靠通道的提供方仍只能 best effort；不要正常发送 OK。错误文案不要包含私密内容或无界 peer 消息。
4. lease 必须确保只完成一次；取消和正常完成竞争时，`released:false` 只能代表资源已经释放，不能当作已确认保存。销毁/超时后借出的 FD 要等 Rust 作业真正退出，不能以迟到回调把操作升级为成功。
5. 导入也需要 peer 错误检查：Rust 对裸 FD 读到 EOF，不会自动执行 PFD `AutoCloseInputStream` 在 EOF 时做的 `checkError()`。否则提供方错误截断可能被认作正常结束。固定源码 [PFD.java:1029](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/ParcelFileDescriptor.java#1029) 展示标准输入流的处理。

以上是错误证据不丢失的改进，不是新建提交协议。对于当前文件级别，“保存完成”应明确只指本机复制、同步及平台关闭流程无已知错误；不能显示“云端上传完成”。若产品需要“关闭后可读取内容与原文件一致”，应实施有界回读校验；若要求远端持久提交，则需要提供方专有协议，通用 SAF 无法保证。

## 三种路线的取舍

| 路线 | 工作量与获得能力 | 安全条件及局限 | 建议 |
| --- | --- | --- | --- |
| 保留 `rw` 文件路径 | 原有 Rust 无需放宽；补 PFD 完成信号和结果呈现 | 只支持空、普通、可定位且 `fsync` 成功的 FD；拒绝 w-only 提供方；不保证远端提交 | 当前最小完整基线 |
| 本次明确 `createDocument` 后用 `w` | 扩展共享复制的输出契约；可支持合法 pipe/socket | 只能用于本次创建的 handle；单文件 picker 返回值没有该证明；非文件无空文件/fstat/fsync证据 | 只有扩大提供方支持范围时实施 |
| 可靠 pipe 或 proxy FD | 提供方或 adapter 可传输错误、随机访问、同步回调 | 外部提供方决定 FD 类型；不能要求它改用可靠 pipe/proxy；自建 adapter 不能强化底层提交语义 | 首先作为真实 fixture；生产 adapter 要有实际需求 |

若实施第二条，不能在原复制入口上仅添加“接受所有特殊 FD”和“忽略所有 fsync 失败”。应让共享核心显式识别 `emptySeekableFile` 与 `newDocumentStream` 两个输出契约：前者完整保留当前检查；后者要求平台 lease 的本次新建来源，允许明确的 FIFO/socket 类型，既不把 `statSize=-1` 当零，也不对 pipe 执行 `lseek`/`fsync`。流完成回执应写出 `bytesAccepted`、`synchronization:notAvailable` 及关闭结果，不能复用“文件已同步”证据。流的非阻塞背压、部分写入、`EPIPE`/SIGPIPE、peer 死亡、取消和限时必须有测试；普通文件上真实 `fsync` 错误不能被该分支吞掉。

[createReliablePipe](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/ParcelFileDescriptor.java#524) 是数据 pipe 加另一条状态通信通道。Rust 的 POSIX `dup` 只复制数据 FD，原 PFD 必须留下负责结束信号；复制成功不等于 provider drain 成功。自建 Kotlin pump 加完成 future 可以明确知道 pump 已退出，却仍只能观察底层提供方暴露的完成证据，且增加缓冲、线程、取消与双重 FD 生命周期成本。

[ProxyFileDescriptorCallback](https://developer.android.com/reference/android/os/ProxyFileDescriptorCallback)（API 26）可在 `onWrite`、`onFsync` 抛出带 errno 的错误，`onRelease` 是关闭后的回调。固定 [ProxyFileDescriptorCallback.java:88](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/core/java/android/os/ProxyFileDescriptorCallback.java#88) 默认 `onFsync` 就抛 `EINVAL`；没有实现同步的 proxy 被当前基线拒绝是兼容限制，不是应忽略错误的理由。生产自建 proxy 如果只在 `onFsync` 同步本地缓存、随后后台上传，就不能把 fsync 成功包装成远端已保存。

## 产品必须实现与平台约束

产品必须完成：

- 给文件、相册等入口接上真正系统保存；只在 `documents.export` 的结果为已保存时显示完成。分享交给系统目标也不能当作“已保存到本机”。
- 保留原始本机来源；取消、部分完成、结果未知和提供方不支持都应有可见结果。列出目标名称/URI、已完成项及不确定项；明确本次不会自动重试或清理不确定目标。
- 结果需要跨页面导航保留；操作中途退出或进程中断后，曾创建/曾开始写入的目标不能被遗忘并自动再次保存。若声称支持进程重启恢复，需要持久化任务回执和本机源的持有关系；当前 operation 内存记录本身不构成此承诺。
- 创建调用失败、写入后失败、同步失败、关闭/peer 错误、完成回执丢失，都不能折叠为“用户取消，未产生文件”。部分目标可能已经存在。
- 同名处理由共享 coordinator 决定；本轮不提供无证据的覆盖。`ACTION_CREATE_DOCUMENT` 实际选到非空已有项时拒绝写入并保留旧文件。

平台真实约束：

- SAF 可写不等于可随机访问；不支持 `rw` 是合法提供方行为。不能通过增加一个 mode 绕过其能力。
- 通用 SAF 没有把创建、检查空文件、写入、原子发布、远端持久确认合在一起的事务；同名/并发写者检查只能降低风险。
- 一般系统保存完成可表示当前平台流程成功，不表示云端同步已完成。存在已知错误或完成证据丢失时必须呈现未知/部分结果；不能靠“API没抛异常”压掉已知状态。
- 非事务提供方无法保证中途取消撤销已写数据。为避免删除未知或被替换的用户文档，不应自动清理结果未知的 URI。

因此，“接上系统保存并如实提供结果”是必须交付的产品能力；“同时支持所有合法管道/云提供方且保证不可截断和远端持久提交”不属于通用平台能直接提供的保证。不能把前者以平台限制为由推迟，也不能把后者写成已经实现。

## 可检验的真实 fixture 与验收证据

以下是后续实施的真实 Android fixture 设计，**本报告未执行**。应放在独立测试 APK 或 debug/instrumentation 提供方中，通过真实系统 picker、ContentResolver、PFD 与 Rust 绑定运行；只模拟 Dart MethodChannel 回复不足以验证这些契约。

fixture 提供一个可写根和固定样本，记录 `create/open(mode)/read/write/fsync/close/error` 次序及独立文档 ID、最终字节内容。测试数据使用大于 pipe 缓冲区的确定性二进制和空文件，源/目的 SHA-256 与长度作为独立观察。provider 支持延迟、死亡、错误注入和独立 inspector；生产 app 不依赖测试 inspector。

| fixture 情景 | 必查结果 |
| --- | --- |
| 普通文件 `rw`，初始空，正常同步 | 系统真实保存；最终字节一致；成功计数在 copy+finalize 后增加 |
| 已有非空哨兵文件；在系统保存界面选中并确认替换 | app 仍拒绝写入；哨兵字节不变；未以 `w/wt/rwt` 打开 |
| 元数据显示零，`rw` 实际 FD 非空 | Rust 在首次 write 前拒绝，哨兵不变 |
| `w` 合法 pipe、`rw` 抛不支持 | 当前基线明确不支持且保留源；不得自动 `w` 回退；未来流方案仅对本次 create handle 成功 |
| `w` 在 open 时立即截断；元数据返回零/未知；picker 返回已有 URI | 当前实现绝不请求 `w`；未来流授权不能由 picker URI 或 Dart 参数伪造 |
| `createDocument` 返回已存在 ID，或创建完成后调用方丢失回复 | 旧 ID 在写前拒绝；回复丢失报告未知，不自动重新 create/delete |
| 可靠 pipe 正常 drain、写至中途关闭、`closeWithError`、provider 进程死亡 | 无卡死或进程崩溃；保留具体错误/部分字节；无“只要写完缓冲区就保存成功” |
| peer 已报错，但 Java `close()` 正常返回 | finalize 的 `checkError` 捕获；不会增加已保存计数；原始关闭异常 mock 仍覆盖异常传播路径 |
| provider 在收到写端关闭后延迟报错 | 显示通用 API 证据边界；不可把 close/checkError 当可等待提交 ACK；需要回读确认的流方案结果维持未知直到核验 |
| proxy FD：`onGetSize=0`、正常 onWrite/onFsync | 记录真实 fstat 类型、seek、fsync；若满足基线则正常保存，而不是按 authority 猜“云端不可用” |
| proxy FD 的 `onWrite` 抛 ENOSPC 或 `onFsync` 抛 EIO/EINVAL | 实际 Rust 错误回传；不能普遍忽略 fsync；结果含已写目标和本机源 |
| 大文件背压、不读 pipe、取消、超时、页面退出、Activity 销毁 | 作业真正收束、FD 不泄漏、不迟到升级成功；取消使用失败信号；结果保留 |
| 回读方案：元数据大小正确但字节错误、大小未知、延迟可读 | 长度相同不等于完整；有界比较成功后才升级可见内容已核验；超时留未知且不改写目标 |
| 连续两次保存、第一次结果未知 | 第二次要求新的显式用户操作，第一次记录与目标仍可核对，无自动重复副本 |

还需真实系统提供方最小烟测：系统本机“下载”位置正常保存，同名新建/显式选择已有项，取消 picker，以及一个正常返回 `rw` 的设备存储位置。记录 Android build、DocumentsUI 包版本、提供方 authority、实际请求 mode、文件内容核验、页面结果截图/日志。测试用自建 provider 的成功不能冒充实际云提供方兼容结论；只测系统本机目录也不能写成全提供方支持。

## 推荐落地顺序

1. 当前交付保留 `rw`，接通共享系统保存入口，补错误通道和完成/取消信号，给出支持范围与保留内容的结果体验。用上表普通文件、已有文件、w-only 拒绝和关闭错误 fixture 验收。
2. 产品确实需要流提供方时，再实现 `createDocument` 来源约束和共享 Rust 的显式流输出契约；不要把单文件 picker 返回 URI直接授权给该路径。单文件 w-only 可以引导用户选父目录后由本次操作创建新文档，这是新增路径而非偷偷更换打开模式。
3. 需要关闭后可见内容一致的承诺时，加有界回读比较和持久回执；需要远端上传确认时另行接入提供方明确协议。保持原生层只持有 URI、grant、PFD 与平台调用，复制、限额、比较和结果决策留在共享层。

## 后续落地证据

上述调研保留为实施前基线。后续已接通共享单项保存入口、success/abort完成信号、PFD错误检查和未知回执保护；真实API36 Downloads取消/保存以及独立外部接收器读取授权和字节/hash均通过。见[实现与命令](../implementation/content-delivery.md)和[完整失败/复验记录](../implementation/validation.md#原文件系统保存与外部分享交付)。此证据没有关闭上表自建provider/云端/pipe/撤权/写入中故障矩阵，也不意味着提供方提供持久提交ACK。
