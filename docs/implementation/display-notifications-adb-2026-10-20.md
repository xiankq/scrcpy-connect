# 屏幕比例、通知与 ADB 边界核对（2026-10-20）

本文记录本轮源码与验证结果，不承担产品规则。当前行为见[交互规则](../../designs/prod/interaction-rules.md)，模块责任见[架构](architecture.md)，代表状态见[设计对照](design-fidelity.md)。

## 变更与证据对象

- 远控支持原始、可用区域自适应、预设与自定义比例。自适应采用扣除安全区与远控导航键后的实际布局约束，临时键盘不改变被控比例。整机通过受监督的临时显示覆盖改变目标尺寸，独立应用使用 scrcpy 虚拟显示及 resize 控制消息。既有偏好默认原始比例。
- 工作台提供连接后点亮、关闭前锁屏与保持唤醒。锁屏限定最后一个整机控制页面主动退出；后台、断线及独立应用窗口不触发。保持唤醒采用官方 scrcpy 的 keep_active，不改全局充电常亮设置。
- 通知逐条使用圆角卡片，展示 PackageManager 应用名、当前用户的图标及收到时间；点击卡片调用原通知动作。单条和全部清除按目标回执／新快照更新，不提前隐藏，也不承诺原应用消息已读。
- 通知镜像覆盖前台新事件；初始快照与重新附着基线保持静默，保留去重、隐私设置和精确撤回。当前 Android 主控系统通知中心的实际链路单独验收。
- 动态列表改为开放行及惰性 builder／sliver。通知保留独立对象卡片，活动、文件、传输、会话、发现结果和活跃应用不以整组卡片承载全部条目。万行通用列表及千项活跃应用有初始构建数量回归。
- ADB 库移除产品重连跟踪器，公开原始 TCP 选项及 adbd service 响应。Dart 配置执行参数，组织配对、USB 记录选择、转 IP 重试、能力说明与自动重连调度；原生通过 adb.* 提供有显式租约的单次执行与探测事实。产品设置种子、画质预设和全局／设备合并统一在 Dart，Rust 核验参数、尝试所有者、连接代次及旧活动清理边界。

Pencil 保留有独立含义的完整页面与控制状态，移除重复授权、发现、应用／设备卡片、质量和目录片段。通知母组件与比例选择／自定义状态同时更新，未删除独有的视频控制状态。源稿通过对象 API 修改，代表图通过渲染检查。

## 第一轮验证（后续源码变更前）

环境：Ubuntu x86_64、Flutter 3.47.7／Dart 3.13.5、Rust 1.99.1、JDK21，以及 Android API36 x86_64 AVD。官方 adb 仅用于测试配置与独立核对。

通知 Binder 样本在真实 AVD 中展示应用名 Shell 而非包名 com.android.shell，旧通知动作引用被拒绝，目标清除后快照中消失；回执不将消息标记为已读。测试只回收本次通知、JAR 与转发。

通知、工作台、文件和传输页面各取明暗主题、普通尺寸及 280 宽／二倍文字样本，共 16 张 Flutter Widget 截图；未观察到布局异常。Pencil 代表状态另行渲染核对。截图位于系统临时目录，不成为设计源稿依赖。

| 检查 | 结果及边界 |
| --- | --- |
| Flutter 应用 | 全量 427 项通过，包含导航／安全区／键盘／横竖屏、认证回落和大列表；Widget 层 |
| 设计系统／Dart 桥接包 | 分别 36／158 项通过；另有调度器 8 项与原生配置／重新附着 4 项针对性复跑 |
| 工具层 | 58 项通过；token 生成测试 4 项通过；原生文档／USB／声音合同检查通过 |
| 静态与生成 | 全仓 Dart analyze 无问题，Dart／Rust 格式、workspace Clippy -D warnings、协议／FRB／builder 生成一致性、服务端源码／共享压缩产物检查通过 |
| Android 安装包 | 修后 Debug 176434936 字节，arm64-v8a／armeabi-v7a／x86_64；签名、ZIP、16 KiB 原生对齐、Manifest、三架构 Flutter／Rust ELF 与共享服务端资源复验通过 |
| 视觉规范 | 官方 lint 0 错误、71 条既有扩展属性／孤立 token 警告；本轮未改变 token 数值 |

