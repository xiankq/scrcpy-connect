# 验证证据与边界

本文件汇总已执行验证的对象、环境和限制，不承担当前产品规则。行为见[产品规格](../../designs/prod/README.md)，资源所有权见[架构](architecture.md)，可重复构建见[工具链契约](repository-tooling.md)。历史结果只适用于注明的版本与配置，不随代码或依赖更新自动继承。

测试收敛后的保留范围、删减依据和复验结果见[测试收敛记录](test-consolidation-2026-10-20.md)；下文历史通过数保持原版本身份。

## 证据层级

| 证据 | 可以说明 | 不能据此说明 |
| --- | --- | --- |
| 静态稿、Pencil 对象扫描 | 组件引用、布局及代表状态 | Flutter 成像、授权互操作或运行性能 |
| Widget 与协议夹具 | 对应界面/协议边界及受控交错 | 目标 Android/OEM 实际支持 |
| Rust 连接实际 adbd | 该目标上的协议、系统接口及资源清理 | 主控 Flutter 完整流程或物理声音输出 |
| 主控与目标 AVD 流程 | 该镜像上的实际界面、编码/解码及系统交接 | 实体 ARM、Wi-Fi 漫游、量产安全或四宿主交付 |
| APK/ELF/签名检查 | 给定构建产物的完整性、架构和签名 | 包含该架构的实机已运行 |

