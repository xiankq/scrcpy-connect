# 连接与传输应用源码比较：Hiddify / LocalSend

核对日期：2026-11-12。只读当前默认分支源码，未运行这两个项目。Stars 来自本次 GitHub API 采集，用于解释样本选择，不作为架构质量证明。以下源码链接固定 commit；“对本项目的判断”是推论。

## 样本版本

| 项目 | 当前默认分支快照 | Stars（采集时） | 实际状态库 |
| --- | --- | --- | --- |
| [Hiddify](https://github.com/hiddify/hiddify-app) | main，`7c9438c2b5aee1e09f096031d02cf6675d27d7c7` | 33,927 | pubspec 声明 hooks_riverpod ^2.4.10、flutter_hooks ^0.20.5；锁定 hooks_riverpod/flutter_riverpod/riverpod 2.6.1、flutter_hooks 0.20.5 |
| [LocalSend](https://github.com/localsend/localsend) | main，`2e7ef1972b0b4e210608ec77ef5fad334f798f7e` | 98,578 | Refena 3.5.0 + routerino 0.8.1；不是 Riverpod |

版本来源：[Hiddify pubspec](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/pubspec.yaml#L34)、[Hiddify lock](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/pubspec.lock#L810)、[LocalSend pubspec](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/pubspec.yaml#L54)。不能照搬 Riverpod 2 的 Ref 与生命周期细节到本仓库的 3.4.3。

## Hiddify：功能 provider 图 + 普通 Dart 原生封装，依赖 Riverpod 较深

### 实际连接调用链

```text
ConnectionButton
  watch connectionNotifierProvider
  read connectionNotifierProvider.notifier.toggleConnection()
    ConnectionNotifier
      connectionRepositoryProvider
        ConnectionRepositoryImpl
          hiddifyCoreServiceProvider
            HiddifyCoreService
              平台 CoreInterface / gRPC / VPN service
```

- **启动是分阶段主动初始化，并非“所有东西都必须 lazy”。** `lazyBootstrap` 创建 ProviderContainer，通过 read 明确等待目录、偏好、数据库、profile repository、核心初始化；部分功能使用 `_safeInit` 限时容错；然后把同一 container 交给 `UncontrolledProviderScope`。它还显式 listen activeProxy provider 避免首个页面 build 中的惰性碰撞。来源：[bootstrap L52–154](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/bootstrap.dart#L52)。这证明集中 bootstrap 可以成立，但初始化对象经过了有名字的 provider，不意味着业务全部写在 bootstrap。
- **依赖按功能装配。** connectionRepositoryProvider watch directories/configOptionRepository/coreService/profilePathResolver，再创建普通 `ConnectionRepositoryImpl`；没有要求页面穿过全应用能力集合。来源：[connection_data_providers L11–20](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_data_providers.dart#L11)。
- **共享状态与操作都在功能 Notifier。** keepAlive StreamNotifier 的 build 监听 activeProfile 并转发 repository 的 ConnectionStatus；用户方法保留 toggle/connect/disconnect 和单次操作、epoch 保护；并非为每个方法建立 provider。来源：[connection_notifier L27–78](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/notifier/connection_notifier.dart#L27)、[连接与取消 L195–278](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/notifier/connection_notifier.dart#L195)。
- **页面直接消费所需功能状态。** ConnectionButton watch connectionNotifier、stats、connectionHealth；动作 read notifier；视觉短暂状态用 useRef/useState/useEffect 的 Timer 保存，不变成应用级 provider。来源：[connection_button L53–94](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/home/widget/connection_button.dart#L53)、[局部展示状态 L149–173](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/home/widget/connection_button.dart#L149)。
- **原生异步正确性仍有专门实现。** HiddifyCoreService 有订阅表、状态流、stop 请求计数和监听代次；旧状态监听会被 `_statusListener` 过滤；平台 stop 需要先于 gRPC stop 以避开死锁。来源：[core service L30–49](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/hiddifycore/hiddify_core_service.dart#L30)、[stop L286–325](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/hiddifycore/hiddify_core_service.dart#L286)、[listener 代次 L637–654](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/hiddifycore/hiddify_core_service.dart#L637)。
- **onDispose 不是完整退出策略。** core provider 的 onDispose 启动 unawaited core.dispose；桌面明确 exit 则判断 VPN 是否归系统持有，等待 abortConnection（2s上限）、core.shutdown，再销毁 tray/window。来源：[core provider L11–15](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/hiddifycore/hiddify_core_service_provider.dart#L11)、[window exit L135–153](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/window/notifier/window_notifier.dart#L135)。

### 不能美化或照搬的部分

`ConnectionRepositoryImpl` 直接持 Ref，并读取 dialog notifier；`HiddifyCoreService` 同样直接持 Ref，初始化失败会显示 toast；ConnectionNotifier 本身调错误对话框。它不是“所有普通对象都纯构造注入”“业务与展示完全分离”的范本。来源：[repository L44–59](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_repository.dart#L44)、[repository dialog L161–179](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/features/connection/data/connection_repository.dart#L161)、[core init L51–63](https://github.com/hiddify/hiddify-app/blob/7c9438c2b5aee1e09f096031d02cf6675d27d7c7/lib/hiddifycore/hiddify_core_service.dart#L51)。本次 core service 文件本身约 870 行，说明 stars 不保证每个文件已充分收敛。

**对本项目的判断：** 更值得借鉴的是页面直连功能 provider、按真实依赖声明 `watch`、功能 Notifier 接普通 Dart/native 实现的链条；保留原生代次与显式异步 shutdown。不能从该样本推导“把资源全部交给 autoDispose”或“所有对象都应拿 Ref”。

## LocalSend：不是 Riverpod；状态按传输职责拆分，底层执行在独立包

### 实际传输调用链

```text
preInit
  创建 RefenaContainer，override 已打开的 persistence 与运行环境
  设置并启动 parentIsolateProvider（discovery/httpUpload/httpServer）
SendPage
  watch sendProvider.select(sessionId)
  read sendProvider.notifier.cancelSession(sessionId)
SendNotifier
  httpProvider / fileTransferProvider / parentIsolateProvider
  typed Rust API、typed isolate actions
packages/localsend_isolates
  实际发现、HTTP上传/接收、Rust网络与取消令牌
```

- **启动也有主动装配。** preInit 在 runApp 前初始化 Rust、持久化与平台能力，创建 container，通过 overrides 提供已有实例和环境，再显式设置/启动 IsolateController。来源：[init L60–98](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/config/init.dart#L60)、[container 与 isolate setup L149–192](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/config/init.dart#L149)。因此“启动必须全 lazy”和“先装配依赖就是架构问题”都不能由样本支持。
- **状态按职责组织，没有把发送、服务端和发现塞进一个 AppState。** sendProvider 管会话 map；serverProvider 管一个 server state；nearbyDevicesProvider 管附近设备。发现模块用构造参数接 IsolateController、FavoritesService、DiscoveryLogger。来源：[send L41–64](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L41)、[server L24–74](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/server/server_provider.dart#L24)、[nearby L17–43](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/nearby_devices_provider.dart#L17)。这里的 provider 是 Refena，不能作为 Riverpod 3 的具体用法证据。
- **执行层在真实异步 seam 后。** HTTP client provider watch security 后创建 `HttpClientCollection`；发送按所选设备指纹创建 Rust client。IsolateController 的状态持有三个类型化连接，setup 启动 discovery/upload/server isolate。来源：[http_provider L24–52](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/http_provider.dart#L24)、[parent isolate L14–35](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/packages/localsend_isolates/lib/src/isolate/parent/parent_isolate_provider.dart#L14)、[setup L61–95](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/packages/localsend_isolates/lib/src/isolate/parent/parent_isolate_provider.dart#L61)。
- **页面选择会话状态，短暂展示用 StatefulWidget。** SendPage select sessionId；取消前临时缓存两个设备用于展示，dispose 只清 taskbar 进度；是否在 pop 时取消由 `closeSessionOnClose` 决定。来源：[send_page L53–105](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/pages/send_page.dart#L53)。
- **取消不是“释放provider就算完成”。** SendNotifier 保存每会话的 Rust hash/prepare-upload cancel tokens，取消时撤销 tokens，并对精确上传 taskId 发 isolate cancel action；进度回调发现 session 已移除会忽略迟到结果。来源：[tokens L52–60](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L52)、[迟到回调 L167–202](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L167)、[取消 L709–785](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L709)。
- **应用生命周期独立于页面。** resumed 时移动端检查服务器是否仍运行，iOS 重新绑定发现；detached 时销毁子 isolate。LifeCycleWatcher 自身只登记和移除 Flutter observer。来源：[main L65–95](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/main.dart#L65)、[watcher L19–33](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/widget/watcher/life_cycle_watcher.dart#L19)。

### 不能美化或照搬的部分

SendNotifier 本次文件约 851 行，直接使用 Routerino.context 打开 SendPage，状态管理、发送编排、部分导航并未完全分离；`cancelSession` 返回 void，退出 isolate 使用 kill，源码不能证明它具有本仓库要求的可等待、失败重试的资源排空语义。来源：[send 导航 L149–161](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/app/lib/provider/network/send_provider.dart#L149)、[isolate dispose L99–105](https://github.com/localsend/localsend/blob/2e7ef1972b0b4e210608ec77ef5fad334f798f7e/packages/localsend_isolates/lib/src/isolate/parent/parent_isolate_provider.dart#L99)。

**对本项目的判断：** 领域最接近的价值是“设备发现、发送会话、接收服务的状态所有者分开 + 原生执行在包里 + 稳定会话/任务身份”，而不是照搬 Refena 或把 void cancel 当可靠回收证明。

## 两个样本共同说明的事情

真实项目都混合使用状态库、普通 Dart 对象、平台/native seam 和专门异步保护。状态库可参与依赖装配，也可拥有业务状态与动作；这不等于每个底层实现、视图状态、资源租约都必须改成 provider。更明确的共同点是**页面按功能消费状态，功能按真实依赖组合执行模块**。二者也都存在集中的启动编排和较大的实现文件，不能把 stars 或文件行数当作单一判据。
