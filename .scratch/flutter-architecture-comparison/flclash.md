# FlClash 源码架构核查

本笔记只读开源源码，没有修改本项目应用。核查日期：2026-11-12。事实依据为维护者 GitHub 仓库、GitHub API 和浅克隆源码；没有依赖二手架构文章，也没有运行 FlClash 来推断运行时行为。

## 样本与版本

- Canonical 仓库：[chen08209/FlClash](https://github.com/chen08209/FlClash)。GitHub API 于 **2026-11-12 08:25:56 UTC** 返回默认分支 `main`、**62,747 stars**、`pushed_at: 2026-11-04T07:31:46Z`；star 数是查询时快照。[第一方 API](https://api.github.com/repos/chen08209/FlClash)
- 本次读取的 `main` 提交：**`be84736605527034689c95bf27828ff27d912c5e`**。下文所有源码链接固定此 SHA，避免默认分支后续变化。[固定提交](https://github.com/chen08209/FlClash/commit/be84736605527034689c95bf27828ff27d912c5e)
- `pubspec.yaml` 应用版本 `0.9.3+2026110401`，Dart SDK `>=3.10.0 <4.0.0`；`flutter_riverpod` / `riverpod` 为 `^3.4.3`，`riverpod_annotation` 为 `^4.0.7`，generator 为 `^4.0.9`。锁文件实际解析分别为 `3.4.3`、`3.4.3`、`4.0.7`、`4.0.9`。依赖清单没有 `flutter_hooks` / `hooks_riverpod`，`pubspec` 的 `hooks:` 是构建 hook，不是 Flutter Hooks 状态库。[pubspec](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/pubspec.yaml#L1-L92)、[flutter_riverpod lock](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/pubspec.lock#L508-L515)、[其他 Riverpod lock](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/pubspec.lock#L1085-L1116)

## 直接回答

**FlClash 使用 Riverpod 很多，但没有把所有核心实现搬成 Notifier，也没有一个包办整个应用所有命令的 `AppNotifier`。它同时存在按功能划分的 providers/actions、全局单例核心门面、全局事件分发器、全局 ProviderContainer 和根部 Manager Widget。** 这不是“所有东西一股脑交给 Riverpod”，也不是“完全独立的 feature 架构”。下面逐条给出源码依据。

### 1. 启动有明确阶段，确实会主动启动核心

`main` 先 `RustLib.init()`、`system.init()`、`bootstrap.init()`，安装 HTTP overrides 并 `request.attach(container.read)`，最后把已创建容器交给 `UncontrolledProviderScope`。因此它也有启动前原生初始化，不能声称它一切等到页面使用才初始化。[main](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/main.dart#L38-L50)

Bootstrap 构造 `ProviderContainer(overrides: [...appStateOverrides, ...configOverrides])`，保存到 `globalState.container`，随后显式 seed 动态颜色、查询数据库 profiles 并写入 provider、加载语言、初始化窗口。这里是保存配置与必要状态的装配，不是遍历创建所有 providers。[bootstrap](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/bootstrap.dart#L114-L137)

`Application.initState` 在首帧后调用 `bootstrap.attach()`；`_initApp` 调度托盘、订阅更新、检查更新等任务，处理恢复/免责声明，然后明确 `await coreActionProvider.notifier.startCore()`、按恢复模式调用 `setupAction.initStatus()`。核心进程启动由这段应用级启动流程触发，不是 `coreHandlerProvider.build()` 的副作用。[首帧 attach](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/application.dart#L70-L85)、[启动编排](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/bootstrap.dart#L140-L178)

**推论：**“启动就启动核心”本身不能用这个案例判错。FlClash 的主要产品就是操作一个 Clash 核心。要比较的是启动是否有必要、启动副作用的归属、失败/恢复策略，以及是否把无关功能都带着初始化。它的根部 Manager 栈也会建立很多应用级监听，不能宣传成纯粹惰性初始化。

### 2. Riverpod 暴露核心，但没有拥有整个核心实现

最关键的 2 行是：

```dart
@Riverpod(keepAlive: true)
CoreController coreHandler(Ref ref) => coreController;
```

这里确实返回**全局实例**，不是逐功能创建依赖，也没有在这个 provider 上注册核心关闭回调。[完整 provider](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/core.dart#L1-L7)

`coreController` 本身是全局 `final`。`CoreController` 是包装 `CoreHandlerInterface` 的 Dart extension type，工厂缓存单例，并根据 Android/桌面选择 `coreLib` / `coreService`；它向上提供一个较宽的具名核心接口。[单例与平台选择](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/controller.dart#L15-L37)、[全局实例](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/controller.dart#L213)

桌面的真正资源管理在普通 Dart `CoreService` / `DesktopCoreLifecycle`：前者组合生命周期控制器、RPC channel、crash subscription，后者持有 transport、状态流、进程 session、待处理命令、revision 和期望状态。生命周期构造器接收 transport factory / launcher resolver 等依赖，不依赖 Riverpod。[CoreService](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/service.dart#L19-L84)、[生命周期实现与依赖](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/desktop/lifecycle.dart#L126-L202)

**推论：**可借鉴的是“能力实现的生命周期、并发和原生协议留在普通 Dart 模块，Riverpod 提供应用侧访问和状态集成”。不能把这个事实包装成“FlClash 没有全局门面”，它明确有。

### 3. 页面读取功能状态，点击调用具名 Action；实际链仍经过根部 Manager

`OutboundModeCard` 是最完整的真实例子，读取模式用：

```dart
final mode = ref.watch(
  patchClashConfigProvider.select((state) => state.mode),
);
```

同一文件点击时先判断当前值，再调用：

```dart
ref.read(setupActionProvider.notifier).changeMode(mode);
```

这不是伪代码；分别在 [outbound_mode.dart:19–33](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/outbound_mode.dart#L19-L33) 和 [点击入口:47–57](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/outbound_mode.dart#L47-L57)。

完整模式切换链：

1. `SetupAction.changeMode` 更新 `patchClashConfigProvider`；切到 global 模式时还调用 `proxiesActionProvider` 更新当前分组。[changeMode](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/setup.dart#L377-L386)
2. 派生 `updateParamsProvider` watch 配置和网络设置并形成 `UpdateParams`，其中包含 mode。[派生参数](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/state/system.dart#L3-L17)、[mode 映射](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/models/clash_config.dart#L2357-L2378)
3. 根部 `CoreManager` 用 `ref.listenManual(updateParamsProvider, ...)` 触发 `setupAction.updateConfigDebounce()`；并非某个 feature provider 自己完整拥有这条副作用链。[CoreManager 监听](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/manager/core_manager.dart#L37-L60)
4. `SetupAction.updateConfig()` 读取当前 provider 值，经 `_core.updateConfig(...)` 推给核心；原生边界将具名 `CoreMethod.configUpdate` 和参数序列化为 RPC。桌面由 `CoreService` 转交 RPC client。[应用命令](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/setup.dart#L317-L347)、[具名核心方法](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/interface.dart#L109-L115)、[RPC 转交](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/service.dart#L100-L110)

直接使用 `coreActionProvider` 的例子是 `CoreStatusButton`：它 `ref.read` + `ref.listenManual(coreStatusProvider)` 管本地按钮显示，用户确认后 `await ref.read(coreActionProvider.notifier).restartCore()`。**这个按钮用的是 listenManual，不应写成 ref.watch。** `CoreAction` 是 `keepAlive`、`void build()` 的命令协调 Notifier，内部通过 `coreHandlerProvider` 访问全局核心；重启时再协调 `setupAction` 和其他功能状态，并合并同时到来的重启请求。[按钮读取与本地状态](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/core_status_button.dart#L20-L61)、[重启调用](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/core_status_button.dart#L64-L83)、[CoreAction 定义](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/core.dart#L3-L43)、[重启编排](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/core.dart#L99-L141)

**推论：**它能支持“页面面向功能状态、调用具名命令”这一方向，不能支持“所有命令都应该经过一个应用级 AppNotifier”。但它也使用 Action 调 Action、Manager 监听 provider 再触发副作用，并不是严格的 feature 隔离范本。

### 4. 哪些东西放 / 不放 Riverpod

| 职责 | 源码事实 |
| --- | --- |
| 应用可观察状态、配置切片 | 独立的设置/状态 providers；配置聚合 `_config` 通过 `ref.watch` 形成 `Config` 快照，用于配置读写，而非统一命令入口。[config](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/config.dart#L98-L161) |
| 查询/数据库订阅与界面更新 | `profilesStreamProvider` 返回 Drift 查询 stream；`Profiles` Notifier 监听查询，额外管理乐观写入、回读，而不是把数据库实现改成 Notifier。[database providers](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/database.dart#L130-L164) |
| 应用命令与跨状态编排 | `CoreAction` / `SetupAction` / `SystemAction` 等 Notifier。`SetupAction` 自己还有 scheduler、timer、运行请求和已应用参数；注册 `ref.onDispose` 关闭自己的 timer。[SetupAction](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/setup.dart#L35-L79) |
| 核心进程、transport 与 RPC | `CoreService` / `DesktopCoreLifecycle` 普通 Dart 实现；通过 provider 暴露单例。[service](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/service.dart#L19-L110) |
| 纯页面短期状态 | `CoreStatusButton` 的 600ms 最短 connecting 展示、timer 保存在 Widget State，dispose 时 cancel。[按钮局部状态](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/views/dashboard/widgets/core_status_button.dart#L20-L61) |
| 页面轮询的可见性/定时器 | `ActivePollingMixin` 保存在 Widget State，跟随 app lifecycle 和页面可见性，dispose 停止并解除 observer。[轮询 mixin](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/widgets/active_polling.dart#L10-L92) |

### 5. 它明确存在全局状态、事件总线和宽门面

- **全局 ProviderContainer：**`GlobalState` 单例有 `late ProviderContainer container`，并在普通 getter / helper 里读 provider。HTTP `Request` 也保存注入的 `ProviderReader`，以便后续读取应用状态。因此“没有全局 Ref 字段”不等于“没有全局容器访问”。[GlobalState](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/state.dart#L15-L46)、[Request reader](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/common/request.dart#L15-L59)
- **全局核心事件分发器：**`coreEventManager` 是全局实例；内部接收动态 `CoreEvent.data`，集中解析，再调 `CoreEventListener` 的具名 typed hooks。它不是完全无 Map 的事件系统，但 Map/JSON 到 typed 数据的转换集中在原生事件边界。[事件分发实现](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/event.dart#L24-L136)
- **根部中央桥接：**`CoreManager` 注册 listener，退出时移除；收到 request、traffic、DNS、crash 等事件后直接更新多个 feature providers。它还监听多个配置 providers 触发 setup。不是每个 feature 都自行订阅同一批原始 Map 事件。[监听与解除](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/manager/core_manager.dart#L37-L114)、[事件写入功能状态](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/manager/core_manager.dart#L155-L200)
- **嵌套 Manager Widget：**根部堆叠 Core、Connectivity、Tray、HotKey、Proxy、Window 等 Manager。业务编排有一部分依赖根 Widget 生命周期。[manager stack](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/application.dart#L24-L52)
- **宽核心接口和 Action library：**`CoreHandlerInterface` 既有 start/restart/stop/close，也有通用 `invokeMethod` 及大量具体核心操作；Actions 虽分文件，仍通过 `part` 属于一个共享导入的 Dart library。不能只数文件数量就认定模块隔离很好。[核心接口](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/interface.dart#L12-L25)、[Actions library](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/action.dart#L1-L46)

**设计判断：**这些是成熟项目的实际取舍，不能因为 star 多就把它们一律叫最佳实践。全局容器隐藏依赖，根部桥接 Widget 会集中业务规则，较大的 SetupAction 仍有宽协调器的维护成本。可借鉴的是稳定能力边界、具名接口和事件转换归属；不能照搬为本项目再建一个全局 service locator 或万能事件入口的理由。

### 6. 关闭、失败与重试归属

退出由 `SystemAction.handleExit` 显式调用 `SystemExitCoordinator`，按 cleanup → closeWindow → closeCore → exitApplication 执行；各步出错会记首个错误并继续后续步骤。`closeCore()` 明确 `await _core.close()`。这个路径不是靠 `ref.onDispose` 等待原生资源释放。[SystemAction](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/system.dart#L32-L62)、[closeCore](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/system.dart#L96-L110)、[退出协调器](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/system_exit.dart#L21-L68)

`CoreService.close()` 合并重复关闭，在 `finally` 中依次关闭 RPC client、取消 crash subscription。`DesktopCoreLifecycle` 用 revision/intent/worker 处理 start/restart/stop/close，并把 close 设为终态；两层都缓存关闭 Future。[service close](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/service.dart#L86-L98)、[lifecycle close/submit](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/desktop/lifecycle.dart#L204-L238)

生命周期实现会保留未确认退出的进程 lease，下一次 reconcile 先尝试清理后再继续命令；但终态关闭允许 cleanup failure / 未确认退出被放过。再加 `SystemAction` 配置的 **3 秒退出 watchdog**，这不是“保证所有异步资源确已释放后才退出”的范本，也不能声称重复 close 会重新尝试失败的关闭操作。[重试入口](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/desktop/lifecycle.dart#L294-L301)、[lease 清理策略](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/core/desktop/lifecycle.dart#L522-L599)、[watchdog 配置](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/system.dart#L32-L43)、[watchdog 行为](https://github.com/chen08209/FlClash/blob/be84736605527034689c95bf27828ff27d912c5e/lib/providers/actions/system_exit.dart#L44-L54)

## 对本项目比较的含义（设计推论）

1. 不应把“用不用 Riverpod”“启动是否有全局装配”“所有 core 是否 eager”混成同一个问题。FlClash 的核心启动是显式产品流程，普通 provider 的声明/override 与真正启动原生进程是不同动作。
2. 功能页面可以直接 watch 自己需要的状态、调用具名业务操作；不需要统一穿过一个覆盖全应用的 Notifier。FlClash 的 Action Notifier 用于应用编排，底层能力仍有独立生命周期实现。
3. FlClash 能证明全局核心门面在真实项目中存在，不能证明本项目的依赖大包 → ApplicationSession → 宽 AppNotifier 就合理。其宽门面围绕同一个 Clash 核心，而本项目有设备连接、控制会话、传输任务等不同资源归属，不能用“都是 core”抹平这些边界。
4. 与其照搬全局事件总线，更值得关注的是原始协议事件在哪里转为具名数据、谁唯一负责事件对功能状态的影响、谁拥有订阅。FlClash 主要集中在根部 CoreManager；这减少页面直接读原始事件，但也让中央桥接承担较多跨功能规则，仍应作为成本评估。
5. 核心资源的异步 close、并发命令、迟到结果与失败恢复必须由明确 owner 管理。Riverpod 能提供应用观察、依赖访问和取消回调，但本例资源正确性的关键在普通 Dart 生命周期模块，不能通过把对象塞进 provider 自动得到。
