# 当前目录与模块职责

本文记录实现的依赖方向与资源所有权。领域用语见根目录 [GLOSSARY.md](../../GLOSSARY.md)，架构决定见 [ADR](../adr/)，产品行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准。
当前产品修订的验证边界见 [产品验收记录](product-refinement.md)；文末及其他验收记录中的历史结果只适用于各自注明的阶段。

## 依赖方向与目录

Flutter 页面通过 `AppDependencies` 调用 Dart `InteropBridge`，经 FRB 进入 Rust `Runtime`，再调用独立 `interop-adb`。设计系统不依赖互联业务。主控系统能力由平台适配实现；被控设备临时 JAR/helper 集中在 `servers/`。媒体字节通过本机流交给播放器，不在 JSON 事件通道逐帧复制。

被控兼容按 ADB feature、系统接口与实际权限分别判断，不能把音频或独立应用窗口的下限施加到基础连接与整机远控。无宽元数据／目录协议的设备使用同一个临时原生文件服务；旧 shell 的未知退出码不能作为文件变更成功证据。固定服务端、部署授权、资源回收及当前验证范围见[被控兼容边界](android-target-compatibility.md)。

Flutter 应用位于仓库根目录：`lib/`、`test/`、`integration_test/` 与平台 runner 共用根 `pubspec.yaml`。`packages/`、`crates/`、`servers/`、`third_party/`、`tool/` 保留各自构建职责。页面独立放在 `lib/pages/<page_name>/`，私有组件就近存放；共享服务、组件和路由使用 `services/`、`widgets/`、`router/`。路由生命周期见 [Flutter 页面与路由](flutter-navigation.md)。

## 状态和资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| Rust Runtime | 初始化、持久授权身份、跨模块协调与命令分发 |
| ConnectionOwner | 已准入连接、每设备转换栅栏、去重的在途清理 |
| ActivityOwner / activities | 会话、音源、传输活动的准入、引用、统一投影与停止 |
| 领域实现 | 各类活动的协议流程、具体容器与资源释放 |
| Dart InteropBridge | 核心观察者与本机输出协调；授权身份属于 Rust 持久存储 |
| RuntimeInitialization | 复用进程 FRB 绑定；界面重新附着保持原身份目录 |
| bootstrapApplication | 配置完成前持有 bridge；失败等待释放，成功交给 ProviderScope |
| AppController | 应用级不可变状态投影、订阅和打开页面的设备音源租约 |
| RemotePresentation | 单个远控路由的会话绑定、输入许可、可见性、恢复及启动结果 |
| SessionViews | 页面对持久控制会话的呈现租约与替代视图协调 |
| PortableVideo/AudioOutputs | 本机播放器、呈现回执与释放 |
| Android ProcessFlutterHost | 进程 FlutterEngine 与通道；Activity 提供当下 UI/授权 |

慢设备清理在独立任务进行；同一设备仍受转换栅栏约束。旧清理不能释放新连接，重连不能覆盖尚未发布的离线结果。Activity 重建与进程死亡分别验收；后者终止内存活动。

远控页面租约、控制会话和设备连接具有不同生命周期。AppController 按设备合并页面租约；最后一个页面释放时立即撤销该设备声音启动意图，并精确停止对应音源。保留会话或保持连接不产生页面租约。剪贴板协调器拥有前台同步代次，设备偏好与可见页面焦点决定对象；切换后旧轮询、系统读回及远端事件失效。具体用户行为统一见交互规则。

## 契约与生成

`protocol/commands.json` 生成 Dart/Rust 命令枚举、字段形状和核验策略。统一 codec 负责版本、UTF-8 请求限额、命令和结果信封；领域实现负责权限、范围、默认值及 generation。保留 String/JSON 兼容入口与 typed execute 入口，动态业务 payload 尚未全部变为静态 DTO。

`TransportKind` 在保存、导出与恢复中区分 tcp、wireless、tls、usb。TLS 的明确授权拒绝映射为结构化错误，产品策略不解析展示文本。新增活动通过 activities 统一投影和停止；新增远控转换由 RemotePresentation 协调，页面不另建平行恢复状态。

生成文件与来源一起维护，修改来源后重新生成。共享命令、FRB、Dart builder 和 companion 源码/产物检查由 `tool/check.sh` 汇总；视觉 token 的官方解析与自有 Dart emitter、fvp 受控副本边界见 [工具链契约](repository-tooling.md)。

## 材质启动与渲染

`lib/main.dart` 在启动 `try` 内先等待 `GlassMaterial.initialize()`，再调用 `bootstrapApplication()`；支持 shader 的后端加载失败进入启动错误页。材质只有 `liquid_glass_easy` 的一个 lens 引擎。后端实际支持 `ImageFilter` shader 时使用 lens，不支持时使用磨砂回退；降低透明度、高对比或显式实体面使用不透明内容并移除过滤器。减少动态效果另行关闭触摸形变。

lens 拥有轮廓与子内容裁剪，外层不叠加径向保护遮罩或固定白边。Pencil 的 GLSL 只表达静态设计目标，不是 Flutter 渲染实现或 Apple 原生像素等效证明。光学数值来自生成 token，产品布局依据父约束而非整屏缩放。真实 shader、回退及无障碍路径的证据边界见产品验收记录。

## 平台交付边界

`tool/check.sh --android` 覆盖工程检查与三 ABI Android APK；`tool/build_host.py` 由对应宿主执行 iOS、macOS、Windows 整包及库检查。CI 配置存在不代表作业通过；平台功能支持、物理设备/OEM、媒体性能、后台回收和生产密码提供器分别留证。

## 2026-10-18 验证快照（历史）

2026-10-18，该阶段工作区的 `./tool/check.sh --android` 实际退出 0：

- Rust 工作区 296 passed、0 failed、68 ignored；忽略项仍需要其声明的设备或外部环境。
- 应用 Flutter 测试 299 项、桥接 130 项、设计系统 3 项全部通过。
- 严格分析、Clippy、格式、共享契约与 FRB 生成检查、companion 临时真实重建通过。
- 工具回归 8 项、CMake 依赖回归 3 项、原生 snapshot 接缝与驱动验收契约通过。
- 实际三 ABI debug APK 构建、签名、16KB ZIP 对齐、包内 Flutter/Rust ELF、manifest
  及 Kotlin 所有权/音频契约检查通过。构建耗时约 251 秒。

真实主机测试覆盖桥接初始化后目录准备失败、释放等待、同目录重试、FRB 绑定复用
及并发不同目录拒绝。它不运行被控设备活动，也不作为 Android/OEM 或播放质量证据。
设计 lint 为 0 errors、31 warnings、1 info；保留提示，不称视觉目标已经完成。
其他三个宿主整包 CI 已配置，该阶段未远程执行；未新增物理设备验收。
