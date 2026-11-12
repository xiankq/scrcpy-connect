# Flutter 架构与状态管理的一手资料核对

核对日期：2026-11-11。此文件是研究笔记，不是实现规格或重构工单；未修改应用。官方文档经 Context7 与网页交叉核对，开源实现按下列固定 Git commit 阅读。Stars 仅说明样本认可度，不证明代码正确。

## 本项目版本基线

`app/pubspec.yaml` 声明 hooks_riverpod ^3.4.3、flutter_hooks ^0.21.3+1、go_router ^18.1.1，workspace `pubspec.lock` 实际解析为 hooks_riverpod/flutter_riverpod/riverpod 3.4.3、flutter_hooks 0.21.4、go_router 18.1.4、go_router_builder 4.5.3、riverpod_annotation 4.0.7、riverpod_generator 4.0.9、riverpod_lint 3.1.9。不能仅凭各包 major 数字不同推断兼容性问题。根 `analysis_options.yaml` 已启用 flutter_lints、riverpod_lint analyzer plugin 与 strict casts/inference/raw types。

## 官方原则：哪些必须认真对待，哪些是可选方案

| 主题 | 一手资料支持的判断 | 对审查的意义 |
| --- | --- | --- |
| 分层 | Flutter 强推荐职责分离、UI/data 分层、单向数据流、不可变模型、依赖注入；指南明确应适应应用需求，不是硬规则。 | 检查业务规则、数据所有权和可替换依赖，不能按是否叫 ViewModel/Repository 直接判错。 |
| 数据接口 | Flutter 强推荐 Repository 隔离外部数据来源，服务负责具体外部交互。 | wire JSON 在传输适配处合理；大量应用调用者自行理解 JSON 字段意味着隔离不足，是接口质量问题。 |
| 状态库 | Flutter 对 ChangeNotifier/Listenable 的推荐是 conditional，并明确存在多种状态管理选择；provider 是 DI 的推荐实现。 | 使用 Riverpod 实现 DI 与响应式更新符合原则，无须再添加 provider 或改成 ChangeNotifier。 |
| domain/use cases | domain layer 是 conditional；复杂或重复业务逻辑才需要额外用例。 | 原生连接、资源租约和恢复协调器可能有充分理由独立存在；不能要求每个 UI 事件再包装一个 use case。 |
| 路由 | go_router 是官方推荐路由方案；typed GoRouteData/go_router_builder 能将构造参数错误提前至编译期。 | 本项目有 typed routes 是优点；不要求 router 必须由 Riverpod 创建。 |
| code generation | Riverpod codegen 可选；目前文档建议在项目已有 codegen 时使用，不必仅为 Riverpod 引入生成步骤。 | 已有 Riverpod/go_router codegen 可保留；是否 Freezed 不决定是否不可变。 |

