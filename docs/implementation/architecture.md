# 当前目录与模块职责

本文记录实现的依赖方向与资源所有权。领域用语见根目录 [GLOSSARY.md](../../GLOSSARY.md)，架构决定见 [ADR](../adr/)，产品行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准。
当前产品修订的验证边界见 [产品验收记录](product-refinement.md)；文末及其他验收记录中的历史结果只适用于各自注明的阶段。

## 依赖方向与目录

Flutter 页面通过 `AppDependencies` 调用 Dart `InteropBridge`，经 FRB 进入 Rust `Runtime`，再调用独立 `interop-adb`。设计系统不依赖互联业务。主控系统能力由平台适配实现；被控设备临时 JAR/helper 集中在 `servers/`。媒体字节通过本机流交给播放器，不在 JSON 事件通道逐帧复制。

被控兼容按 ADB feature、系统接口与实际权限分别判断，不能把音频或独立应用窗口的下限施加到基础连接与整机远控。无宽元数据／目录协议的设备使用同一个临时原生文件服务；旧 shell 的未知退出码不能作为文件变更成功证据。固定服务端、部署授权、资源回收及当前验证范围见[被控兼容边界](android-target-compatibility.md)。

被控执行产物在 Android 安装包中由三种主控架构共享，Flutter 宿主准备私有资源缓存，Rust 校验后持有不可变原始字节并负责远端部署；其他宿主和独立 Rust 保留压缩内置资源。生成链、摘要与缓存规则见[共享打包](repository-tooling.md#被控执行产物的共享打包)。被控 ABI 与主控 ABI 独立。

Flutter 应用位于 `app/`：`app/lib/`、`app/test/`、`app/integration_test/` 与平台 runner 共用 `app/pubspec.yaml`。根 `pubspec.yaml` 声明 Dart workspace 与仓库工具依赖，统一解析使用根 `pubspec.lock` 和 `.dart_tool`。`packages/`、`crates/`、`servers/`、`tool/` 保留各自构建职责。页面按业务父子层级放在 `app/lib/pages/`，入口、叶页命名及业务组件归属统一见[页面文件布局](flutter-navigation.md#文件布局)；共享服务、通用组件和路由使用 `services/`、`widgets/`、`router/`。路由生命周期见 [Flutter 页面与路由](flutter-navigation.md)。

## 状态和资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| Rust Runtime | 初始化、持久授权身份、跨模块协调与命令分发 |
| ConnectionOwner | 已准入连接、每设备转换栅栏、去重的在途清理 |
| ActivityOwner / activities | 会话、音源、传输活动的准入、引用、统一投影与停止 |
| TransferStore | 传输检查点、按任务追加日志、持久化屏障与恢复校验 |
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

Runtime 按自身不变的授权身份缓存成功创建的 TLS 配置；连接的加密策略仍单独判断。可选设备信息由 Runtime 拥有的有界队列处理，最多四个查询并行，结果仅能更新同一存活连接；Runtime 释放时取消在途任务并丢弃排队请求。连接准入仍完成必要身份检查。

传输持久状态由 `TransferStore` 统一写入：`transfers.json` 为版本化检查点，`transfers.journal` 为连续序号的任务变更；兼容读取原有数组格式。逐项完成与提交前 `finalizing` 保留持久化屏障，定期按存量阈值压缩日志，不以延迟保存换吞吐。检查点先同步文件、原子替换并同步目录，再截断旧日志；失败或取消中的追加禁止继续复用，损坏或截断日志拒绝猜测恢复。`finalizing` 恢复仍为 `result_unknown`，分享来源只在相关任务持久化后回收。本轮变更及主机验证见 [ADB 性能修复记录](adb-performance-2026-10-19.md)。

远控页面租约、控制会话和设备连接具有不同生命周期。AppController 按设备合并页面租约；最后一个页面释放时立即撤销该设备声音启动意图，并精确停止对应音源。保留会话或保持连接不产生页面租约。剪贴板协调器拥有前台同步代次，设备偏好与可见页面焦点决定对象；切换后旧轮询、系统读回及远端事件失效。具体用户行为统一见交互规则。

## 契约与生成

`protocol/commands.json` 生成 Dart/Rust 命令枚举、字段形状和核验策略。统一 codec 负责版本、UTF-8 请求限额、命令和结果信封；领域实现负责权限、范围、默认值及 generation。保留 String/JSON 兼容入口与 typed execute 入口，动态业务 payload 尚未全部变为静态 DTO。

`TransportKind` 在保存、导出与恢复中区分 tcp、wireless、tls、usb。TLS 的明确授权拒绝映射为结构化错误，产品策略不解析展示文本。新增活动通过 activities 统一投影和停止；新增远控转换由 RemotePresentation 协调，页面不另建平行恢复状态。

生成文件与来源一起维护，修改来源后重新生成。共享命令、FRB、Dart builder 和 companion 源码/产物检查由 `tool/check.sh` 汇总；视觉 token 的官方解析与自有 Dart emitter、社区原版 fvp 的依赖边界见 [工具链契约](repository-tooling.md)。

共享播放器使用 pub.dev 精确版本 `fvp: 0.39.1`，不维护本地 fork 或原生补丁。MDK 的实际来源、版本与下载行为由该发布包的平台构建文件决定；锁定 Dart 包不等于所有平台 MDK 二进制也已锁定。历史本地补丁的 snapshot 接缝与 MDK 固定回归不再是当前门禁，普通宿主产物检查继续保留；原版空结果回调限制见工具链契约。

## 材质启动与渲染

`app/lib/main.dart` 在启动 `try` 内先等待 `GlassMaterial.initialize()`，再调用 `bootstrapApplication()`，生产应用通过 `GlassMaterial.wrap` 接入 `liquid_glass_widgets` 的主题亮度和系统辅助偏好。支持 shader 时初始化失败进入启动错误页；实际支持 `ImageFilter` shader 时使用 premium 光学路径，不支持时使用明确的磨砂回退。降低透明度、高对比或显式实体面使用不透明内容并移除光学与模糊；减少动态效果另行关闭弹性位移。

`Glass` 和工具组保留项目的材料接口。项目不再定义 `GlassIconButton`、`GlassTabBar` 或 `GlassDestination` 组件；页面直接构造库的 `GlassIconButton` 与 `GlassTabBar.bottom`，设计系统只原样导出官方类型并提供 token 配置值。底部导航由官方组件持有拖动、焦点与内部液态镜片，外围不再套整片玻璃或额外裁剪。普通材料与工具组仍在局部 `GlassSurfaceGroup` 中共享背景读取和融合形状，分组不跨 Navigator 或覆盖不同路由。实体内容卡片与列表使用原内容材料。整片材料的厚度、折射率、色散、着色、模糊和光照由生成 token 映射，角度按后端要求转换；`refractionWidth` 用于局部融合距离，不作为厚度的替代值。导航的内部交互镜片保留库的 clear 默认值，不套用整栏 regular 的着色与模糊。官方主题在应用 builder 中统一设置交互 stretch；减少动态效果时为零，按钮公开参数同步关闭缩放与 anchor stretch。透明度/高对比度偏好映射到官方 accessibility scope；实体分支使用 minimal、blur0 与实体色。组件专属尺寸和导航选中色在实际调用点配置，不为转发参数再定义组件类。

光学层拥有轮廓与子内容裁剪，外层不叠加径向保护遮罩或固定白边。Pencil GLSL 是静态设计投影，与 Flutter 渲染分别核对。真实 shader、回退、辅助偏好与动态性能的验证结果见[设计与实现对照](design-fidelity.md)。

`PageFrame` 将视口延伸至透明页头和底部导航背后，`PageChromePadding` 的避让由滚动内容消费；分组列表消费后清空下游作用域，自定义 sliver 使用对应首尾占位，非滚动状态使用 `PageChromeBody`。标题保护由正文 Stack 最后绘制，覆盖完整页头后渐退，不放入前景玻璃组或给 AppBar 添加底色。固定路径或搜索区域与列表通过同一嵌套滚动协调，不另占页头外的固定条带。页头拖动交给仍挂载的正文滚动对象，不能保留已释放的 `ScrollPosition`。

对话框、底部抽屉、菜单和提示统一通过设计系统入口呈现。框架持有路由、焦点、返回结果、键盘和滚动控制器；库的组件持有材料。菜单使用 `GlassMenu`，对话框与 Tooltip 的生产表面使用 `GlassCard` 及独立采样层，保留现有框架布局；库的固定对话框或抽屉布局不能接管项目的键盘避让和业务滚动。抽屉以受约束的垂直圆角透镜承载，避免后端容器内部布局重新接管业务滚动。交互与材质化所需的纹理余量由生成 token 与实际尺寸推导，传给负责采样的局部光学层，不改变命中或内容尺寸。Tooltip 保留框架调度、语义与穿透行为，并以同一显示动画驱动玻璃可见性。工具组、视频控制和退出把手的按压观察器只负责可打断形变和光照，不抢占内部动作与业务拖拽。

通过 OverlayPortal 呈现的菜单和 Tooltip 仍可能继承触发位置的上下文，不能据此复用触发工具组的玻璃平面。它们使用 `GlassSurfaceGroup.isolated` 建立本地光学层与独立背景采样键，采样范围归覆盖层自身；材质化作用域位于该本地层之外，使 shader 可见性随显示动画更新。

现成组件接入、保留适配的原因及本次验证环境见[组件核查记录](glass-components-2026-10-20.md)。

## 平台交付边界

`tool/check.sh --android` 覆盖工程检查与三 ABI Android APK；`tool/build_host.dart` 由对应宿主执行 iOS、macOS、Windows 整包及库检查。CI 配置存在不代表作业通过；平台功能支持、物理设备/OEM、媒体性能、后台回收和生产密码提供器分别留证。

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
