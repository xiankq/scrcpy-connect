# Flutter 应用架构比较与本仓库判断

核对日期：2026-11-12。本轮只研究，未修改应用代码。样本选择覆盖原生代理核心、跨设备文件传输、媒体库与后台同步；沿启动、一个实际功能、原生执行和退出/取消路径读取源码，而非仅检查目录或 pubspec。外部源码固定到本次默认分支 commit。Stars 是整个仓库的采集值，仅用于说明样本规模。

## 结论

本仓库有值得处理的架构问题，上一轮拆开 AppRuntime 只改善了职责位置，尚未解决功能依赖暴露和状态传播的复杂性。最明确的问题是全应用能力入口，以及多个查询在 Riverpod 内另外实现刷新与失效协议。集中 bootstrap、普通 Dart 能力对象、显式异步关闭本身都有成熟项目先例，应分别判断。

“放进 Riverpod”要区分三件事：

1. 用 Provider 暴露一个普通 Dart 对象，参与依赖装配与替换。
2. 用 Future/StreamProvider 表达共享查询、缓存和依赖失效。
3. 用 Notifier 维护功能状态及命名操作。

这三种做法可以共存；业务实现不必全部继承 Notifier。对象通过 provider 暴露，也不代表 provider 就拥有那个对象的全部底层资源。

## 五个真实样本

