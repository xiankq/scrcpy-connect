# 当前实现职责

本文维护实现依赖、资源所有权与恢复边界。领域用语见[词表](../../GLOSSARY.md)，架构取舍见[ADR](../adr/)，产品行为见[产品规格](../../designs/prod/README.md)，验证结果见[验收记录](validation.md)。

## 依赖方向

Flutter 页面通过 `AppDependencies` 调用 Dart `DeviceRuntime`。它组装 `device_connections`、`device_preferences`、`device_files`、`scrcpy_client` 和 `runtime_diagnostics`；各包拥有自己的规则与状态。`device_protocol` 提供控制契约。FRB 只连接需要原生执行的能力。设计系统不依赖设备业务，媒体字节不进入 Dart JSON。

`flutter_adb` 提供统一 ADB 调用与受控进程生命周期。Android/iOS 使用 `interop-adb`，桌面使用随包分发的官方 platform-tools，通过私有 adb-server 的 smart socket 执行；不接管用户已有的服务器。原生传输不定义产品重连策略。Dart `ConnectionPolicy` 区分产品编排与原生执行参数；同一进程重新附着必须使用相同配置。`ConnectionSetupCoordinator` 编排配对、USB、转 IP 与取消，`ReconnectionCoordinator` 拥有自动重连计时和前后台决策。USB 离线后等待新的系统授权。

`device_preferences` 拥有产品默认值、迁移、校验、revision 与 `preferences.json` 原子保存。Rust 只接收执行所需的设置镜像，不保存用户偏好。`VideoQualityPolicy` 合并设备偏好，`DeviceQualityCoordinator` 串行保存、重建和逐窗结果，`VirtualDisplayPolicy` 计算等比虚拟尺寸。`DeviceCapabilityPolicy` 把原始探测事实转成产品状态；Rust 验证可执行条件。

Flutter 位于 `app/`；`packages/` 提供设计系统和 Dart/Rust 桥接；`crates/` 提供 Rust 领域实现；`servers/` 保存被控执行产物；`protocol/` 是命令契约来源。Dart workspace 共用根锁文件和 `.dart_tool`，页面布局与路由规则见[导航契约](flutter-navigation.md)。

## 状态与资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| Rust Runtime | 初始化、持久授权身份、模块协调、命令分发与快照栅栏 |
| ConnectionOwner | 已准入连接、每设备转换栅栏、去重的在途清理 |
| ActivityOwner | 原生会话与音源的准入、引用、投影与停止 |
| KeepActiveOwner | 同设备仍开画面的保活意图、独立控制服务及按连接/PID 核验的释放 |
| device_files / RemoteFiles | 浏览、搜索、图库快照、传输编排、持久任务日志与恢复校验 |
| NativeFileExecutor | 文件事实查询、字节传输、原子提交与资源租约 |
| interop-adb writer | 普通/优先队列、单流顺序、ACK、burst credit 与有序关闭 |
| VideoTransport | 本机中转、源 PTS 偏移检测、换段、有界写入与实时 GOP 上限 |
| Dart DeviceRuntime | 能力组装、核心观察者、本机输出协调和启动重新附着 |
| device_preferences | 偏好校验、迁移、冲突检测与原子持久化 |
| flutter_adb | 统一 ADB 调用、移动端适配与桌面私有官方服务器 |
| media_codec | 裁剪 FFmpeg 解码、帧与 PCM 输出、Flutter 组件 |
| AppController | 应用级不可变状态、可见页面焦点、页面与设备音源租约 |
| RemotePresentation | 单窗口的会话绑定、输入许可、可见性、恢复与启动结果 |
| RemoteInputQueue | Dart 单页串行输入与每触点最新 move；Rust 负责有界录取、批写和失败撤销 |
| SessionViews / Media outputs | 未关闭窗口租约、精确关闭、播放器回执与释放 |
| Android ProcessFlutterHost | 进程 FlutterEngine、Activity 与当下系统授权 |

同一 Client 上的流与设备连接分别拥有生命周期；活动、页面租约和播放器也不能互相代替。旧清理、旧回执和旧连接结果不得作用于新连接。`connectionId` 只标识当前存活连接，不持久化。

## 连接与屏幕

连接快照由 Runtime 栅栏发布。`DeviceScreenCoordinator` 只核对连接基线，连接、断开、重连和重新附着都不触发屏幕动作。每个明确新建的远控窗口至多尝试一次唤醒；`DeviceScreenPolicy` 按同设备整机与独立窗口计数，只有主动关闭最后窗口才按偏好锁屏。后台、遮挡、短断线和重新附着不触发唤醒或锁屏。

保持唤醒独立于点亮/锁屏，使用固定 scrcpy 的 control-only 服务。最后窗口关闭、偏好禁用或断线时取消该设备服务；回收必须核对原连接以及 PID、starttime 和 nice-name。没有打开窗口时，保持连接不产生页面或声音租约。

Runtime 持有默认全局授权身份和设备专属身份。替换身份只失效使用该身份的连接、活动与在途准入；私钥不进入普通设置、快照或事件。设备已有绑定身份只读，候选配置在同一目标握手成功前不替换原端点。

可选设备数据由 Runtime 有界查询并携带采集时间。结果只更新同一存活连接；离线或过期数据不冒充实时值。电量、充电和未知状态分别判断。

## 恢复、持久化与媒体

`device_files` 以版本化、连续序号的任务日志保存传输，串行刷新后才进入下一执行阶段；压缩时先刷新临时文件，再原子替换。旧 Rust 检查点和 journal 只作为迁移输入，成功迁移前不删除。损坏、截断或代际倒退拒绝猜测恢复。`finalizing` 与取消未确认的任务在重启后保留 `result_unknown`，未知写入不自动重放。原生执行层仅提供事实、字节 I/O、原子提交和租约，不再拥有平行任务状态。