来源：[Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations)、[架构指南](https://docs.flutter.dev/app-architecture/guide)、[数据层](https://docs.flutter.dev/app-architecture/case-study/data-layer)、[DI 示例](https://docs.flutter.dev/app-architecture/case-study/dependency-injection)、[类型安全路由](https://pub.dev/documentation/go_router/latest/topics/Type-safe%20routes-topic.html)、[Riverpod codegen](https://riverpod.dev/docs/concepts/about_code_generation)。以上是概括，不是要求逐条照搬 Compass 的类名或目录。

## Riverpod 3 的具体审查标准

- 共享业务状态适合 provider；输入框、动画、焦点、普通局部选择等 ephemeral state 更适合 hooks/State。provider 应自行初始化，避免 widget 初始化时额外调用业务 provider 的 init；导航前明确的用户动作可以调用命令。provider 初始化主要表达读取/订阅，避免把提交表单等写操作建模成自动重算的 provider。这不等于禁止 provider 创建受管理的资源或订阅。[DO/DON'T](https://riverpod.dev/docs/root/do_dont)
- `watch` 是声明式依赖的默认选择；`listen` 适用于状态变化后做导航、日志、提示等副作用；事件处理时 `read` 获取动作接口合理。将 `read` 用于本应响应依赖变化的展示值会漏更新。[Refs](https://riverpod.dev/docs/concepts2/refs)
- 生成 provider 默认自动释放；有 family 参数时推荐自动释放，避免参数组合无限保留。`keepAlive` 有效地表达应用、连接或在途工作寿命，但不会阻止依赖重算时销毁旧状态。`onDispose` 用于资源清理，不能在回调中修改其他 provider。[Automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose)
- Riverpod 3 统一使用 `==` 过滤更新，使用 Ref 之前需考虑 await 期间被销毁，官方提供 `ref.mounted`；provider 失败默认自动 retry；不可见消费者会暂停 listener；StateProvider/StateNotifierProvider/ChangeNotifierProvider 已移入 legacy 导入。本项目已是 3.x，不能套 2.x 的生命周期假设。[3.0 migration](https://riverpod.dev/docs/3.0_migration)
- `mounted` 只说明 owner 尚存，不证明结果仍属当前设备、当前请求或当前会话；原生资源代码仍需要序列号、epoch、租约或取消令牌。这是对异步语义的工程推断，不能指望换 AsyncNotifier 自动消除逻辑过期结果。
- `.select` 适合大状态中的细粒度订阅，但官方要求先测量；它增加读取和理解成本，被选属性应不可变。没有到处 `.select` 并非缺陷，已有 `.select` 也不能自动证明性能良好。[优化指南](https://riverpod.dev/docs/how_to/select)
- 测试应为每例创建独立 container；自动释放 provider 在测试中应有 listener 持有；依赖可通过 overrides 替换。重点是测试真实公开行为和竞态，而非让每个 provider 都有模板式测试。[Testing](https://riverpod.dev/docs/how_to/testing)
- 应用启动要 eager initialize provider 时，官方推荐根 ProviderScope 下专门 Consumer watch，且可只返回稳定 child，避免将整棵应用绑定到高频状态。不能把所有启动工作一概塞进 main 或 widget initState。[Eager initialization](https://riverpod.dev/docs/how_to/eager_initialization)

这里没有官方规定“每个功能必须一个 AsyncNotifier”“业务服务必须持有 Ref”“所有查询必须 FutureProvider”。但 Riverpod 已提供依赖追踪、共享缓存、family、失效、loading/error 和生命周期；若应用另建查询层，应该能说明它提供的额外语义，以及如何避免重复缓存与失效规则。

## Hooks 与路由细节

- hooks 与 Riverpod 独立；HookConsumerWidget 只是组合局部 widget 生命周期和 provider 消费。它们能减少 controller/init/dispose 重复，但不是 Flutter 或 Riverpod 的必选方案。[About hooks](https://riverpod.dev/docs/concepts/about_hooks)
- hook 应无条件、顺序一致地调用；局部 controller 优先使用现成 hook；`useEffect` 同步执行，省略 keys 会每次 build 执行，返回的清理函数在 keys 改变或 dispose 时执行。[flutter_hooks](https://pub.dev/packages/flutter_hooks)、[useEffect](https://pub.dev/documentation/flutter_hooks/latest/flutter_hooks/useEffect.html)
- `useMemoized` 缓存实例并在 keys 改变时重建；`useFuture` 订阅已有 Future，官方明确不要直接 `useFuture(fetch())` 在每次 build 创建新 Future。keys 中要覆盖结果依赖的身份与参数。[useMemoized](https://pub.dev/documentation/flutter_hooks/latest/flutter_hooks/useMemoized.html)、[useFuture](https://pub.dev/documentation/flutter_hooks/latest/flutter_hooks/useFuture.html)
- go_router typed path/query 提供构造检查，但页面资源是否仍有效、设备是否存在、会话如何恢复仍由应用负责。`$extra` 不属于 URL，官方明确其会影响动态/deep linking，尤其 web；能从稳定身份恢复的路由更容易测试和重入。[go_router_builder](https://pub.dev/packages/go_router_builder)
- provider 自身也处理创建、监听、释放与 `watch/read/select`；这与 Riverpod 的目标部分重叠。已经使用 Riverpod 的项目无需为了“官方推荐 provider”再引入第二套 DI。[provider](https://pub.dev/packages/provider)

## 成熟开源应用的真实做法

### Immich：hooks_riverpod + flutter_hooks，路由是 auto_route

快照 `940df6476ae8d0218a58f4e9fb8c4a169a021108`；2026-11-11 GitHub 约 118.7k stars。pubspec 当前是 hooks_riverpod ^2.6.1、flutter_hooks ^0.21.3+1、auto_route ^11.1.0，不能误写成 Riverpod 3/go_router 样本。[仓库](https://github.com/immich-app/immich)、[pubspec](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/pubspec.yaml)

- `providers/infrastructure/sync.provider.dart` 主要装配服务依赖：数据库 repositories、API、原生同步适配器与 cancellation。业务逻辑在 domain service；provider 不必吞并业务实现。[源码](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/providers/infrastructure/sync.provider.dart)
- `album.provider.dart` 用 typed StreamProvider/FutureProvider.family 读取局部相册与缩略图；远程相册 service 和 Notifier 分开。并非为每个方法都建 provider。[源码](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/providers/infrastructure/album.provider.dart)
- `AlbumApiRepository` 将 API DTO 转 `RemoteAlbum`，方法返回领域类型或含 added/failed 的 typed record；调用者无需解释任意 Json。[源码](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/repositories/album_api_repository.dart)
- 数据库 provider 注册 `ref.onDispose` close，background sync provider 注册 manager.cancel；隔离任务 cancellation 是明确注入的信号，资源归属有独立机制。[数据库](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/providers/infrastructure/db.provider.dart)、[后台同步](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/providers/background_sync.provider.dart)、[取消信号](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/mobile/lib/providers/infrastructure/cancel.provider.dart)

项目自己的架构文档强调 repositories 不应在接口暴露 foreign DTO，同时坦承图示是目标架构，当前代码并非处处遵守。这正说明高认可项目适合作为经过检验的参考，不是必须照搬的标准答案。[架构文档](https://github.com/immich-app/immich/blob/940df6476ae8d0218a58f4e9fb8c4a169a021108/docs/docs/developer/architecture.mdx)

### Hiddify：hooks_riverpod + flutter_hooks + go_router

快照 `05fb2b34af3c24b31d468e08cdf657ee083b2bed`；2026-11-11 GitHub 约 33.9k stars。pubspec 是 hooks_riverpod ^2.4.10、flutter_hooks ^0.20.5、go_router ^16.2.4。它是本次技术组合最接近的成熟样本，且同样需要协调长寿命原生连接。[仓库](https://github.com/hiddify/hiddify-app)、[pubspec](https://github.com/hiddify/hiddify-app/blob/05fb2b34af3c24b31d468e08cdf657ee083b2bed/pubspec.yaml)

- `ConnectionRepository` 显式定义 setup、watchConnectionStatus、connect、disconnect、reconnect，输入输出为 ProfileEntity、ConnectionStatus、ConnectionFailure；实现再映射原生 core 状态。[源码](https://github.com/hiddify/hiddify-app/blob/05fb2b34af3c24b31d468e08cdf657ee083b2bed/lib/features/connection/data/connection_repository.dart)
- `ConnectionNotifier` 用 keepAlive stream provider 暴露应用级连接状态，监听 profile 变化；连接命令包含 SingleCall 和 `_connectEpoch`，避免过期 connect 覆盖新状态。使用响应式状态库仍需要业务所有权和竞态控制。[源码](https://github.com/hiddify/hiddify-app/blob/05fb2b34af3c24b31d468e08cdf657ee083b2bed/lib/features/connection/notifier/connection_notifier.dart)
- `SettingInputDialog` 使用 HookConsumerWidget、useTextEditingController/useFocusNode 处理局部输入和焦点；`GoRouterNotifer` 用 keepAlive provider 创建 router，routingConfig 用 listen 更新。[输入弹窗](https://github.com/hiddify/hiddify-app/blob/05fb2b34af3c24b31d468e08cdf657ee083b2bed/lib/core/router/dialog/widgets/setting_input_dialog.dart)、[路由](https://github.com/hiddify/hiddify-app/blob/05fb2b34af3c24b31d468e08cdf657ee083b2bed/lib/core/router/go_router/go_router_notifier.dart)

这些源码也包含 repository 持 Ref、业务流程调 dialog 等耦合，并非每行都符合最严格分层。可借鉴 typed feature 接口与原生竞态处理，不宜把它整个目录设计视为规范。

### LocalSend：当前是 Refena + routerino，不是 Riverpod

快照 `8476c091c5a107e4507b6b3ec0cb15a069e857b5`；GitHub API 本次读到 98,274 stars。当前 pubspec 使用 refena_flutter 3.5.0、routerino 0.8.1，并有独立 isolates/Rust 包。它是跨平台设备发现和文件传输领域参照，不能充当当前 Riverpod 写法的证据。[仓库](https://github.com/localsend/localsend)、[pubspec](https://github.com/localsend/localsend/blob/8476c091c5a107e4507b6b3ec0cb15a069e857b5/app/pubspec.yaml)

`nearby_devices_provider.dart` 用 typed NearbyDevicesState、动作和构造注入协调发现；`main.dart` 做系统生命周期回调、后台 sockets 恢复，`LifeCycleWatcher` 在 widget dispose 移除 observer。`SendPage` 使用 StatefulWidget 存局部展示信息，使用 select 订阅指定 session，而非把一切状态都装进全局对象。[设备发现](https://github.com/localsend/localsend/blob/8476c091c5a107e4507b6b3ec0cb15a069e857b5/app/lib/provider/network/nearby_devices_provider.dart)、[main](https://github.com/localsend/localsend/blob/8476c091c5a107e4507b6b3ec0cb15a069e857b5/app/lib/main.dart)、[生命周期](https://github.com/localsend/localsend/blob/8476c091c5a107e4507b6b3ec0cb15a069e857b5/app/lib/widget/watcher/life_cycle_watcher.dart)、[传输页面](https://github.com/localsend/localsend/blob/8476c091c5a107e4507b6b3ec0cb15a069e857b5/app/lib/pages/send_page.dart)

### AppFlowy：Flutter/Rust + Bloc/provider/GetIt + go_router

快照 `8fcee27d9bd93aad4ee0191d5d8d915d6a9a4e93`；GitHub API 本次读到 78,667 stars。当前依赖同时包含 flutter_bloc、provider、get_it、go_router，不是 hooks_riverpod 项目。适合作为 Flutter/Rust 应用如何定义显式业务接口与生命周期的参考。[仓库](https://github.com/AppFlowy-IO/AppFlowy)、[pubspec](https://github.com/AppFlowy-IO/AppFlowy/blob/8fcee27d9bd93aad4ee0191d5d8d915d6a9a4e93/frontend/appflowy_flutter/pubspec.yaml)

`ViewBloc` 持有 view/favorite listeners，在 close 中 stop；`ViewBackendService` 为 Rust dispatch 的 typed protobuf payload 提供 createView/getChildViews 等 typed 方法；go_router 使用 StatefulShellRoute 保存分支状态。它没有“所有数据方法都必须 repository 类”或“所有接口都禁止原生 DTO”的统一纯净形状，但关键行为是可读的命名接口，而非 UI 到 enum+任意Json 的统一入口。[ViewBloc](https://github.com/AppFlowy-IO/AppFlowy/blob/8fcee27d9bd93aad4ee0191d5d8d915d6a9a4e93/frontend/appflowy_flutter/lib/workspace/application/view/view_bloc.dart)、[ViewBackendService](https://github.com/AppFlowy-IO/AppFlowy/blob/8fcee27d9bd93aad4ee0191d5d8d915d6a9a4e93/frontend/appflowy_flutter/lib/workspace/application/view/view_service.dart)、[路由](https://github.com/AppFlowy-IO/AppFlowy/blob/8fcee27d9bd93aad4ee0191d5d8d915d6a9a4e93/frontend/appflowy_flutter/lib/startup/tasks/generate_router.dart)

## 用于最终判断的边界

强证据支持保留：不可变业务快照、清晰原生包公开接口、显式资源 owner、长寿命连接、constructor DI/override seam、局部 hooks、typed route、真实异步竞态测试。没有证据支持为了符合模板重排目录、全量改库或强行将所有流程拆成 providers。

值得优先检视的接口问题：共享查询与缓存的身份、失效和错误语义是否集中；业务调用是否被 enum+Json 擦去输入输出类型；UI 是否承担可独立于页面存在的恢复/传输/连接流程；一个入口是否使多数功能彼此知道过多。它们可以在现有技术栈中局部改进，不要求重写应用，也不能只凭文件长度或 provider 数量证明。