2026-10-17 至 20 日的运行记录主要来自 Ubuntu 24.04 x86_64、Rust 1.99.1、JDK21、Flutter 3.47.6/3.47.7、Dart 3.13.5，以及独立 API36 x86_64 AVD。较旧目标另见[被控兼容证据](android-target-compatibility.md#验证证据)。官方 adb 只用于宿主部署和独立核对，产品连接由 Rust 直接完成。

播放器现为社区原版 fvp 0.39.1；旧本地 snapshot 补丁、固定 MDK、协作暂停捕获 JAR 的测量只能作为历史样本。当前官方 scrcpy JAR 的暂停只停止本地呈现，`capturePaused=false`，恢复通过 `RESET_VIDEO` 重新取得画面。旧“远端捕获已经暂停”的通过记录不证明当前实现有该能力。

## 2026-10-21 累计设计要求实施验收

起点为 `e37cc51`。目标和85项跟踪保存在 `.scratch/design-implementation/`；本次授权实现范围已经落地，并按下列层级完成适用验收；物理设备、OEM与其他宿主的边界保留。

| 范围 | 已执行证据 | 边界／剩余 |
| --- | --- | --- |
| 工程整合 | app全量406项、bridge190项、工具55项、token工具3项及lint通过；全仓fatal-infos分析无问题；Rust workspace404通过／85显式忽略，随后Android锁与paused重建改动有相关52项主机回归及目标实际复验；最终全workspace严格Clippy通过 | 正式生成一致性和394文件格式检查通过；远控五场实际矩阵和双MDK质量组合全部通过，product-06完整UI和普通main最终冷启动／热重载通过，运行错误为空，忽略项不计通过 |
| 连接与身份 | Flutter组合58项、core device18pass/5ignored、身份8项、范围analysis通过；涵盖配置成功再提交、错误目标拒绝、专属四方式attempt、旧身份readonly、IP归属变化 | 物理USB、系统扫码与真实转IP互操作未由这些主机夹具证明 |
| 远控 | 131项远控主机回归、全局密钥20项、画面协调器2项通过；顶部inset回归先失败后通过；新窗wake启动前发送与同session重附着计数有回归 | quality重建输入双代际屏障主机回归已通过。API36双AVD首场实际顶部视频／目标通知栏下拉／远端Back通过；横屏旧纹理拉宽已修布局与输入屏障；租约残留实际定位Android硬链接拒绝，改symlink后正常关闭、强杀迟到写及质量重建后resize实际通过。settings-05整页48独立检查点已通过，含两端横屏新像素、真实后台pause/resume、全部比例恢复和最后关闭锁屏；workspace-04、recovery-01、ime-04、input-01整场通过，涵盖4唯一窗口、同task接续、闭后不复活、中文emoji精确一次和实际HOME输入释放 |
| 应用后台 | API36 emulator-5554 实跑 application_background_test：零设备/画面/音源进入即启连接FGS、显式开关、dispose/同进程重附着；正常main HOME/重入、Task Manager stop及再次进入已核对 | settings-05三次最后关窗的独立dumpsys确认connectedDevice FGS保留且AudioPlaybackService不前台；workspace-04多窗口精确关闭通过；不代表OEM后台长期存活 |
| 后台恢复栅栏 | root15项应用后台／reconnection测试通过：原生stopped回执在首个快照前阻止自动重连，手动恢复仅放行对应设备 | 系统stop后的普通main重入UI真实状态已核对；workspace-04多窗口关闭场景通过 |
| 通知内容 | API36 emulator-5556，独立APK真实BigText/Inbox/MessagingStyle+UID2000产品companion。RED：展开标题误用Collapsed title、Inbox正文空。修后GREEN：标题正文、更新、旧动作失效、源撤回、Binder事件及observation重新附着 | 真实Android合成样式，未宣称第三方消息服务/OEM通过；Rust真实通知端到端及Flutter notifications-02整场通过：创建／更新／撤回各先Binder事件驱动真实页面，再list核对；原应用图标／动作、锁屏不绕过、单清／全清、前台系统提醒与撤回同步，临时PIN／通知／APK清理确认 |
| 通知产物 | companion确定性重建/check、compatibility、shared server package生成通过 | 原Java8编译弃用警告保留；所有可分发产物仍需最终构建核对 |
| 设备数据 | 解析5项；API36 emulator-5556真实Rust读取系统、1080×2400/420dpi/60.000004Hz、电池、内存、内部存储及接口通过；三个只读命令错误connectionId拒绝；断开无旧动态值 | product-06首卡进入只读数据及新时间刷新通过；最终普通main无画面情况下目标BatteryService受控100%充电→37%不充电→恢复100%充电，首卡随周期自动同步，截图与Android回执核对且reset确认 |
| 画面质量／独立密度 | 质量save-only RED后实现当前会话重建；API36 Settings实体411dp、独立原720dp的密度RED，修后不同分辨率均约411dp且保留真实task；实际resize→quality→resize及旧capture迟到拒绝通过 | quality-03真实双MDK通过：paused手机与playing Settings同720→1280重建，保持逻辑ID／task79／paused意图，各新capture／renderer与实际解码一致；未来窗口继承。paused转发首帧超时RED已修，不靠仅保存配置或移除暂停断言 |
| 稳定玻璃与固定选项组 | API36 x86_64主控AVD，最终公开三层组合真实运行，静止、按住、拖动、归位、滚动背景、降透明、减少动态松手/按住共8张捕获及逻辑断言通过；逐图检查静止镜片轮廓可辨、glyph无旧碎字、减少动态按住仅一片镜片；设计系统23项、固定页窄屏大字5项通过，最终导航6项及相关分析通过 | Mesa llvmpipe软件渲染，非物理GPU；最终组合八状态来自独立底栏夹具，另有最终普通main首页与设置稳定选中态实捕；未测连续手感、多视频负载、读屏与性能。详见[10/21后续](glass-components-2026-10-20.md#2026-10-21-静止镜片与固定选项组后续) |

通知实际probe入口：`dart tool/e2e/notification_fixture/build.dart` 后运行
`dart servers/companion/tests/notification-snapshot.dart --adb /home/xiankq/Android/Sdk/platform-tools/adb --serial emulator-5556`。
本轮只在明确隔离AVD安装新夹具，拒绝覆盖既有安装；finally确认移除本run通知、APK、JAR与forward。
原始临时证据 `/tmp/connect-notification-snapshot/initial.json` 与 `android-notifications.txt` 为本轮合成数据，不作为长期规范。

模拟器经 `tool/glass_emulator.dart` 启动host GL，但当前宿主提示硬件GPU不可用；实际渲染记录必须注明软件Mesa等具体后端，不能称物理GPU验收。

### 累计任务的额外复核与纠漏

用户随后要求重新逐项核实并额外视觉对照，本轮发现前述完成结论仍漏掉表单/工作台/主次动作细节及已有窗口的动态保活；已修复并以新版本重新验证，见[复核记录](design-refinement-reaudit-2026-10-21.md)。最终419项应用测试、25项设计系统、60项scrcpy范围、严格分析/Clippy/生成/格式检查通过；6组同尺寸图与另3个状态逐张核对。最新原生冷构建的双AVD保活13检查点再次通过，普通main恢复/热重载及运行错误空值已确认。上方原阶段数量与实际矩阵保留历史身份，不替代本轮纠漏证据。

## 2026-10-21 USB 与系统扫码配对

桌面 USB 入口、无序列号候选选择、Android USB 授权广播遗漏 URI scheme、USB 离线重连及二维码多地址超时已修复。双 API36 AVD 实际通过系统相机扫码、应用自己的 PAKE 配对、自动发现连接端口及加密连接。另以 USB/IP 导入内核软件 USB，实际通过主控系统拒绝／允许、nusb FD 交接、真实被控 adbd 与 shell/sync 探测、拔除重连；普通 release APK 的 USB 工作台正例也通过。环境、红绿回归、清理与未验证范围见[本轮记录](usb-qr-pairing-2026-10-21.md)。这不补齐物理线缆、OTG／厂商 USB HAL、被控 RSA 授权或实体 Wi-Fi 验收。

## 2026-10-20 设备工作台与连接管理

同日后续的屏幕比例、通知、列表与 ADB 调度重构有独立的[验证记录](display-notifications-adb-2026-10-20.md)，不继承下表旧版本的测试数量或运行结论。

此轮覆盖统一添加表单、工作台/设备管理、单设备活动、私钥导入与恢复、传输记录移除，以及显式转 IP；责任规则分别在设备连接、信息架构和交互规格中维护，静态状态定位见[设计对照](design-fidelity.md#源稿与实现定位)。

| 检查 | 实际结果与范围 |
| --- | --- |
| Flutter 应用及设计系统 | 全量 436 项通过，包含窄屏、横屏、二倍文字、安全区及密钥恢复确认；是 Widget 验证 |
| Rust Core lib | 141 passed、0 failed、9 ignored；4 项要求 IPv4 组播，5 项要求隔离/真实 Android adbd 或授权 shell，未计通过 |
| 身份与 TCP 回归 | 扫码保留 deviceId/专用身份，取消及旧身份拒绝；TCP 目标核验后原子提交，失败、取消、目标不符、无序列号时内存和持久记录保留原连接字段 |
| 密钥输入与传输 | 文本/单文件回填、取消与格式限制、密钥不可用后明确恢复继承；活动先停止再移除记录，保存文件保留，持久日志删除/恢复覆盖于对应回归 |
| 工程检查 | Dart 分析、builder only-check、协议生成、Core Clippy `-D warnings`、Rust 格式及 token 漂移检查通过；官方设计检查保留扩展属性和引用警告 |
| 源稿及运行样本 | Pencil 对象/展开实例核对与代表图目视；API36 普通主控入口 Dart hot reload 成功、runtime errors 为空。热重载没有重新部署本轮 Rust 原生库 |

活跃应用另有 API36/x86_64 目标系统样本：真实任务启动、返回 HOME 后保留、force-stop 后消失，以及目标 PackageManager PNG。它证明该目标接口，不外推全部 OEM 或旧 Android。

此轮没有物理目标上的 USB 双端授权、无线码/扫码配对、新密钥重新授权或实际 adbd 固定端口转换验收。Pencil、主机夹具、Widget 和 Dart 重载不替代这些条件。原始临时日志/截图不作为长期规范或构建输入。

## 协议与持久化回归

2026-10-19 的 Linux 工作区执行了 workspace 测试、严格 Clippy、格式、ADB 无默认 feature 编译和生成检查。针对性回归覆盖 SYNC push 按协商 payload 合并、控制队列背压、经典/现代 checksum、USB wire 保真、确定 errno 不额外部署 helper、取消 rename、可选电量查询不阻塞连接及旧查询不更新新连接。

传输检查点与 journal 的迁移、截断/序号/代际错误、删除和失败写入均有主机回归；单项更新不再全量重写历史。机制与回退限制见[架构](architecture.md#状态和资源所有权)、[ADB 库](../../crates/adb/README.md)及[被控兼容](android-target-compatibility.md)。可信无线候选、发现代际与TLS重连另见[无线重连](wireless-reconnect.md)。包数减少不是实机吞吐倍数；未测真实设备 MiB/s、CPU/RSS、小时稳定性，也未交付字节续传。

## 历史设备流程证据

下表收敛 2026-10-17 至 19 日已执行的独立流程。旧后端/偏好/页面已改动时，保留的是能力与故障证据，复跑应使用当前源码入口和实际目标条件。

| 对象与环境 | 实际证据 | 限制与复现位置 |
| --- | --- | --- |
| 首次授权，安全配置 API36 AVD | 未配对证书拒绝、错码失败、真实 PAKE、Required TLS、精确系统接口撤权后拒绝旧身份 | 可写覆盖层 userdebug/orange 镜像；直接 Settings Forget 持久化曾失败；非量产安全、QR 或物理 USB 认证。见[首次配对](first-pairing.md) |
| 全屏远控，API36 双 AVD | 实际 H.265 486×1080、默认导航键、系统 Back 保留会话、画面外点击不暂停、退出把手拖动/收起/展开及返回 | 较早协作暂停和补丁播放器版本；没有继承为当前原版完整业务通过。`product_flow_test.dart` |
| 五种视频格式，API36 x64 | H.264/H.265/AV1/VP8/VP9 的实际编码、首帧、Texture、截图、暂停恢复与停止 | 是功能超时，非五编码延迟/画质达标；HEVC 请求1280曾退化到230×512，改选1080取得486×1080。见[HEVC研究](../research/hevc-emulator-constraints.md) |
| 声音与前后台，API36 | 实际 PCM、播放器 playing/时钟前进；双设备焦点丢失与恢复、Activity 重建保留同进程音源、按精确活动停止音源 | 不证明物理扬声器/耳机可闻、进程死亡恢复或双向通话。旧后台声音偏好已由统一后台保持替代；当前所有权见架构 |
| 文字输入，API36 Settings | composing 不泄漏、中文 emoji 精确一次、延迟不重复、查询恢复；限定时序截图在主控与目标均看到新文字 | 使用 TestTextInput 编辑协议，不是 Gboard 候选、InputConnection 镜像或触控到像素延迟。见[本机键盘](mobile-ime.md) |
| 原通话界面，隔离 API36 模拟来电 | 真实 CallsPage→全屏远控，独立 Telecom/Telephony 确认同一来电仍振铃及 InCallActivity 前台 | 未接听/拒接；全局动作因无法原子定位而移除，不能算安全逐呼叫控制或双向音频。见[通话入口](current-call-ui.md) |
| 文件与目录，实际 API36 adbd | push/pull 哈希、中文/空目录/零字节、冲突、取消、链接循环、源变化、FUSE 发布及非UTF8名称碰撞保护 | 不宣称目录整体事务或秒精度 stat 检出所有变化；真实测试见 `files_android` / `files_tree_android` |
| 系统文件位置，API36 ExternalStorageProvider | 真实 ACTION_CREATE_DOCUMENT 与目录选择，独立读回字节、子目录与空目录 | 不覆盖云 provider、所有旧 API 或 provider 原子覆盖。见[内容交付](content-delivery.md) |
| 相册与搜索，API36 双 AVD | 多目录原件、稳定分页与重试、受限目录、JPEG/MP4 取回和系统交接 | 各任务分别验收，不能以缩略图或缓存代替保存。见[图库](gallery-index.md)、[搜索](file-search.md) |
| 入站内容，API36 三 AVD | 外部 provider 真实 grant；UI 选 A 后焦点切 B，独立读回仅 A 收到 PNG，消费后不重复传输 | 合成 fixture，非任意恶意/云 provider；固定提交目标见[内容交付](content-delivery.md#外部入站内容的固定目标) |
| 媒体暂存，API36双AVD | 真实预览与清理页操作，租约持有时保留原件，释放后核对实际回收；远端原件保留 | 不证明应用总占用为零、长期ENOSPC或外部分享读完。见[媒体暂存](media-cache.md) |
| 通知观察与原动作，API36 | 实时观察、原动作失效、accepted/unknown 跨页保护；独立 APK fixture 的 RemoteInput 原文与次数核对为1 | shell 裸 receiver 缺 ApplicationThread 注册失败；无 APK probe 只证明系统接受，不证明送达；APK样本只证明合成应用接收 |
| 主控系统提醒，API36 双 AVD | 远端系统通知→通用隐私提示；精确撤回、SystemUI 点击后进入来源设备且不执行旧远端动作 | 拒权、渠道关闭、锁屏、真实来电、OEM/系统停止与 Windows 打包身份另验。见[系统提醒](system-notifications.md) |
| 连接故障，实际 adbd/协议夹具 | 半包与HTTP背压期限、精确 Client 失活检测；应用层黑洞无注入EOF后，新会话及新像素自动恢复 | TCP ACK仍在的应用层停转，非真实 Wi-Fi 漫游或任意 adbd 内部挂起。见[连接健康](connection-health.md) |

通知回复与可见设备归属的复现入口是 `app/integration_test/notification_reply_test.dart`、`tool/driver/notification_reply.dart` 与独立 `tool/e2e/notification_fixture/`。夹具核对 run/id/原文/count、原通知精确清除、基线剪贴板恢复及自有安装清理；缺少任一回执不能记为完整通过。

## 构建与渲染证据

2026-10-19 的社区原版 fvp 切换实际完成主机测试、分析、生成一致性、Android x64 打包及普通入口启动；当轮没有重跑远控/媒体 E2E。此前补丁播放器的运行或崩溃保护结果不继承。内存 appendBuffer 实验未取得同PTS下可靠延迟/CPU收益，仍由独立 benchmark 运行，见[研究记录](../research/mdk-memory-input-experiment.md)。

三架构 release 包的压缩对照、签名与独立 ELF/资源检查见[Android打包](android-packaging.md)。SDK/NDK、密码接口、ZIP 校验和可复现服务端产物的升级验证见[依赖升级记录](dependency-upgrade-2026-10-20.md)。这些是构建/主机证据，不是 ARM 设备运行。

玻璃材料的静态稿、Widget、GPU 夹具和普通主控入口分别取证。API36/x64、Impeller OpenGLES、Mesa llvmpipe 样本验证了官方组件的局部折射、明暗文字和实体辅助偏好；不证明 Apple 原生等效、完整连续形变或多视频性能。详见[设计对照](design-fidelity.md)和[玻璃运行记录](glass-components-2026-10-20.md)。

## 复现入口

默认工程检查从仓库根运行 `tool/check.sh`；Android 整包检查使用 `tool/check.sh --android`。设备用例依各自测试声明显式提供隔离目标及 opt-in，不把 ignored 当作通过。Flutter 集成测试从 `app/` 执行：

```sh
flutter drive -d <主控设备> \
  --driver=../tool/driver/integration_test.dart \
  --target=integration_test/product_flow_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=<目标可达地址> \
  --dart-define=CONNECT_E2E_PORT=<连接端口> \
  --dart-define=CONNECT_E2E_TRANSPORT=<已知连接方式>
```

专题文档给出对应 driver、目标条件及额外参数。主机工具可用 adb 配置本次隔离端点，不成为产品依赖；配对端口不能充当连接端口。模式切换后先按[打包说明](android-packaging.md#测试插件注册)准备插件，缺端点、完成回执或清理确认必须失败。输出使用新的系统临时目录，不覆盖失败证据或写回设计源稿目录。

## 尚待验证

物理 USB 双端授权、真实 Wi-Fi 发现/漫游、32位 ARM 与厂商旧手机、纯 Rust experimental 密码提供器发布安全、真实多设备听测/通话链路、长时后台与进程/系统停止恢复、热功耗、完整高动态低延迟，以及 Apple/Windows Flutter 整包均没有由上述局部证据关闭。跨端 cargo check、编译成功、首帧或首页重载各有自己的范围。
