# AppRuntime：Flutter 生命周期与依赖装配依据

核实日期：2026-11-12。官方文档是指导，下面与本项目的对应关系是基于本地代码的设计判断。

## 适用版本

以根 `pubspec.lock`、`.dart_tool/package_config.json` 及实际缓存源码为准：Flutter 3.47.8、Dart 3.13.7；`riverpod` / `flutter_riverpod` / `hooks_riverpod` 3.4.3；`flutter_hooks` 0.21.4；`riverpod_annotation` 4.0.7、`riverpod_generator` 4.0.9。网页会更新且 pub.dev 对部分锁定版本的页面暂不可访问，因此涉及生命周期签名的结论同时核对本地对应版本源码。

## 官方规则及本项目含义

| 官方规则 | 对本项目的判断 |
| --- | --- |
| Flutter 以职责分离、依赖注入、单向数据流为核心；架构建议允许按应用特点调整，额外 domain/use-case 层是有条件使用的。见 [Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations) 与 [架构指南](https://docs.flutter.dev/app-architecture/guide)。 | 保留既有能力模块和类型化接口，通过构造参数传入依赖。无需改成 MVVM 目录或为每个方法另加 use-case。`bootstrap` 负责装配，业务规则回到能力所有者。 |
| Riverpod 的 provider 默认延迟初始化；官方建议只对需要的 provider 在根 `ProviderScope` 下的 Consumer 中 `watch`，也能在该处呈现加载与错误状态。见 [提前初始化](https://riverpod.dev/docs/how_to/eager_initialization)。 | `keepAlive` 不等于提前初始化。应用级状态可在根部持续订阅；这不要求所有能力都变成 provider，也不要求把已有原生初始化移动进 build。 |
| provider 应自行初始化；不要由 Widget 的 initState/useEffect 手动初始化共享 provider。表单、焦点、动画等短暂视图状态宜就近保留。provider 计算不适合充当写操作触发器。见 [DO/DON'T](https://riverpod.dev/docs/root/do_dont)。 | 能力 Notifier 的初始读取应由自身 build/依赖触发，用户操作仍调用明确命名的 Dart 方法。视图租约与页面局部交互继续由 Widget/Hooks 持有。 |
| 自动释放依据监听者计数；重新计算也会销毁旧状态，`keepAlive` 不能阻止依赖变化造成的重建。`onDispose` 不应修改其他 provider。见 [自动释放](https://riverpod.dev/docs/concepts2/auto_dispose)。 | 连接、缓存、传输等资源的生命周期按实际所有者决定；不能为了页面方便统一 autoDispose。应用依赖对象一旦替换，其订阅所有者也必须精确退出。 |
| `Ref.onDispose` 接收 `void Function()`；`ProviderContainer.dispose()` 返回 void。对应本地 3.4.3 源码见下文；在线源码入口见 [Ref](https://github.com/rrousselGit/riverpod/blob/master/packages/riverpod/lib/src/core/ref.dart)。 | 同步 dispose 通知不是可等待的异步关闭屏障。`unawaited(close())` 可以启动回收，但不能据此释放承载连接、允许重启接管，或判定回收成功。原生资源需要显式、可 await、可重试的关闭操作。 |
| Hooks 的 useEffect 同步执行；返回的 `Dispose` 是 void 回调，在 key 改变或 Widget 退出时调用。见 [useEffect](https://pub.dev/documentation/flutter_hooks/latest/flutter_hooks/useEffect.html)。本地 0.21.4 源码签名一致。 | Hooks 适合绑定视图监听和释放租约，不适合承担原生宿主的完整有序异步关闭。启动异步工作后仍须由拥有者处理取消、迟到结果和错误。 |
| Riverpod 3 的 provider 计算失败默认自动重试，最多 10 次，退避为 200ms 至 6.4s；可配置或禁用。见 [自动重试](https://riverpod.dev/docs/concepts2/retry)。 | 把显式 bootstrap 移入 FutureProvider 会改变失败和重试语义。原生 scope/身份选择/迁移不是可以随意重跑的读取，先保留现有 gate 与重试规则。 |
| Riverpod 3 的不可见消费者会基于 TickerMode 暂停订阅，见 [3.0 生命周期变化](https://riverpod.dev/docs/whats_new)。本地 flutter_riverpod 3.4.3 的 ConsumerStatefulElement 同样实现该行为。 | 应用级事件和后台活动不能依靠某个页面是否可见来维持；页面只订阅投影，不取得连接与任务的关闭权。 |
| Flutter 不保证所有应用生命周期通知都被送达；不可取消的退出不经过 onExitRequested。见 [AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html) 与 [onExitRequested](https://api.flutter.dev/flutter/widgets/AppLifecycleListener/onExitRequested.html)。 | 桌面可等待退出回调只是正常退出路径；移动端异常终止必须依靠已有持久化、恢复和孤立资源回收。不能以 Widget dispose 替代恢复机制。 |

## 已核对的本地源码与既有保证

- `~/.pub-cache/hosted/pub.flutter-io.cn/riverpod-3.4.3/lib/src/core/ref.dart`：`onDispose(void Function() listener)`，调用者不接收关闭 Future。
- 同版本 `core/provider_container.dart`：`void dispose()`；`core/element.dart` 的 `runOnDispose()` 同步运行已登记回调。
- `~/.pub-cache/hosted/pub.flutter-io.cn/flutter_hooks-0.21.4/lib/src/primitives.dart`：`typedef Dispose = void Function()`；`_EffectHookState.dispose()` 直接调用 disposer。
- `~/.pub-cache/hosted/pub.flutter-io.cn/flutter_riverpod-3.4.3/lib/src/core/consumer.dart`：Consumer 根据 TickerMode 暂停和恢复订阅。
- `app/lib/core/application/application_session_provider.dart` 由一个 scope 创建 ApplicationSession；session 先向状态所有者同步交付事件再通知页面。拆分不能建立第二份状态源或第二个传输订阅所有者。
- `app/lib/bootstrap/app_runtime.dart` 的初始化 gate、旧实例排空、连接活动退出与 OrderedDisposal 含有原生所有权规则。拆分文件并不授权改变这些规则。

## 推荐的实施顺序

1. 先为真实可观察保证建立少量回归覆盖：状态未核验时拒绝写操作、关闭后拒绝新操作、取消与错误保留原语义、关闭失败时承载层不提前释放且可重试。不要为纯转发编写结构测试。
2. 将 AppRuntime 中按能力聚合的操作包装迁回能力目录。让它们实现已有公开接口，通过明确依赖接入；共享普通诊断/错误辅助只抽真正一致的部分，保留各能力的错误类型、核验条件和日志字段。
3. 再拆应用级跨能力协调与生命周期；`bootstrap` 保留创建与接线。先保持启动步骤、状态恢复水位、取消行为和有序关闭不变。
4. 每步执行静态分析、架构检查、格式与生成一致性检查；对涉及所有权的步骤运行新增行为覆盖。启动性能或异步加载 UX 改动另行取证，不能因文件长就推断所有初始化都应延迟。

判断是否改善：理解文件能力的执行和失败规则无需阅读媒体、连接与整个启动装配；理解应用退出时仍能在一个明确所有者处找到可等待的关闭顺序。
