# 架构

## 模块位置与接口

| 位置 | 职责 |
| --- | --- |
| `app/lib/application/` | 业务组装、命令分派、事件与快照；`transport/` 定义应用请求 |
| `app/lib/connection/` | 设备记录、身份、配对、连接准入、健康检测与重连 |
| `app/lib/companion/` | 临时服务部署、RPC与观察意图 |
| `app/lib/files/` | 目录/搜索/图库快照、变更、传输日志与系统交付 |
| `app/lib/media/` | 逻辑窗口、捕获、本机输出、声音租约、输入及缓存 |
| `app/lib/preferences/`、`platform/` | 偏好持久化与本机系统适配 |
| `app/lib/pages/`、`router/`、`presentation/` | 页面、typed route及展示；业务模块不依赖页面或路由 |
| `packages/` | 通用设计系统、ADB、scrcpy和媒体解码；公开Dart接口，隐藏FRB与生成物 |
| `rust/<package>/` | 对应能力包的协议、原生资源与媒体执行 |
| `servers/` | 被控临时执行产物 |

能力包以 `lib/<包名>.dart` 为主入口，手写实现归 `lib/src/`，原生绑定归 `lib/src/native/`，Dart生成物归所属模块的 `generated/`。构建辅助归 `tool/`（含 `tool/cmake/`），Dart及工具测试归 `test/`；原生测试留在对应原生模块的 `tests/`。`hook/`、`native/` 和平台目录按实际能力保留，不创建空目录对齐。

`ApplicationSession` 组装所有者，分派器只适配命令。跨包使用公开接口；共享ADB连接使用同库宿主，句柄不能跨动态库。依赖由 `tool/check_architecture.dart` 检查。决定见[ADR](../adr/)，页面约定见[导航](flutter-navigation.md)。

## 状态与资源所有权

- 应用拥有设备、用户意图与持久记录；能力包拥有连接、流、捕获、FD及执行回执。
- 同设备连接转换串行，其他设备独立推进。停止先撤销准入，再等待原活动、SDK资源和平台租约依次释放。
- 取消是请求，超时只结束等待。确认退出前，原所有者保留精确句柄和重试权；迟到回执按原身份及代次处理。
- 连接、捕获、观察者、页面租约和播放器分别关闭。清空页面或快照不代表资源已释放。
- 远端等待在登记锁外执行。清理重试只处理未完成阶段；执行结果未知时保留记录，不重放副作用。
- isolate恢复先认领原生资源并排空旧任务，再建立业务状态。关闭权来自当前租约，不从PID、地址或磁盘记录推导。

## 连接与显示

`DeviceCoordinator` 组合设备业务，`ConnectionOwner` 持有每设备连接及清理责任。候选通过身份核验和持久提交后才替换原端点；未交付失败先补偿本次配置。

无线发现只提供候选，接纳前核对真实GUID及发现代次；配对端口与连接端口分别使用。授权拒绝停止自动重连，不降级明文。USB平台租约保持到SDK实际断开；Activity/引擎更替先排空旧SDK任务，再释放原始描述符。

`DeviceHealthCoordinator` 解释入站活动和OPEN探针。只有OPEN已写出且之后无入站进展的响应超时才累计沉默；本机排队或容量失败不算对端失活。

`PhysicalDisplayLease` 随逻辑手机窗口保持；`PhysicalDisplayRecovery` 在连接交付前恢复遗留覆盖。修改前保存原状态和owner，停止捕获及尺寸worker后按原owner恢复并读回；确认前不交给后继窗口，未知修改不猜测恢复成功。

## 恢复、持久化与媒体

`StateRecovery` 合并事件缺口核验；快照只读取现有状态，不建立连接或捕获。核验期间阻止新副作用，允许读取、释放输入、取消与停止。水位一致后恢复准入，视频帧遥测不推进业务版本。

设备记录、偏好、应用打开与传输各有唯一账本写入者，串行刷新后原子提交；损坏或较新格式保留原文件并报错。`AppLaunchStore` 在START_APP前持久化操作身份，pending/observed重建为unknown，同设备同包未决时禁止再打开。检查或关闭匹配本次操作UUID，不强停真实应用任务。

文件模块由 `FileCatalog`、`FileMutationCoordinator`、`TransferCoordinator` 分别拥有快照、变更和传输。批次固定原连接；停止等待准备、worker、句柄与预算收尾。finalizing或提交回执丢失保留result_unknown，清理成功不等于提交成功，移除历史不删除文件。

`AppMediaCache` 只清理登记的预览及出站原件树。活动读写、未决交付及外部应用可能仍在读取的来源保持保护；文档与分享各持来源账本，完整传输引用核对后才能回收，见[系统交付](content-delivery.md)。

视频路径为Rust scrcpy packet source → Rust媒体核心 → 裁剪FFmpeg → 平台纹理；PCM直接进入平台输出，媒体字节不经Dart JSON。捕获与播放器分别关闭。画质重建保留逻辑session和真实应用task，只替换捕获，旧捕获/renderer代次的输入与回执失效。

`RemotePresentation` 管理窗口绑定与恢复，`RemoteInputOwner` 管理输入及持键。页面声音租约归 `DeviceAudioViewCoordinator`，同设备共用 `DeviceAudioSourceCoordinator` 的音源。官方JAR的暂停只停止本机呈现，capturePaused=false；恢复通过RESET_VIDEO取新画面。

## 本机集成

Android连接与音频前台服务分别持有通知和资源。系统停止保留停止意图，用户明确恢复后才重新准入。`SystemNotificationCoordinator` 持有本机提醒，点击重验当前设备和观察代次；重连与核验快照形成安静基线。

进程级 `DiagnosticLog` 使用白名单字段及加盐标识，保存有界JSONL，不记录私钥、命令参数或异常正文。main初始化日志与GlassMaterial后启动应用；材质与辅助偏好按[视觉规范](../../designs/design.md)实现。