| 项目 | Stars 约值 / 源码快照 | 实际实现及最有用的对照 |
| --- | --- | --- |
| FlClash | 6.27 万；`be84736605527034689c95bf27828ff27d912c5e` | Riverpod 3.4.3。普通 Dart CoreController 持有核心生命周期，provider 返回其全局实例；功能状态与 Action Notifier 分开。页面按配置字段 watch，动作调用命名 Action。[核心 provider](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/core.dart#L6-L7)、[页面](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/outbound_mode.dart#L19-L33) |
| Hiddify | 3.39 万；`7c9438c2b5aee1e09f096031d02cf6675d27d7c7` | Riverpod 2.6.1。集中 bootstrap 主动初始化多个 provider；连接页直接消费 ConnectionNotifier，repository provider 声明所需依赖，再接普通 Dart/native service。[启动](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/bootstrap.dart#L52-L154)、[功能装配](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_data_providers.dart#L11-L20) |
| Immich | 11.89 万；`dbe5e229d008404d7775d6fcce50bdb1dd98fb9b` | Riverpod 2.6.1。启动 override 数据/API 基础对象；相册 provider 注入普通 RemoteAlbumService，查询用 Future/StreamProvider，操作由相册 Notifier 发起。[启动](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/main.dart#L52-L88)、[相册依赖与查询](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/infrastructure/album.provider.dart#L13-L38) |
| LocalSend | 9.86 万；`2e7ef1972b0b4e210608ec77ef5fad334f798f7e` | 使用 Refena 3.5.0。发现、接收服务、发送会话分别管理；页面按 sessionId 消费发送状态，实际传输交给 Rust/isolate。[依赖](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/pubspec.yaml#L54)、[发送页](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/pages/send_page.dart#L53-L105) |
| Ente Photos | 3.01 万；`d3c1a2b828136f6d1fb0084a66d231768df8531b` | 没有 Riverpod。单例/ServiceLocator、类型事件、StatefulWidget 与 ChangeNotifier；部分能力通过 getter 延迟创建，picker 与常规/后台启动路径分开。[依赖](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/pubspec.yaml)、[装配](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/service_locator.dart#L57-L121)、[启动分支](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/main.dart#L444-L563) |

精确版本、调用路径与更多固定行号证据见 [FlClash 笔记](/Users/xiankq/git/scrcpy-connect/.scratch/flutter-architecture-comparison/flclash.md)、[Hiddify / LocalSend 笔记](/Users/xiankq/git/scrcpy-connect/.scratch/flutter-architecture-comparison/connection-apps.md)、[Immich / Ente 笔记](/Users/xiankq/git/scrcpy-connect/.scratch/flutter-architecture-comparison/media-apps.md)。Hiddify 与 Immich 的 Riverpod 2 用法只支持职责划分的比较，不能直接证明 Riverpod 3 的生命周期、暂停和重试行为。

### FlClash 究竟怎么用 Riverpod

它的核心 provider 源码只有下面这一层（保留原名）：

```dart
@Riverpod(keepAlive: true)
CoreController coreHandler(Ref ref) => coreController;
```

这是暴露普通 Dart 核心对象；CoreController 并没有因此变成 Notifier。[原始源码](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/core.dart#L6-L7)

模式切换的真实链路是：

```text
OutboundModeCard.watch(patchClashConfig.mode)
  用户动作 → SetupAction.changeMode
  更新配置 → 派生 updateParams
  根部 CoreManager 监听 → SetupAction.updateConfig
  普通 CoreController → RPC → 原生核心
```

页面读取/动作见 [outbound_mode.dart](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/outbound_mode.dart#L19-L57)，模式写入见 [SetupAction.changeMode](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/setup.dart#L377-L388)，配置提交见 [SetupAction.updateConfig](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/setup.dart#L317-L347)。完整根管理器、派生配置和 RPC 路径见专项笔记。

因此 FlClash 也有全局 container、全局核心对象、事件管理器和根部管理 Widget；不能描述成完全独立的功能模块范本。它有可参考的功能状态/命令入口，也保留了较宽的核心门面。退出由显式应用操作等待核心关闭，并设强退 watchdog；这不能证明它满足本仓库的失败重试和资源排空要求。

### 其他项目也有现实瑕疵

- Hiddify 的 repository/core service 直接持 Ref，部分路径显示 dialog/toast；不能以它为证据要求普通 Dart 对象全部持 Ref。[repository](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_repository.dart#L44-L59)、[dialog](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_repository.dart#L161-L179)
- Immich 正在将旧 DB/API 访问迁移到实体分组的 Store；旧 repository/service 与新入口并存，不是已经完全统一的理想模板。[Store 及迁移说明](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/data/store.dart#L12-L50)
- LocalSend 的 SendNotifier 较大，并直接打开页面；退出 isolate 使用 kill，取消会话返回 void，不能据此推导可等待的彻底排空。[发送导航](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L149-L161)、[isolate 销毁](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/packages/localsend_isolates/lib/src/isolate/parent/parent_isolate_provider.dart#L99-L105)
- Ente 有全局 ServiceLocator/EventBus、页面直接访问 DB 和很大的服务对象；它说明技术选择多样，不能证明单例方案优于 Riverpod。[全局事件](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/core/event_bus.dart#L1-L5)、[页面读取](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/ui/viewer/gallery/collection_page.dart#L146-L175)

## Riverpod 官方建议提供的边界

- provider 可以包装普通同步值、Future 或 Stream；Notifier 额外提供修改状态的命名入口。共享缓存、依赖失效、替换和异步错误表达本来就在框架职责内。[Providers](https://riverpod.dev/docs/concepts2/providers)
- `watch` 是声明依赖的常用入口；`listen` 更偏手动响应与副作用。原生事件桥和通知副作用可以合理使用 listen，但纯派生状态应先考虑 watch/select。[Refs](https://riverpod.dev/docs/concepts2/refs)
- provider 默认惰性；官方允许在根部选定 provider 主动初始化。不能把“集中启动”直接判为反模式，也不能把 keepAlive 理解为立即执行。[Eager initialization](https://riverpod.dev/docs/how_to/eager_initialization)
- 页面选择、表单、动画和 controller 等短暂状态适合页面自己的 State/Hooks。[DO/DON'T](https://riverpod.dev/docs/root/do_dont)
- autoDispose 针对 provider 状态与相应回收回调；重新计算同样会销毁旧状态。资源是否可以在这里关闭取决于实际所有权，不能让查询重建关闭共享应用连接。[Automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose)

本仓库要求普通能力实现通过参数接收依赖、不持 Ref，是本项目的边界选择。官方 Ref 文档允许把 Ref 传入对象/函数；不能把本项目规则宣称为 Riverpod 的普遍强制要求。

## 本仓库：可证实的结构与判断

以下“问题”是基于源码的维护性判断，不等于已验证的运行时故障或启动性能瓶颈。

### 1. 全应用能力总入口仍然存在

**事实：** [AppDependencies](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/app_dependencies.dart:53) 构造要求数十个能力；[AppNotifier](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/app_notifier.dart:103) 再暴露设备、文件、音视频、设置、身份等几乎所有能力。路由仍取出这个 controller 并传给页面：[app_router.dart](/Users/xiankq/git/scrcpy-connect/app/lib/router/app_router.dart:60)。

**判断：** 启动根持有资源集合可以合理，但让它同时成为普遍的功能访问入口，会隐藏某个页面/能力实际需要什么。功能独立替换也容易变成先构造整个应用能力集合。即使内部有 select 限制重建，这个依赖边界问题依然存在。

**对照：** Hiddify 连接功能显式 watch 自己需要的 repository/core；Immich 相册 provider 注入相册能力。我们可以保留唯一 native runtime，同时按功能提供窄 provider，逐步移除 AppNotifier 的能力转发。

### 2. 查询刷新在 Riverpod 内另有一套机制

**事实：** [FileTransferQuery](/Users/xiankq/git/scrcpy-connect/app/lib/core/files/file_transfer_query.dart:20) 自己维护 loading/error/data、事件前缀筛选、microtask 初次读取、pending/dirty、刷新循环及关闭；[TransferHistoryNotifier](/Users/xiankq/git/scrcpy-connect/app/lib/core/files/transfer_history_notifier.dart:14) 基本把 state 的读写回调传给它。目录查询又维护 generation/pending/dirty，并同时 watch 连接与恢复状态、监听相同方向的原始事件：[file_directory_notifier.dart](/Users/xiankq/git/scrcpy-connect/app/lib/core/files/file_directory_notifier.dart:42)。

**判断：** 这让开发者同时理解 Riverpod 依赖失效和自建刷新协议。应审查哪些 loading/error、缓存、调度可交给 FutureProvider/AsyncNotifier，哪些确为领域所需。异步结果的连接身份、撤销核验、取消令牌和恢复屏障不能靠替换成 AsyncValue 自动得到。

**已存在的良好基础：** [deviceDetails](/Users/xiankq/git/scrcpy-connect/app/lib/core/devices/device_query_provider.dart:17) 已是按设备身份的异步 provider，并绑定取消。不能笼统称本仓库“没有使用 Riverpod 查询能力”。

### 3. 全应用投影与同步提交协议增加跨功能耦合

**事实：** [ApplicationSession](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/application_session.dart:24) 有 stateEvents/stateCommits/events 等同步流与 applyingState；[AppNotifier](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/app_notifier.dart:65) 手动 listen 四类状态、在 commit 后重新组装 AppState。文件页又从全应用 AppState 选设备和恢复状态，同时读功能查询：[文件页](/Users/xiankq/git/scrcpy-connect/app/lib/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart:67)。

**判断：** 状态已经分到能力后，页面仍可能经由全局投影再读取，导致功能关系绕行。恢复快照的水位和“页面事件前状态已可读”是已有明确保证，不能直接删除提交协议。应先明确哪些消费者确实需要跨能力原子视图，再把普通功能消费改为直接依赖自己的状态；必要一致性留在真正负责恢复的所有者。

### 4. 上一轮拆文件没有缩小依赖图

**事实：** [ApplicationAssembly.open](/Users/xiankq/git/scrcpy-connect/app/lib/bootstrap/application_assembly.dart:436) 主动打开基础存储、缓存、传输等依赖，并在返回前访问 runtime 完成构造；[ApplicationRuntime 构造](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/application_runtime.dart:42) 仍接收约 28 个所有者。新增 Operations 层承担操作准入与诊断，但很多动作仍是转发。

**判断：** 原 AppRuntime 文件变短不能证明依赖设计已经优化。下一轮应以调用路径、可独立替换范围、资源所有者和可删除层数评估，而非文件行数。必须有具体额外语义才保留一层 Operations/Service 包装。

构造所有能力对象和启动所有原生任务也需区分：当前 activate 明确执行恢复、事件附着、后台策略和重连服务启动，并不能从构造图推出已为所有功能打开播放器/设备会话。[activate](/Users/xiankq/git/scrcpy-connect/app/lib/core/application/application_runtime.dart:315) 本轮未做性能测量，不据此声称启动已变慢。

## 建议的调整边界

| 职责 | 建议所有者 | 应保留的保证 |
| --- | --- | --- |
| native host、连接 scope、应用退出 | 普通 Dart runtime / 连接所有者 | 应用唯一性、异步 close 屏障、失败重试、有序排空 |
| 文件、设备、媒体的依赖装配 | 各能力的 provider | 依赖显式、独立 override；可借用 app runtime，无需重新创建 host |
| 按设备/路径/任务身份的查询 | 功能 Future/StreamProvider，必要时 AsyncNotifier | 缓存身份、精确失效、取消、旧连接结果不能恢复操作资格 |
| 有持续状态的业务操作 | 功能 Notifier + 普通能力实现 | 操作去重、任务身份、准入与恢复约束 |
| 焦点、选择、动画、视图租约 | 页面 State/Hooks | 页面结束只释放自己的订阅/租约 |

建议先验证文件目录这一条完整调用链：页面直接消费目录查询、文件操作、设备连接及恢复状态的窄 provider；普通文件执行对象继续通过参数接收依赖；同时审查目录的双重失效和通用 FileTransferQuery 是否有无法由框架清楚表达的语义。每删除一层，都列出它原先保证什么、现在由谁保证。

应先覆盖真实边界：仅 override 文件能力即可独立创建查询；在途请求遇到连接身份更换；resync 期间旧回执；多个消费者共享查询；最后消费者离开后的取消；应用 close 失败后重试。上一轮新增的 8 个测试没有 ProviderContainer/ProviderScope 级验证，不能作为这些 Riverpod 关系已正确的证据。

待这一条链的职责、代码量与边界验证成立，再推广到设备和媒体。本轮不引入新状态框架，也不继续铺开重写。

## 验证范围

这是固定源码的静态比较，未构建或运行上述五个外部项目。外部样本不能替代本仓库的设备/原生生命周期验证。本轮仅新增研究笔记，无应用行为变更，因此没有重复运行应用测试。Stars 的第一方采集入口：[FlClash API](https://api.github.com/repos/chen08209/FlClash)、[Hiddify API](https://api.github.com/repos/hiddify/hiddify-app)、[Immich API](https://api.github.com/repos/immich-app/immich)、[LocalSend API](https://api.github.com/repos/localsend/localsend)、[Ente API](https://api.github.com/repos/ente/ente)。
