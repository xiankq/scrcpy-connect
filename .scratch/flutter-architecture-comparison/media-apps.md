# Immich 与 Ente Photos：真实 Flutter 架构取样

核实日期：2026-11-12。只读官方默认分支源码，GitHub 网页与 API 核对身份、stars，浅克隆后固定 commit 逐文件阅读。Stars 属于整个仓库，不单独代表 Flutter 子项目；这里记录实际实现，不把流行度当作架构正确性的证明。

| 项目 | 快照 | GitHub stars（采集值） | 实际状态库 |
| --- | --- | ---: | --- |
| Immich | `dbe5e229d008404d7775d6fcce50bdb1dd98fb9b`，main | 118,931 | Flutter mobile 的 hooks_riverpod 锁定 2.6.1，flutter_hooks 锁定 0.21.3+1；路由是 auto_route。 |
| Ente Photos | `d3c1a2b828136f6d1fb0084a66d231768df8531b`，main | 30,062 | Photos 没有 Riverpod 依赖；使用单例、全局类型事件、StatefulWidget、ChangeNotifier/ValueNotifier/InheritedWidget。 |

元数据来源：[Immich 仓库](https://github.com/immich-app/immich)、[Immich API](https://api.github.com/repos/immich-app/immich)、[Ente 仓库](https://github.com/ente/ente)、[Ente API](https://api.github.com/repos/ente/ente)。旧地址 `ente-io/ente` 现在重定向到 `ente/ente`。版本依据：[Immich pubspec](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/pubspec.yaml#L30-L39)、[Immich lock](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/pubspec.lock#L803-L810)、[Ente Photos pubspec](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/pubspec.yaml)。

## Immich：Riverpod 同时装配依赖、投影查询和维护功能状态，业务实现并未全放进 Notifier

### 启动与共享依赖

`main` 在 `runApp` 前执行 domain bootstrap、应用平台准备、worker pool、数据库迁移，随后通过 `ProviderScope.overrides` 提供已构造好的 `DataController` 和 `ApiService`。[main.dart:52–88](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/main.dart#L52-L88)

`Bootstrap.initDomain` 负责网络、数据库、设置、日志和 PhotoManager 的准备；它没有承担相册创建、同步或 UI 操作。[bootstrap.dart:48–87](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/utils/bootstrap.dart#L48-L87)

这里不是“启动时把一切业务都 eager 成 provider”。原生/数据库基础依赖明确在启动前准备，能力对象则由 provider 按依赖接线。也不能把“全部挪进 main”当作模仿目标，bootstrap 自身明确标出数据库耦合的待移除项。

### 一个完整相册调用链

- 页面 `AlbumsPage` 直接 `watch(remoteAlbumProvider.select(...))` 读取相册数量，刷新动作调用相册 Notifier；滚动 controller 在页面创建和释放。[album.page.dart:20–35](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/presentation/pages/album.page.dart#L20-L35)
- `CreateAlbumPage` 的已选资源、创建中标记、导航与提示保留在 StatefulWidget。用户提交时直接调用 `remoteAlbumProvider.notifier.createAlbumWithAssets`。[create_album.page.dart:154–201](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/presentation/pages/create_album.page.dart#L154-L201)
- `album.provider.dart` 建立 `remoteAlbumServiceProvider`，仅注入相册 repository、API repository、上传能力；同时用 `StreamProvider` 表达本地相册流、`FutureProvider.family` 表达按相册身份查询缩略图。[album.provider.dart:13–38](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/infrastructure/album.provider.dart#L13-L38)
- `RemoteAlbumNotifier` 维护 `RemoteAlbumState`，调用普通 `RemoteAlbumService`，操作成功后更新相册状态。[remote_album.provider.dart:33–55](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/infrastructure/remote_album.provider.dart#L33-L55)、[创建操作:105–139](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/infrastructure/remote_album.provider.dart#L105-L139)
- `RemoteAlbumService` 本身不持有 `Ref`；通过构造参数借用明确依赖，并负责本地/远端资源分类、排序/搜索、API 与本地数据库更新顺序。[remote_album.service.dart:25–51](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/domain/services/remote_album.service.dart#L25-L51)、[创建提交:118–132](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/domain/services/remote_album.service.dart#L118-L132)
- 读取链的末端是 Drift repository。`LocalAlbumRepository.watchAll` 返回数据库查询流；不是页面自己解释原始数据库字段，也不是应用级大门面轮询并分发所有 feature。[local_album.repository.dart:18–57](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/infrastructure/repositories/local_album.repository.dart#L18-L57)

### 长寿命任务并没有交给 provider 自动神奇处理

同步 provider 注入 repository、原生同步 API 与 isolate 的取消信号，执行算法在普通 Dart 对象内。[sync.provider.dart:13–50](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/infrastructure/sync.provider.dart#L13-L50)

`backgroundSyncProvider` 创建 `BackgroundSyncManager`，用 `onDispose(manager.cancel)` 触发回收。manager 的 `cancel()` 自己撤销引用、取消任务并等待任务 unwind；因此其异步语义来自 manager，不能解释为 Riverpod 等待了异步关闭。[background_sync.provider.dart:6–38](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/providers/background_sync.provider.dart#L6-L38)、[background_sync.dart:61–97](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/domain/utils/background_sync.dart#L61-L97)

### 必须承认的复杂性和迁移状态

当前 `Store` 是全局入口的命名空间，以两个注入的基础 provider 提供实体分组入口；文件明确说明旧的直接 DB/API 访问仍在迁移。实体 `PersonStore` 暴露 autoDispose 的按身份查询和独立 mutations，这与单个 AppNotifier 转发全部业务不同，但也不是“永远没有统一入口”。[store.dart:12–50](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/data/store.dart#L12-L50)、[person.dart:9–64](https://github.com/immich-app/immich/blob/dbe5e229d008404d7775d6fcce50bdb1dd98fb9b/mobile/lib/data/store/person.dart#L9-L64)

该项目也有 controller initState 手动 refresh、Notifier `ref.read`、同步/异步生命周期混用等现实做法。其 Riverpod 是 2.6.1，不能拿来证明 Riverpod 3 的暂停、重试等行为相同。我们应借鉴功能直达的依赖与查询、普通能力对象和明确任务所有者；不机械复制目录和所有写法。

## Ente Photos：完全不同的技术路线，同样有长寿命任务与局部状态

### 启动与业务装配

`main` 进行 Flutter、Rive、MediaKit 等准备，`_runInForeground` 先 `_init` 再 `runApp`。`_init` 还区分普通启动、picker 启动与后台启动，picker 会提前结束后续上传/同步准备。[main.dart:109–167](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/main.dart#L109-L167)、[不同启动路径:444–563](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/main.dart#L444-L563)

基础依赖通过 `ServiceLocator.instance.init` 设置；大量 feature getter 采用 `??=` 延迟创建。它不是 Riverpod，也不是纯构造注入；服务定位器、单例和显式 init 顺序是实际依赖机制。[service_locator.dart:57–121](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/service_locator.dart#L57-L121)

### 一个完整相册读取/更新链

`CollectionsService.instance` 自己借用数据库/配置单例，缓存相册数据；`init` 加载数据库，再注册类型事件订阅。重新初始化时先取消旧订阅。[collections_service.dart:61–129](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/services/collections_service.dart#L61-L129)

`CollectionPage` 是普通 StatefulWidget：直接从 `CollectionsService` 取封面缓存，订阅类型化的 `CollectionUpdatedEvent`，在 dispose 时取消自己的订阅，异步返回用 `mounted + generation` 过滤迟到结果；图库直接从 `FilesDB` 加载。选择状态由页面持有的 `SelectedFiles extends ChangeNotifier` 维护。[collection_page.dart:52–117](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/ui/viewer/gallery/collection_page.dart#L52-L117)、[图库加载:146–175](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/ui/viewer/gallery/collection_page.dart#L146-L175)、[selected_files.dart:8–26](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/models/selected_files.dart#L8-L26)

事件总线是一个全局 `EventBus` 单例，实际事件使用 Dart 类型。不能因为文件名里有 provider 就将其误认成 Riverpod：图库里的 provider 也包含 InheritedWidget、ChangeNotifier 和 ValueNotifier。[event_bus.dart](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/core/event_bus.dart#L1-L5)、[gallery_boundaries_provider.dart](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/ui/viewer/gallery/state/gallery_boundaries_provider.dart)

### 任务与资源退出

`SyncService` 单例借用本地/远端同步与上传单例，内部用 `_existingSync` 去重、停止标志控制阶段准入；ML 的 `MlRunControl` 也自行锁存停止原因，不依赖 UI 或状态库的存活判定。[sync_service.dart:28–57](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/services/sync/sync_service.dart#L28-L57)、[停止标志:199–209](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/services/sync/sync_service.dart#L199-L209)、[ml_run_control.dart:14–44](https://github.com/ente/ente/blob/d3c1a2b828136f6d1fb0084a66d231768df8531b/mobile/apps/photos/lib/services/machine_learning/ml_run_control.dart#L14-L44)

### 不适合照搬的部分

Ente Photos 的显式启动路径、任务停止语义和页面自己的订阅所有权值得参考；但是它同时有全局依赖、直接 DB 访问、全局 EventBus 和很大的能力对象（本次快照 main 823 行、CollectionsService 2771 行、ServiceLocator 415 行）。这些是实际维护取舍，不能拿高 stars 推导出“单例比 Riverpod 更好”或“该架构没有耦合问题”。

## 对当前仓库的推论（不是外部项目的官方要求）

1. “业务全部放 Riverpod”不是这些项目的共同做法；“让 Riverpod 管什么”必须按对象职责逐项判断。Immich 会把普通功能对象注册成 provider，同时保留不持 Ref 的业务实现；Ente 则完全不依赖 Riverpod。
2. 更值得对照的是调用路径：一个相册页面通常直接消费相册状态/查询及命名能力。若我们的页面必须经过全应用 AppNotifier、AppDependencies、ApplicationSession 再访问任意功能，应逐层说明额外语义；没有额外语义的聚合入口值得移除。
3. 强行要求所有依赖在一个巨大构造图中集中接线，并不等于保住资源所有权。Immich 的 feature provider 也能接线普通能力对象。可把依赖图逐功能暴露给 Riverpod，同时保留真正拥有原生 scope、任务和关闭屏障的对象；不能借迁移之名让页面 autoDispose 去关闭应用级连接。
4. 状态源应按实际数据所有者确定。数据库或原生 SDK 已有流时，可由局部 StreamProvider 投影；不用再额外写一套“事件→应用快照→状态仓库→页面事件”的缓存和失效系统。我们的恢复水位、精确租约是否需要这些层，应逐项用保证说明，不能以“其他项目也用了事件总线”替代判断。
5. 普通页面局部状态采用 Hooks、State、ChangeNotifier 均有成熟实践；无需把选择、焦点、controller 强行提升为共享 provider。