实际 scrcpy 基线与比例 E2E 在 SDK36／x86_64 Android16 通过。整机和独立应用窗口均取得 H.264 字节，经 FFmpeg 解码 PNG 确认为 640×960，再动态调整为 960×640；独立窗口必须传 flex_display=true，本轮真实验证发现并修正了缺参导致的服务退出。keep_active 使已亮屏的活动时间增长，KEYCODE_SLEEP 后等待 4.5 秒仍保持睡眠。停止会话后目标恢复 1080×2400、无显示覆盖，原旋转配置、实际朝向与全局超时不变，无显示租约残留。本次夹具已卸载，成功及失败诊断的自有会话资源已清理，捕获图片保留在系统临时目录。预存显示覆盖、旋转映射、外部修改保护、resize 失败与关闭交接另由主机 shell 夹具覆盖，未在 AVD 制造强杀 shell／悬挂 wm。这证明该 AVD 的 Rust→scrcpy→解码流程，不等于 Flutter 远控触控整条链路或物理 OEM 验收。

真实 AVD 验证还发现经典 ADB 的 empty OKAY 可重复表示 readiness；原实现将额外 readiness 当作逐包 ACK 错误并关闭整条连接。修复保留 stream ID／payload 校验，额外 readiness 不为后续写入累计许可；线缆回归核对兄弟流保活及后续写入仍等待新回执。

Rust workspace 使用每测试二进制 4 个线程执行：428 passed、75 ignored、0 failed。高并发首轮的跨设备清理 500 ms 时限用例曾失败，原断言单独重跑和限制测试并发后的全量均通过，未放宽断言。该全量编译早于最后的 flex_display 参数修复；修后 scrcpy 主机用例另有 37 passed、1 ignored，且上述实际 AVD 比例验收通过。

真实多播 mDNS 的 7 项 opt-in 用例另行全部通过，未计入默认通过数。需要 SO_ATTACH_FILTER 的黑洞 TCP opt-in 用例因宿主 EPERM 未运行成功，不能算已验；应用层停转、外部自动重连和手动停止后迟到尝试拒绝的三项 socket 夹具通过。产品不再依赖 Rust 自动重连调度。

修后 APK 的 SHA-256 为 3a54da95c1a905bfb95c89e588da2c027c918df95994e1dee68cb97b7e4e391e。以该包重新安装启动 API36 主控普通入口，实际显示设备空态，Impeller OpenGLES 与玻璃初始化成功，DTD runtime errors 为空；本轮 Dart 与新 Rust 初始化参数共同运行，不以旧库热重载代替。启动截图位于系统临时目录。

## 补齐与复核

第一轮完成判断过早：Android 启动自动重连时，原先页面层屏幕策略可能丢失连接事件；部分产品编排和默认值也仍在 Rust。后续将屏幕策略迁至 Bridge，在自动连接前读取可信基线，按连接代次只提交一次点亮；失败在页面订阅后仍可见。编码器选择弹层另改为惰性构建，千项列表可滚动选择末项。

连接编排和产品默认值按上述职责继续迁移，原生与 Dart 测试分别验证执行事实和产品决策。最终结果以本节后续补齐的验证为准，第一轮安装包与通过数不代表这些后续变更已验收。

当前源码验证：全仓 Flutter analyze（fatal infos）无问题，Dart／Rust 格式检查通过。Rust workspace 的 62 个测试二进制汇总 436 passed、75 ignored、0 failed；Clippy 全 targets 严格检查通过。Flutter 应用全量 429 项、Dart 桥接全量 186 项、设计系统 36 项、工具层 58 项及 token 生成 4 项通过。原生策略测试实际加载 FRB 库，确认 Dart 设置种子完整注入、同目录相同参数重新附着可复用，改变策略或设置种子会被拒绝。协议、FRB、builder 与服务端压缩资源生成一致性检查通过。

新边界另显式运行真实 mDNS 配对的四项用例：第二端点、拒绝明文、取消及发现更新／撤销后的代次校验全部通过。USB 当前证据为描述符资源夹具和 Dart 授权迟到／重复序列号流程，未据此声明物理 USB 双端授权验收。

