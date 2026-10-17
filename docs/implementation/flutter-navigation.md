# Flutter 页面与路由

应用采用 go_router 18.1.0 与 go_router_builder 4.5.0 生成类型化路由。生产入口是 `lib/app.dart` 的 `MaterialApp.router`；初始化失败时，`main.dart` 使用独立的 `StartupErrorPage`，不依赖尚未建立的连接服务或路由。

## 文件布局

- `lib/pages/<page_name>/<page_name>_page.dart`：每页单独目录、单独页面文件。
- 页面专属组件放在该页目录内的 `widgets/`，例如远控退出手柄。
- `lib/widgets/`：通用布局、操作行、反馈与命令视图。
- `lib/services/`：控制器、剪贴板协调、文件操作、校验与数据转换。
- `lib/router/`：类型化路由声明及生成文件、ID 查找、异步路由加载与导航方法。

不使用 `part` 聚合页面。生产 imports 直接指向所属文件；只有生成器产物使用标准的 `.g.dart` part。

## 页面身份

| 路由名 | 路径 | 解析依据 |
| --- | --- | --- |
| devices / transfers / settings | `/devices` / `/transfers` / `/settings` | 有恢复身份的 StatefulShellRoute 分支 |
| add-device | `/connection/add` | 可选 deviceId，用于重新授权 |
| wireless-guide / connection-form | `/connection/wireless` / `/connection/form` | 可选 deviceId，地址、端口只是待确认表单值 |
| discovery / usb-guide / qr-pair | `/connection/discovery` / `/connection/usb` / `/connection/qr` | 页面各自拥有尝试与取消生命周期 |
| workspace | `/devices/:deviceId` | `device.info` |
| device-details / device-connection / capabilities / diagnostics | `/devices/:deviceId/<功能>` | `device.info` |
| files / file-details / gallery / media-preview | `/devices/:deviceId/<功能>` | deviceId；文件 path 经当前目录清单重新核对 |
| apps / notifications / calls / quality / session-tools / sessions | `/devices/:deviceId/<功能>` | deviceId；通知回复额外按 notificationId 查当前通知 |
| remote / remote-app | `/devices/:deviceId/remote` / `/devices/:deviceId/apps/:packageName/remote` | 显式打开意图；URL 恢复不会自动创建会话 |
| remote-session | `/devices/:deviceId/sessions/:sessionId` | 当前 `session.list` 中匹配的会话 |
| transfer-details / document-export | `/transfers/:taskId` / `/transfers/:taskId/export` | `transfers.get`；导出能力与本机路径重新核对 |
| document-import / share-directory | `/devices/:deviceId/documents/import` / `/devices/:deviceId/share-directory` | deviceId 与明确目标目录 |
| incoming-share | `/sharing/:shareId` | 本机尚未消费的 pending share |
| appearance / clipboard / audio / background / activities / data-preferences | `/settings/<功能>` | 本机设置与实际服务状态 |
| transfer-center / settings-page | `/activity/transfers` / `/preferences` | 从业务页覆盖打开的独立页面 |

`app_router.dart` 使用 `@TypedGoRoute` 和 `@TypedStatefulShellRoute` 声明完整路由图，生产调用直接使用生成的 `FilesRoute(deviceId: id).push<void>(context)`、`ConnectionFormRoute(...).pushReplacement(context)` 等 API。路径参数、查询参数与返回结果均有类型。`navigation.dart` 只保留带显式启动意图的远控入口、typed 返回和回设备页，不保留字符串命名路由分派表。

`RouteRepository` 只接受记录标识。路径、地址或记录 ID 不代表授权，路由从不恢复私钥、长期信任或认证状态。找不到设备、任务、通知、文件或会话时显示可重试错误和返回设备列表入口，不强制转换缺失 extra。

## 生命周期与返回

三标签保留分支状态，返回按标签访问历史恢复。根路由使用显式 Flutter `MaterialPage`，保证桌面与移动端保留相同的页面过渡语义。全屏远控覆盖根 Navigator，底部标签和页面顶栏不会进入远控画面。主题更新、事件更新与 `router.refresh()` 保留同一路由的活动远控子树及其首次打开决定，临时 extra 被重新解码也不会丢失已绑定画面；新的进程恢复仍必须重新查找会话，不能自动创建画面。路由重建保留原 RemotePage 状态；退出或声明式移除只停止它绑定的 sessionId，保留目标应用任务。