画面质量重建保留逻辑 `sessionId` 和真实应用 task，只替换捕获进程与虚拟 display。`captureGeneration` 标识捕获所有者，renderer generation 标识同捕获内输出；旧 generation 的迟到 ready、输入和尺寸结果必须失效。重建期间撤销旧输入绑定，只允许释放按键、指针和明确关闭。

当前官方 scrcpy JAR 不提供协作捕获暂停。页面暂停保留会话并停止本地呈现，`capturePaused=false`，恢复通过 `RESET_VIDEO` 取得新画面。旧扩展 JAR 的暂停回执不适用于此路径。

后台由 `ApplicationBackgroundPolicy` 在应用进入时按偏好请求。Android 连接 FGS 与音频播放 FGS 分别拥有通知和资源；没有画面不停止连接服务。系统 Task Manager stop 持久化为停止状态，只有用户明确操作才能重新准入，后台恢复不自动创建画面或声音。

## 契约与生成

`protocol/commands.json` 生成 Dart/Rust 命令枚举、字段形状和核验策略。统一 codec 负责版本、UTF-8 限额、信封和范围；执行层负责权限与 generation。新增活动通过 activities 投影和停止，新增远控转换通过 `RemotePresentation`，页面不另建平行状态。

`TransportKind` 在保存、导出和恢复中区分 tcp、wireless、tls、usb。TLS 授权拒绝保留结构化错误，产品策略不解析展示文本。生成文件与来源一并维护，修改来源后重新生成。

`scrcpy_client` 负责会话呈现规则，`media_codec` 负责解码与平台输出。Rust scrcpy 读取器通过有界 packet-source ABI 交出原始压缩包，Rust 媒体核心直接调用裁剪 FFmpeg；没有 Matroska 封装或 HTTP 中转。Dart 只持有控制、状态和 Flutter Texture。FFmpeg 只包含远控视频解码、必要 parser/bitstream filter、像素转换与平台硬解接口；AV1 以静态 libdav1d 提供软件回退。声音协商为 PCM，直接进入平台输出。

Android 使用 MediaCodec，Windows 使用 D3D11VA，Linux 使用 VAAPI/NVDEC，Apple 使用 VideoToolbox；实际后端、硬件帧和回退由运行状态报告。平台接口可用不代表特定设备已验证，MediaCodec 名称也不能单独证明物理硬解。压缩包的所有权交接与解码后 GPU 帧的共享分别核验，不把整条链路概称为零拷贝。选择理由见 [ADR 0007](../adr/0007-capability-packages-and-native-media.md)。

媒体 source ABI v2 移交含解码 padding 的独占包存储，通过容量通知恢复背压生产者；旧借用 ABI 保留兼容复制。解码完成、平台纹理准备和 Flutter 最终显示分别取证，启动不强制 GPU 回读。PCM 以设备已播/排队水位调节采样漂移，部分写入保留尾部，暂停和输出释放由音频 worker 串行执行。

### 本机运行日志

应用进程持有唯一 `DiagnosticLog`，bootstrap 将其注入 Bridge 与音视频输出；provider 重建和启动重试沿用同一写入队列。结构化 `DiagnosticReporter` 只转写命令标识、错误码、耗时、代际、释放回执与解码后端等白名单字段，设备和会话标识经每进程随机盐散列；不重定向原生自由文本日志，也不保存参数、异常正文或堆栈。设置页读取最近记录并手动导出 JSONL。

日志位于应用支持目录 `diagnostics/`，四份文件各至多 512 KiB，内存最近 300 条、待写队列 256 条，溢出记录丢弃数量。文件 IO 串行，正常批次延迟至多约 250 ms 发起写入，错误与退出前台主动请求 flush；崩溃或系统强杀仍可能损失未落盘记录。重启跳过损坏行并截断当前文件的不完整尾行，存储失败保留有界内存记录且不阻断播放。产品行为见[设置与本地数据](../../designs/prod/information-architecture.md#设置与本地数据)。

## 材质启动与渲染

`app/lib/main.dart` 先创建进程级 `DiagnosticLog`，再初始化 `GlassMaterial` 并启动 `bootstrapApplication`。支持 shader 时使用 premium 光学路径，不支持时使用明确的磨砂回退；降低透明度、高对比或实体偏好移除光学与模糊，减少动态效果关闭弹性位移。

页面直接使用库的 `GlassIconButton`、`GlassTabBar.bottom` 和 `GlassMenu`。浅色 premium 底栏由 `NavigationSelectionLens` 组合 regular 轨道、静止镜片和官方前景栏；暗色、辅助偏好与不支持 premium 的分支保留官方轨道和选中面。该组合依赖锁定版本的零光学快速路径，升级库时需重新核对。

普通材料通过局部 `GlassSurfaceGroup` 共享背景采样，不跨 Navigator。固定设置行使用实体 `ContentPanel`/`SettingsGroup`，动态文件、通知和任务列表保持开放内容流。`PageFrame` 把页头和底栏延伸到透明背景之上，滚动内容通过 `PageChromePadding` 消费避让；对话框、抽屉、菜单和提示统一经设计系统入口创建。

## 平台交付边界

仓库不配置自动 CI/CD。`tool/check.sh` 执行主机检查，`tool/check.sh --android` 额外核验三 ABI APK；`tool/build_host.dart` 手动构建对应宿主。整包编译、协议夹具、模拟器和物理设备运行是不同证据，详见[验收记录](validation.md)。