真实远控验收另捕获带键盘重新进入保留窗口的过渡问题：目标从稳定 916×1920 被短暂系统栏产生的视口误改为 942×1920。新增 Widget 回归先在旧源码失败，记录到不应提交的 session.display；修复在请求 IME 至真实 inset 出现期间冻结尺寸，取消排队调整，并在释放输入后的执行边界重新检查。后续较慢的真实 IME 再现了超时解除冻结的问题，最终移除按等待时长推断硬件键盘的逻辑：同一窗口保持冻结，实际 IME、焦点离开或窗口尺寸变化结束等待；没有 IME 的硬件键盘场景仍随真实窗口旋转调整。延迟 1.8 秒的 IME 与硬件键盘旋转分别有回归，稳定后的导航、旋转仍可驱动自动调整。双 AVD 的已通过分支核对主控键盘 inset 883 物理像素时，目标仍为 916×1920、Flutter 解码 610×1280；独立 host 断言通过，保留包含 Android IME 叠层的实际截图。

旋转验收进一步捕获自动调整的调度问题：同一待调整尺寸在持续页面更新中反复重启 250 ms 计时器，可能始终不执行；短暂 inactive 又可能消耗计时器而在 resumed 后没有恢复。两条 Widget 回归均先在旧源码失败，分别加入连续 streaming 事件和无 pause 的 inactive／resumed 过渡；修复对同一待调整尺寸与会话绑定保留计时器，在 resumed 重新评估最新视口，八项远控设置 Widget 用例通过。

真实关闭会话还触发社区 fvp 的空快照原生崩溃：API36 x86_64 的 JNISurfaceTextu 线程 SIGSEGV，按同 BuildId 的未剥离库符号化，栈顶为 MdkSnapshot 回调 callbacks.cpp:693，并非根据渲染线程名称猜测纹理重复销毁。断流发生在排空 Dart 操作之前，不能通过 Dart catch 或仅调整 dispose 次序保证 MDK 返回非空。普通回读最终复用 Bridge 的原生判空、跨度校验与有界存储，和按需逐帧诊断分开；未修改社区依赖。普通与诊断 token 共享单个 Player 的快照准入，撤销不能伪装原生回调已取消，迟到结果也不读取失效借用数据。十四项原生适配用例覆盖 NULL、迟到回调、4096×2048／2048×4096 的实际像素复制、超界拒绝及 token 隔离。

自定义比例输入还暴露通用文本弹窗的生命周期问题：原逻辑在 pop 后 400 ms 释放控制器，实际退场与 IME 动画较慢时，仍在树中的 TextField 会使用已释放控制器。改为弹窗 State 拥有并在实际 dispose 时释放；十倍慢速退场回归在旧源码失败、修复后通过，不再以固定时长猜测组件销毁。

独立窗口的完整 Flutter 验收发现另一项真实比例问题：请求 1280×1920、画质 maxSize=1280，实际编码和解码却为 1280×1280。锁定版本的 [NewDisplayCapture](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/NewDisplayCapture.java) 对 flex 显示使用非等比约束，[Size.constrain](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/model/Size.java) 分别限制两轴，解释了该结果。Dart 在启动及 resize 前按同一上限等比解析为 854×1280；已保留窗口读取自身 quality，不把下一窗口的偏好提前应用。整机 wm 请求不参与此虚拟窗口缩放。原生虚拟尺寸范围与实体显示分开核验，允许等比缩放产生的小尺寸；独立窗口产品默认尺寸也迁至 Dart，原始 Rust 调用缺省时传上游 `new_display=`。四项 Dart 回归覆盖横竖屏、极端比例、质量上限、既有窗口和不合法参数保留。

极端自动比例另覆盖 4096×320、maxSize=320：不能把分别取整的 320×26 当作比例正确，解析器选择限制内仍保持比例的 256×20。缺少 resize 尺寸继续交由原生拒绝，不套用新窗口默认。桥接全量首轮另暴露既有截图队列测试用零时长延迟猜测文件 I/O 完成的竞争；改为等待假播放器实际进入回读的信号，保持原队列次序断言，全量 186 项复跑通过。

