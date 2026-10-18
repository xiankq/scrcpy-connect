# 当前目录与模块职责

本文描述当前工作区的实现。需求和约束见根目录 GLOSSARY.md 与 docs/adr/；
功能完成度与验证边界见[验收记录](validation.md)。
历史验收文档记录其当时提交，不自动构成当前实现或当前测试通过的证据。

## 依赖方向

Flutter 页面通过 AppDependencies 调用 Dart InteropBridge；后者通过 FRB
进入 Rust Runtime，Runtime 调用独立 interop-adb。设计系统不依赖互联业务。
主控系统能力通过平台适配实现；被控设备的临时 JAR/helper 集中在 servers。
媒体字节通过本机流传输交给播放器，不在 JSON 事件通道中逐帧复制。

Flutter应用直接位于仓库根目录，`lib/`、`test/`、`integration_test/`和各平台runner平铺；
独立的packages、crates、servers、third_party、tool仍按职责保留。
Flutter pages 下每页独立目录，私有绘制组件就近放置；共享 services、widgets、
router 保持浅层。新目录应对应独立职责或构建目标。

## 状态和资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| Rust Runtime | 初始化、持久身份、跨模块协调与命令分发 |
| ConnectionOwner | 已准入连接、每设备转换栅栏、去重的在途清理 |
| ActivityOwner / activities | 会话、音源、传输活动容器与准入；统一活动引用、投影和停止 |
| 领域实现 | 会话、传输、音源各自的协议流程和资源释放 |
| Dart InteropBridge | 核心观察者与本机输出协调；不拥有被控设备的授权身份 |
| RuntimeInitialization | 复用进程 FRB 绑定；界面桥接重新附着不能更换身份目录 |
| bootstrapApplication | 在配置全部完成前拥有桥接，失败等待释放，成功交付给 ProviderScope |
| AppController | 应用级状态投影与订阅，不拥有 ADB socket |
| RemotePresentation | 单个远控路由的绑定、输入许可、恢复/可见性/启动结果转换 |
| SessionViews | 页面对持久控制会话的可见性租约与替代视图协调 |
| PortableVideo/AudioOutputs | 本机播放器、呈现回执与释放 |
| Android ProcessFlutterHost | 进程 FlutterEngine 与通道；Activity 只提供当下 UI/授权 |

慢设备清理在独立任务中进行；同一设备仍受转换栅栏约束，不能让旧清理释放新连接
或让重连覆盖尚未发布的离线结果。进程死亡会终止内存活动；Activity 重建与进程
恢复是不同的验证范围。

## 契约

`protocol/commands.json` 生成 Dart/Rust 命令枚举、字段形状和核验策略。
统一 codec 负责版本、UTF-8 请求限额、命令和结果信封；领域实现继续负责权限、
范围、默认值及 generation。保留 String/JSON 调用兼容入口和可扩展字段，新增
typed execute 入口。此轮没有把所有动态业务 payload 转为静态 DTO。

Device 的 TransportKind 明确区分 tcp、wireless、tls、usb，保存、导出和恢复使用
同一组值。底层 TLS 适配将明确的授权拒绝映射为结构化错误，产品策略不再解析
底层展示文本。

## 生成与交付

- `tool/protocol_codegen.py --check`：共享命令契约生成结果。
- `tool/generate.py --check`：官方DESIGN.md解析模型生成Dart token并比较；临时隔离目录中真实生成并比对FRB，检查Dart builder输出。
- `servers/companion/build.py --check`：临时重建 Java/DEX/JAR，检查源码、构建输入与产物清单。
- helper 的 Rust 默认测试：源码、lockfile、脚本和四 ABI 产物摘要。
- fvp 的 MDK 正式版本与平台摘要：`third_party/fvp/cmake/mdk-release.json`。
- `tool/check.sh --android`：默认工程检查与实际三 ABI Android APK 验证。
- `tool/build_host.py`：iOS、macOS、Windows 宿主整包及打包库检查，由相应 CI 宿主执行。

四端 CI 配置存在不等于本轮远程作业已通过。平台功能支持状态、真机/OEM、媒体
性能、后台回收及生产密码提供器需要各自证据；本次结构重构不替代这些验收。

根目录迁移、官方DESIGN.md解析生成与保留fvp副本的依据见[工具链实施](repository-tooling.md)。

## 后续维护

新增活动时更新其领域实现，并在 activities 的统一投影和停止入口集成；避免再
把全局活动列表放回 scrcpy 或设置实现。ActivityOwner 内部仍由各领域实现管理
具体容器，未来进一步私有化应以真实修改扩散或并发问题为依据。

新增远控状态转换时通过 RemotePresentation 的方法更新，并通过现有页面生命周期
回归验证，避免在页面重建平行的布尔状态。新增命令先更新共享契约；生成物不得
手改。变更原生依赖或临时执行产物时更新其清单并执行新鲜度检查。

## 本批验证快照

2026-10-18，本批工作区的 `./tool/check.sh --android` 实际退出 0：

- Rust 工作区 296 passed、0 failed、68 ignored；忽略项仍需要其声明的设备或外部环境。
- 应用 Flutter 测试 299 项、桥接 130 项、设计系统 3 项全部通过。
- 严格分析、Clippy、格式、共享契约与 FRB 生成检查、companion 临时真实重建通过。
- 工具回归 8 项、CMake 依赖回归 3 项、原生 snapshot 接缝与驱动验收契约通过。
- 实际三 ABI debug APK 构建、签名、16KB ZIP 对齐、包内 Flutter/Rust ELF、manifest
  及 Kotlin 所有权/音频契约检查通过。构建耗时约 251 秒。

真实主机测试覆盖桥接初始化后目录准备失败、释放等待、同目录重试、FRB 绑定复用
及并发不同目录拒绝。它不运行被控设备活动，也不作为 Android/OEM 或播放质量证据。
设计 lint 为 0 errors、31 warnings、1 info；保留提示，不称视觉目标已经完成。
其他三个宿主整包 CI 已配置，本轮未远程执行；未新增物理设备验收。