新远控只接受短暂的 `RemoteLaunchIntent`，不把 Widget 放进 extra。该意图丢失后只显示明确重新打开入口。已有会话按 deviceId 与 sessionId 重新查找，不以页面恢复自动创建新流。

目录选择返回 `String?`，取消为 null。导入成功返回 bool，再进入传输中心；分享确认与取消都按 shareId 消费队列，提交文件时携带同一 shareId 供后端保留传输源。连接成功用生成的 typed 路由替换表单，返回不会重开已经完成的尝试。弹窗、菜单和系统选择器结果保留局部 Navigator.pop。

## 状态与依赖所有权

`AppController` 是 `riverpod_generator` 生成的 Notifier；`AppState` 是深冻结不可变快照，包含设备、偏好、分享队列和明确的状态字段。页面通过 `ref.watch(appControllerProvider.select(...))` 订阅自己需要的字段。服务的 imperative 操作用 `snapshot()` 读取当前值，不通过公开 getter 或可变集合绕开响应式状态。

`appDependenciesProvider` 在应用根 `ProviderScope` 注入真实 bridge request、events 和 close。生成的 `appControllerProvider` 使用 `ref.watch` 持有该依赖，并通过 `ref.onDispose` 取消唯一事件订阅、关闭事件流及释放 transport。异步设备/设置回执受请求序号和 provider 生命周期约束，旧回执不会覆盖新状态。`session.frame` 仅向持有 session 的页面事件流转发，不更新整个应用的状态快照。

生成的 `clipboardCoordinatorProvider` 持有前台剪贴板协调器，并监听设备、偏好和焦点字段，销毁时取消 timer、事件和生命周期观察。普通文本控制器与视频播放器仍按页面本身的生命周期持有。

独立测试可使用真实的生成 provider，不需要构造 ChangeNotifier：

```dart
final container = ProviderContainer(overrides: [
  appDependenciesProvider.overrideWithValue(AppDependencies(
    request: request,
    events: events,
    initialize: false,
  )),
]);
final controller = container.read(appControllerProvider.notifier);
final settings = container.read(appControllerProvider).settings;
// UncontrolledProviderScope(container: container, child: const ConnectApp())
container.dispose();
```

## 生成与分析

直接依赖锁定 `riverpod_annotation 4.0.7`、`riverpod_generator 4.0.9`、`go_router_builder 4.5.0` 与 `build_runner 2.16.2`。build_runner 2.17.1 使用 build 5，而当前两个 generator 使用 build 4，因此不能随意升级这组依赖。

从 workspace 根运行 `dart run build_runner build --workspace`；验证生成文件使用 `dart run build_runner build --workspace --only-check`。生成文件应与源码一起保留。`apps/connect/build.yaml` 只为生成文件忽略 go_router_builder 对 nullable Object extra 产生的冗余 cast；手写代码保留严格类型分析。

官方 `riverpod_lint 3.1.9` 通过 workspace 根 analysis plugin 启用，app 继承根 analysis options，不使用旧 custom_lint 插件配置。Flutter hooks 暂无已确认的一方独立 lint；不引入与当前 analyzer 14 不兼容的第三方 custom_lint 插件。

## 验证

既有页面与交互测试继续保留。`router_test.dart` 覆盖分支状态与返回、ID 查找、缺失记录、远控重建与会话清理、typed 目录结果、分享返回和表单替换。`architecture_test.dart` 约束浅层页面目录、单页文件、生成 typed 路由与共享组件位置。`app_provider_test.dart` 验证深冻结快照、晚回执抑制、transport 释放、原生帧隔离和设置更新顺序。Android 真机/模拟器 integration tests 仍从实际桥接服务读取状态，不用路由测试 fixture 代替原生验收。


设备专用页在`_deviceRecord`确认设备后共用`VisibleDeviceFocus`，以ModalRoute当前资格、生命周期及核验状态声明归属；失去资格只撤回自己的待处理声明，不能清空新页面的焦点。post-frame再次检查epoch、设备、mounted及实际route，返回/replace或同帧核验后正确跟随；Remote继续使用更严格的会话/画面核验，不由共享包装器抢先设焦点。独立回复route重新读取通知，失效且已有本机回复时仅呈现核对/复制，不把内存内容恢复成远端动作。公开typed路由六项与实际回复流程见[验收记录](validation.md#连接入口设备归属与原通知回复闭环)。