Android 通知完整链路通过 `notification_requirements_test.dart` 与对应 driver：API36 x86_64 双 AVD，冷构建当前 FRB 和 Dart。应用显示真实名称及逐字节一致的原始 PNG；点击整卡在目标得到原始 PendingIntent 的 OPEN/count=1 回执。单条清除核对精确来源 ID，全部清除后目标只保留 NO_CLEAR 项。主控前台收到新事件时，独立 `cmd notification` 查询确认系统镜像已发布，内容为通用隐私文案；目标应用撤回后主控该系统通知同步消失，其他主控通知保留，初始快照不集中发布。锁屏分支确认进入真实远控路由、目标仍锁定且不重放动作；没有将路由切换早期截图当作锁屏视频首帧证据。系统授权通过正常界面允许，不用 pm grant 绕过；Flutter 自动化与 UiAutomationService 冲突时由测试操作者按截图点击系统按钮。驱动结果 `notificationRequirementsComplete=true`、hostErrors 为空，本次 PIN、夹具和设备记录已清理。证据保留在 `/tmp/connect-e2e/notification-requirements-20261020-final3/`。

Android 远控设置完整链路通过 `remote_settings_test.dart` 与对应 driver：API36 x86_64 双 AVD，最终冷构建安装包的第 22 次驱动全部通过，`remoteSettingsComplete=true`、34 个独立 host 检查、`cleanupErrors=[]`。自适应开启／关闭导航栏分别解码 652×1280／610×1280，横屏 1280×610；真实 IME 不重设目标尺寸。四个预设、2:3 自定义及非法输入保留均通过。连接后点亮在实际新 connectionId 上生效，单独切换偏好不点亮；keep_active 在控制与保留暂停会话中均维持活动，最后整机页面退出后目标仍休眠。独立 Settings 应用的 2:3 窗口实际解码 854×1280，实体 wm 仍为 1080×2400；首次退出和从会话列表恢复后退出均未锁屏。关闭与清理后物理尺寸、旋转和超时恢复基线，无显示租约或测试进程残留。驱动日志无 Flutter 异常、FATAL EXCEPTION、Fatal signal 或已释放控制器错误；模拟器仍有非致命图形／编解码器诊断，不能概括成系统日志零错误。证据保留在 `/tmp/connect-e2e/remote-settings/`。第 21 次驱动在安装前因宿主 OOM 杀掉模拟器中断，未计为通过；恢复两台 AVD 并限制启动内存后复用同一已编包完成第 22 次验证。

最终交付包为普通入口 `app/build/app/outputs/flutter-apk/app-debug.apk`，以 `lib/main.dart` 重新构建，137277500 字节，SHA-256 `cc52cc2ca3e6db7ee461b9fae2a1b5bd13198ed286ee5672058b3907461b25a0`。arm64-v8a、armeabi-v7a、x86_64 均含 Flutter／Rust ELF；签名、ZIP 完整性、16 KiB 原生页对齐、Manifest 与共享服务端资源检查通过。API36 主控冷安装该普通包后实际启动，Impeller OpenGLES 与玻璃库初始化完成；通过 DTD 显式 hot reload 成功，前后均未报告运行时错误。启动截图保存在 `/tmp/scrcpy-final-android-20261020.png`。该包包含最终缺项拒绝与极端自动比例修正，不把测试入口安装包作为交付物。

测试完成后移除本轮转发并正常关闭本轮启动的两台模拟器，`adb forward --list` 为空；删除临时目标 AVD，保留原有 `interop-controller` 的数据与配置。成功证据集中保存在 `remote-settings/final/`，重复检查点、截图和中间日志已清理，选定失败诊断保留供回归追溯。

## 适用边界

Widget 和静态稿不能证明 GPU 材质、系统通知中心或目标 OEM 行为。Android21–35／物理 OEM 和长时后台未由 API36 AVD 样本覆盖。

临时整机显示覆盖在受监督 shell 正常结束、控制通道停止及 EOF 时恢复；目标外部已修改的覆盖不被旧租约覆盖。SIGKILL 或目标 shell／adbd 崩溃无法保证 trap 执行，残留租约会拒绝盲目覆盖，需要独立核验目标状态。
