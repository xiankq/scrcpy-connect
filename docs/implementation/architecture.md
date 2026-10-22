# 当前实现职责

本文维护实现依赖、资源所有权与恢复边界。领域用语见[词表](../../GLOSSARY.md)，架构取舍见[ADR](../adr/)，产品行为见[产品规格](../../designs/prod/README.md)，验证结果见[验收记录](validation.md)。

## 依赖方向

Flutter 页面通过 `AppDependencies` 调用 Dart `InteropBridge`，经 FRB 进入 Rust `Runtime`，再由独立 `interop-adb` 连接 adbd。设计系统不依赖互联业务；Android/iOS/macOS/Windows 的系统能力由各自适配层实现。媒体字节走本机流，不复制到 JSON 事件通道。

`interop-adb` 拥有 transport、认证、service、shell、sync、forward 与发现协议，不定义产品重连或默认超时。Dart `ConnectionPolicy` 区分产品编排与原生执行参数；同一进程重新附着必须使用相同配置。`ConnectionSetupCoordinator` 编排配对、USB、转 IP 与取消，`ReconnectionCoordinator` 拥有自动重连计时和前后台决策。USB 离线后等待新的系统授权。

产品默认值由 Dart `applicationSettings` 注入；独立 Runtime 使用空设置。`VideoQualityPolicy` 合并设备偏好，`DeviceQualityCoordinator` 串行保存、重建和逐窗结果，`VirtualDisplayPolicy` 计算等比虚拟尺寸。`DeviceCapabilityPolicy` 把原始探测事实转成产品状态；Rust 只验证可执行条件。

Flutter 位于 `app/`；`packages/` 提供设计系统和 Dart/Rust 桥接；`crates/` 提供 Rust 领域实现；`servers/` 保存被控执行产物；`protocol/` 是命令契约来源。Dart workspace 共用根锁文件和 `.dart_tool`，页面布局与路由规则见[导航契约](flutter-navigation.md)。

## 状态与资源所有权

| 模块 | 拥有的状态与责任 |
| --- | --- |
| Rust Runtime | 初始化、持久授权身份、模块协调、命令分发与快照栅栏 |
| ConnectionOwner | 已准入连接、每设备转换栅栏、去重的在途清理 |
| ActivityOwner | 会话、音源、传输活动的准入、引用、投影与停止 |
| KeepActiveOwner | 同设备仍开画面的保活意图、独立控制服务及按连接/PID 核验的释放 |
| TransferStore | 传输检查点、任务日志、持久化屏障与恢复校验 |
| interop-adb writer | 普通/优先队列、单流顺序、ACK、burst credit 与有序关闭 |
| VideoTransport | 本机中转、源 PTS 偏移检测、换段、有界写入与实时 GOP 上限 |
| Dart InteropBridge | 核心观察者、本机输出协调和启动重新附着 |
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

`TransferStore` 以版本化 `transfers.json` 检查点加连续序号 journal 保存任务。检查点先同步文件、原子替换并同步目录，再截断日志；损坏或截断日志拒绝猜测恢复。`finalizing` 在重启后保持 `result_unknown`，未知写入不自动重放。

画面质量重建保留逻辑 `sessionId` 和真实应用 task，只替换捕获进程与虚拟 display。`captureGeneration` 标识捕获所有者，renderer generation 标识同捕获内输出；旧 generation 的迟到 ready、输入和尺寸结果必须失效。重建期间撤销旧输入绑定，只允许释放按键、指针和明确关闭。

当前官方 scrcpy JAR 不提供协作捕获暂停。页面暂停保留会话并停止本地呈现，`capturePaused=false`，恢复通过 `RESET_VIDEO` 取得新画面。旧扩展 JAR 的暂停回执不适用于此路径。

后台由 `ApplicationBackgroundPolicy` 在应用进入时按偏好请求。Android 连接 FGS 与音频播放 FGS 分别拥有通知和资源；没有画面不停止连接服务。系统 Task Manager stop 持久化为停止状态，只有用户明确操作才能重新准入，后台恢复不自动创建画面或声音。

## 契约与生成

`protocol/commands.json` 生成 Dart/Rust 命令枚举、字段形状和核验策略。统一 codec 负责版本、UTF-8 限额、信封和范围；执行层负责权限与 generation。新增活动通过 activities 投影和停止，新增远控转换通过 `RemotePresentation`，页面不另建平行状态。

`TransportKind` 在保存、导出和恢复中区分 tcp、wireless、tls、usb。TLS 授权拒绝保留结构化错误，产品策略不解析展示文本。生成文件与来源一并维护，修改来源后重新生成。

共享播放器使用 pub.dev 原版 `fvp: 0.39.1`，不维护本地 fork。MDK 的实际来源、版本和下载行为由该发布包的平台构建文件决定。Bridge 通过原生有界回读处理普通快照，逐帧诊断按需开启；不调用上游未判空的 `MdkSnapshot`。

## 材质启动与渲染

`app/lib/main.dart` 先初始化 `GlassMaterial`，再启动 `bootstrapApplication`。支持 shader 时使用 premium 光学路径，不支持时使用明确的磨砂回退；降低透明度、高对比或实体偏好移除光学与模糊，减少动态效果关闭弹性位移。

页面直接使用库的 `GlassIconButton`、`GlassTabBar.bottom` 和 `GlassMenu`。浅色 premium 底栏由 `NavigationSelectionLens` 组合 regular 轨道、静止镜片和官方前景栏；暗色、辅助偏好与不支持 premium 的分支保留官方轨道和选中面。该组合依赖锁定版本的零光学快速路径，升级库时需重新核对。

普通材料通过局部 `GlassSurfaceGroup` 共享背景采样，不跨 Navigator。固定设置行使用实体 `ContentPanel`/`SettingsGroup`，动态文件、通知和任务列表保持开放内容流。`PageFrame` 把页头和底栏延伸到透明背景之上，滚动内容通过 `PageChromePadding` 消费避让；对话框、抽屉、菜单和提示统一经设计系统入口创建。

## 平台交付边界

仓库不配置自动 CI/CD。`tool/check.sh` 执行主机检查，`tool/check.sh --android` 额外核验三 ABI APK；`tool/build_host.dart` 手动构建对应宿主。整包编译、协议夹具、模拟器和物理设备运行是不同证据，详见[验收记录](validation.md)。
