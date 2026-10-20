# Flutter 页面与路由

应用通过 go_router 与 go_router_builder 生成类型化路由，版本以 `app/pubspec.yaml` 和根 `pubspec.lock` 为准。产品行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准。生产入口是 `app/lib/app.dart` 的 `MaterialApp.router`；初始化失败时，`main.dart` 使用独立的 `StartupErrorPage`，不依赖尚未建立的连接服务或路由。

## 文件布局

- `app/lib/pages/` 按业务归属组织父子目录。有延伸子页的入口放入该业务目录的 `index/`；叶页直接放在自己的目录，不额外套 `index/`。
- 页面文件名由 `pages/` 以下的完整目录链用下划线连接，再加 `_page.dart`，包括 `index`：例如 `settings/index/settings_index_page.dart`、`settings/appearance/settings_appearance_page.dart`、`transfers/details/index/transfers_details_index_page.dart`。
- 页面专属组件放在该页面目录的 `widgets/`。跨子页共用的业务组件放在最近共同业务目录的 `widgets/`，例如 `devices/widgets/device_identity.dart` 和 `transfers/details/widgets/`；不从另一个页面的私有 `widgets/` 引入。
- `app/lib/widgets/`：通用布局、操作行、反馈与命令视图。
- `app/lib/services/`：控制器、剪贴板协调、文件操作、校验与数据转换。
- `app/lib/router/`：类型化路由声明及生成文件、ID 查找、异步路由加载与导航方法。

不使用 `part` 聚合页面。生产 imports 直接指向所属文件；只有生成器产物使用标准的 `.g.dart` part。

设置归 `settings/`，连接建立流程归 `connection/`，设备工作台归 `devices/workspace/`，连接偏好、能力及诊断页暂归 `devices/details/`（没有独立详情页），任务接收与导出归 `transfers/details/`。同一页面的多个入口复用同一实现；目录表达业务归属，不机械复制路由 URL 或每条跳转路径。页面类名与 typed route 身份不因目录迁移而改变。

## 页面身份

| 路由名 | 路径 | 解析依据 |
| --- | --- | --- |
| devices / transfers / settings | `/devices` / `/transfers` / `/settings` | 有恢复身份的 StatefulShellRoute 分支 |
| add-device | `/connection/add` | 统一添加设备页；发现二级页入口在上，四种表单形式原位切换；可选 deviceId 用于重新授权 |
| wireless-guide / connection-form | `/connection/wireless` / `/connection/form` | 兼容地址呈现同一添加页并预选配对或 IP 形式；可选 deviceId，地址、端口只是待确认表单值 |
| discovery | `/connection/discovery` | 独立发现二级页，选中结果以 typed 返回值回填原添加表单 |
| usb-guide / qr-pair | `/connection/usb` / `/connection/qr` | 兼容地址呈现同一添加页并预选 USB 或扫码形式 |
| workspace | `/devices/:deviceId` | `device.info` |
| device-connection / capabilities / diagnostics | `/devices/:deviceId/<功能>` | `device.info` |
| device-activities / device-adb-key / device-convert-ip | `/devices/:deviceId/activities` / `/devices/:deviceId/adb-key` / `/devices/:deviceId/convert-ip` | 核验同一 deviceId；活动按设备过滤，私钥与显式 IP 切换归当前设备 |
| files / file-details / file-search / gallery / media-preview | `/devices/:deviceId/<功能>` | deviceId；文件 path 经当前目录清单重新核对 |
| apps / notifications / calls / quality / session-tools / sessions | `/devices/:deviceId/<功能>` | deviceId；通知回复额外按 notificationId 查当前通知 |
| remote / remote-app | `/devices/:deviceId/remote` / `/devices/:deviceId/apps/:packageName/remote` | 显式打开意图；URL 恢复不会自动创建会话 |
| remote-session | `/devices/:deviceId/sessions/:sessionId` | 当前 `session.list` 中匹配的会话 |
| transfer-details / document-export / receive-content | `/transfers/:taskId` 及其 `/export`、`/receive` 子路径 | `transfers.get`；导出能力与本机路径重新核对 |
| document-import / share-directory | `/devices/:deviceId/documents/import` / `/devices/:deviceId/share-directory` | deviceId 与明确目标目录 |
| incoming-share | `/sharing/:shareId` | 本机尚未消费的 pending share |
| appearance / background / adb-key / data-preferences / media-cache | `/settings/<功能>` | 本机设置与实际服务状态；adb-key 管理全局私钥；声音和剪贴板没有专用设置路由 |
| activities（兼容） | `/settings/activities` | 仅重定向设备列表，由用户选择设备后查看其活动 |
| transfer-center / settings-page | `/activity/transfers` / `/preferences` | 从业务页覆盖打开的独立页面 |

添加设备的方式切换由页面内状态负责，不 push 另一层表单路由。配对码与地址字段草稿在统一外壳保留；二维码配对、USB 检查及发现请求各自持有尝试身份，切换后旧回执不得更新新形式或导航。已有设备的重新授权在配对码、扫码与 USB 形式中均保留 deviceId，使用同一设备选定的授权身份。配对后补全连接端口仍在同页，并携带已配对设备身份与加密连接方式。

旧 `/devices/:deviceId/details` 地址只重定向到该设备工作台，用于已有链接恢复，不建立第二个设备详情页面。

`app_router.dart` 使用 `@TypedGoRoute` 和 `@TypedStatefulShellRoute` 声明完整路由图，生产调用直接使用生成的 `FilesRoute(deviceId: id).push<void>(context)`、`ConnectionFormRoute(...).pushReplacement(context)` 等 API。路径参数、查询参数与返回结果均有类型。`navigation.dart` 只保留带显式启动意图的远控入口、typed 返回和回设备页，不保留字符串命名路由分派表。

`RouteRepository` 只接受记录标识。路径、地址或记录 ID 不代表授权，路由从不恢复私钥、长期信任或认证状态。找不到设备、任务、通知、文件或会话时显示可重试错误和返回设备列表入口，不强制转换缺失 extra。

## 生命周期与返回

三标签保留分支状态，返回按标签访问历史恢复。根路由使用显式 Flutter `MaterialPage`，保证桌面与移动端保留相同的页面过渡语义。全屏远控覆盖根 Navigator，底部标签和页面顶栏不会进入远控画面。主题更新、事件更新与 `router.refresh()` 保留同一路由的活动远控子树及其首次打开决定，临时 extra 被重新解码也不会丢失已绑定画面；新的进程恢复仍必须重新查找会话，不能自动创建画面。路由重建保留原 RemotePage 状态；普通退出或路由移除释放本次呈现意图，并请求暂停不可见画面，保留真实会话与应用任务；显式关闭才停止准确的 sessionId。暂停拒绝或挂起不得阻止离页；恢复只重新核对已有会话，不重放初始操作。

新远控只接受短暂的 `RemoteLaunchIntent`，不把 Widget 放进 extra。该意图丢失后只显示明确重新打开入口。已有会话按 deviceId 与 sessionId 重新查找，不以页面恢复自动创建新流。

目录选择返回 `String?`，取消为 null。导入成功返回 bool，再进入传输中心；分享确认与取消都按 shareId 消费队列，提交文件时携带同一 shareId 供后端保留传输源。连接成功用生成的 typed 路由替换表单，返回不会重开已经完成的尝试。弹窗、菜单和系统选择器结果保留局部 Navigator.pop。

## 状态与依赖所有权

`AppController` 是 `riverpod_generator` 生成的 Notifier；`AppState` 是深冻结不可变快照，包含设备、偏好、分享队列和明确的状态字段。页面通过 `ref.watch(appControllerProvider.select(...))` 订阅自己需要的字段。服务的 imperative 操作用 `snapshot()` 读取当前值，不通过公开 getter 或可变集合绕开响应式状态。

`appDependenciesProvider` 在应用根 `ProviderScope` 注入真实 bridge request、events 和 close。生成的 `appControllerProvider` 使用 `ref.watch` 持有该依赖，并通过 `ref.onDispose` 取消唯一事件订阅、关闭事件流及释放 transport。异步设备/设置回执受请求序号和 provider 生命周期约束，旧回执不会覆盖新状态。`session.frame` 仅向持有 session 的页面事件流转发，不更新整个应用的状态快照。

生成的 `clipboardCoordinatorProvider` 持有前台剪贴板协调器，并监听设备、偏好和焦点字段，销毁时取消 timer、事件和生命周期观察。普通文本控制器随页面释放；视频播放器和呈现意图通过共享 SessionViews 按真实会话及代际管理，页面取得与释放自己的呈现资格。页面销毁不等于停止真实会话。当前同runtime校准与呈现重建不等于进程死亡后完整恢复，具体边界见[状态恢复](state-recovery.md)。

## 当前设备归属

设备专用页在`_deviceRecord`确认设备后共用`VisibleDeviceFocus`，以ModalRoute当前资格、生命周期及核验状态声明归属；失去资格只撤回自己的待处理声明，不能清空新页面的焦点。post-frame再次检查epoch、设备、mounted及实际route，返回/replace或同帧核验后正确跟随；Remote继续使用更严格的会话/画面核验，不由共享包装器抢先设焦点。独立回复route重新读取通知，失效且已有本机回复时仅呈现核对/复制，不把内存内容恢复成远端动作。对应实际回复流程与历史测试范围见[验收记录](validation.md#历史设备流程证据)。

## 生成与分析

generator 与 build_runner 的兼容组合由 workspace 依赖和根 lockfile 固定；升级时同时检查生成器支持的 build/analyzer 范围。

从 workspace 根运行 `dart run build_runner build --workspace`；验证生成文件使用 `dart run build_runner build --workspace --only-check`。生成文件应与源码一起保留。`app/build.yaml` 只为生成文件忽略 go_router_builder 对 nullable Object extra 产生的冗余 cast；手写代码保留严格类型分析。

官方 `riverpod_lint 3.1.9` 通过 workspace 根 analysis plugin 启用，app 继承根 analysis options，不使用旧 custom_lint 插件配置。Flutter hooks 暂无已确认的一方独立 lint；不引入与当前 analyzer 14 不兼容的第三方 custom_lint 插件。

## 验证

既有页面与交互测试继续保留。`router_test.dart` 覆盖分支状态与返回、ID 查找、缺失记录、远控重建与会话清理、typed 目录结果、分享返回和表单替换。`architecture_test.dart` 约束业务层级命名、单页叶目录、生成 typed 路由与共享组件位置。`app_provider_test.dart` 验证深冻结快照、晚回执抑制、transport 释放、原生帧隔离和设置更新顺序。Android 真机/模拟器 integration tests 仍从实际桥接服务读取状态，不用路由测试 fixture 代替原生验收。
