# 累计设计要求 · 逐项实施状态（2026-10-22 验证轮）

状态取值：待实施 / 实施中 / 待验证 / 已验证 / 受阻。
本清单按目标正文十一节 + 三项排查维护；压缩上下文后从本文件继续。
每项必须保留“实现位置 + 验证证据 + 缺口”。

## 一、责任文档与工作原则
- [已验证] 已读 AGENTS.md（根、designs、app/lib、crates）、design.md、prod 规格（device-connection、information-architecture、interaction-rules、user-flows、coverage）及两份交接文档。
- [已验证] 保留工作区既有修改；未回退设计调整。基线 `git status` 61 个修改文件 + 新增目录（含 remote_input_queue、file_browser_model 等）。
- [已验证] 不以文档/静态检查替代功能实现：本轮以代码 + 测试 + 设备运行核对。

## 二、全局列表、卡片与图标
- [已验证] `GroupedListView`/`SettingsGroup`（app/lib/widgets/grouped_list.dart）用于设置、能力、选项等固定分组；动态列表逐项构建（ListIconBadge 使用处已核对）。
- [已验证] 列表图标 28px 色块 / 6px 圆角 / 20px 图形：token `componentListIconSize=28`、`Rounded=6`、`GlyphSize=20`（design_tokens.g.dart:244-249）。
- [已验证] 六语义色齐备：blue #007AFF、mint #30D158、amber #FF9F0A、coral #F03D32、slate #6B7E9F、purple #AF52DE（design_tokens.g.dart:48-52）；白色图形 `componentListIconTextColor=0xffffffff`。
- [已验证] `functionalIconColor` 按内容语义分配（action_row.dart），非全蓝、非随机。
- [已验证] 真实应用图标/照片保持原貌（PhoneAppIcon 不染色）。
- [已验证] 生成入口：`node tool/design_tokens/generate.mjs --check` 0 errors/71 warnings 通过；未手改生成文件。

## 三、设备列表与发现设备
- [已验证] 更多菜单按状态：离线“开始连接”、已连接“断开连接”，同时保留连接配置、移除此设备（device_card.dart:86-164）；`pending`/`connecting` 防重复提交。
- [已验证] 断开确认活动影响、移除确认不撤销远端调试信任（confirmConnectionChange / removeSavedDevice 文案已核对）。
- [已验证] 发现页仅发现内容：无加号、无 IP/配对码/USB 入口；右上刷新（connection_discovery_page.dart:28-33）。
- [已验证] 列表三行顺序：名称 / IP:端口 / 信任状态；IPv6 方括号（_endpointLabel）；配对端口与连接端口区分（`kind == 'pairing'`）。
- [已验证] 选中结果回填原表单（pop service → ConnectionFormRoute），不把发现当授权。

## 四、添加设备、连接配置与转 IP
- [已验证] 四形式共用页面外壳与公共组件（connection_form_page.dart + ConnectionIdentityFields）。
- [已验证] 四形式统一辅助字号/颜色/字段节奏/主动作/帮助间距（共享组件，reaudit 记录 16px 表单间距、52px 常态）。
- [已验证] 扫码“重新生成”全宽黑色圆角主按钮（QrPairPage 复用主按钮，全宽）。
- [已验证] 添加设备可选全局/专属私钥，专属原位展开 PEM+文件选择（ConnectionIdentityFields；identityScope/privateKeyPem）。
- [已验证] 选文件只填内容不立即替换身份；校验提交由当前方式主动作完成（prepareConnection）。
- [已验证] 连接配置复用添加表单；配置模式隐藏发现入口并收起占位（configuring 分支）。
- [已验证] 连接配置始终编辑原设备，预填可复用值，成功后核验同一目标更新原记录（connection_setup_coordinator）。
- [已验证] 已有设备配置私钥来源置灰只读：不能切换/编辑/导入/恢复继承（ConnectionIdentityFields readOnly 分支，bcFd3/B5nGcj 状态）；全局密钥管理独立保留。
- [已验证] 地址/端口/USB 集中在专门连接配置页；其他子页无重复入口（详情子页与诊断页已核对）。
- [已验证] 转 IP 地址为只允许选择的下拉（DropdownButtonFormField，无自由输入）；候选来自当前设备接口 IP（device.network.get + InternetAddress.tryParse 过滤）。
- [已验证] 转 IP 覆盖多地址/唯一预选/无地址/读取失败/地址变化（readAddresses + notice 逻辑；提交前重读核对 selected 归属）。
- [已验证] 端口默认 5555、validatePort 校验 1–65535。
- [已验证] 转换沿用目标身份，处理中断/取消/失败/未知；成功且核验同一 deviceId 后才更新（devices.wireless + enabled/connected/deviceId 三重校验 + refreshDevices）。
- [待验证] 转 IP 真实切换互操作（需目标设备；既有记录声明待验，本轮保留缺口）。

## 五、设备详情的信息架构
- [已验证] 首卡重布局：DeviceFacts 型号/状态/方式/端点/电量/充电，无 Android 版本（device_hero.dart + device_facts.dart）。
- [已验证] 首卡不显示 Android 版本；版本移入设备数据页（devices_details_data_page.dart system 组）。
- [已验证] 离线/读取失败/过期不冒充实时电量（DeviceFacts 过期屏障；离线不留旧动态值）。
- [已验证] 首卡摘要进入设备数据页；打开画面/连接主动作独立在卡片下部（DeviceHero InkWell + FilledButton）。
- [已验证] “内容与通信”改名“快捷操作”且位于活跃应用上方（workspace index:90 ContentShortcuts → RunningApps）。
- [已验证] 快捷操作与活跃应用一致 52px 外框；功能图形 32px（componentAppIconSize=52、componentIconLargeSize=32）；窄屏/大字换行（Wrap + scale clamp）。
- [已验证] 活跃应用展示真实已启动任务（apps.list filter=running + source=runningTasks + live 校验），真实图标，不混未启动应用。
- [已验证] 全部应用使用 28px 原始图标、行内距/项间距/最小行高（devices_workspace_apps_page 使用 list-icon 尺度）。
- [已验证] 下半部分组：设备设置（设备名称/连接配置/转IP/画面设置/剪贴板/导航键/新画面点亮/最后画面锁屏/保持唤醒）→ 连接能力（功能支持/诊断/当前活动）→ 设备管理（断开/移除）（workspace index:119-254）。
- [已验证] 连接诊断只展示检查结果/原因/重新检查（diagnostics 页无编辑入口）。
- [已验证] 控制窗口管理页已移除：sessions/index 与 sessions/tools 目录为空；`SessionsRoute`/`SessionToolsRoute` redirect → WorkspaceRoute（app_router.dart:852-861）；无生产入口引用。

## 六、画面设置及画面生命周期
- [已验证] 用户可见“画质”统一更名“画面设置”（QualityPage title；工作台入口）。
- [已验证] 远控屏幕比例移入画面设置页（QualityPage 屏幕布局组 + chooseScreenRatio），工作台无重复比例行。
- [已验证] 同设备所有画面共用一套画质：deviceQuality 按设备解析（video_quality_policy.resolve），quality 命令重建当前会话（scrcpy.rs），无窗口单独覆盖。
- [已验证] 必要流重建保留真实任务与窗口归属；失败逐项反馈（applicationFailures → “设置已保存，N 个画面未能应用”）。
- [已验证] 比例与画质分别按责任规格：比例“用于后续新建窗口，已打开窗口保持创建时模式”（RemoteDisplaySettings 生命周期）。
- [已验证] “新画面启动时点亮屏幕”：每个新建画面请求启动时 wake 一次（remote page:526 `newWindowWake ??= requestWake()`，非 0→1 限定；同次重试不重复）。
- [已验证] “关闭最后画面时锁屏”：releasePhonePage 返回 lastPage 才锁屏（remote page:1443-1449；DeviceScreenPolicy 按设备计数）。
- [已验证] ADB 连接/断开/重连/重新附着/临时后台不触发：DeviceScreenCoordinator 只跟踪连接身份不触发；claimPhonePage 对同 sessionId 转移归属。
- [已验证] 保持唤醒独立管理：keepActive 随窗口存续（session.start keepActive 参数），不改超时/不主动点亮。
- [已验证] 关闭即释放窗口/输入/资源，无关闭后暂停/保留/恢复概念（sessions 页面删除 + remote leave）。
- [已验证] 临时遮挡/后台/短断线暂停呈现但不复活已关闭窗口（presentation/恢复路径按窗口身份）。

## 七、远控快捷控件、直接亮屏与应用打开弹层
- [已验证] 退出改可展开悬浮快捷控件，保留拖动跟手/吸边/收起/展开（exit_handle.dart 完整实现）。
- [已验证] 点击收起按钮只展开不退出；面板六项：锁屏/截图/转独立窗口/键盘/旋转/关闭画面（exit_handle.dart:192-202）。
- [已验证] 工具动作归属当前窗口，触控不透传（按钮命中主控消费）；转独立窗口隐藏重复（independent 参数）；已是独立窗口时不提供。
- [已验证] 横屏/键盘/安全区/吸边可达性：_dragBoundsFor 合并 padding + systemGestureInsets；旋转后重新约束。
- [已验证] “手机处于休眠状态”模态已删除（全局搜索无该文案）；无“重新检查”亮屏二次确认。
- [已验证] 只有确认熄屏或锁定才显示直接亮屏图标（remote page:2034-2040 screenOn==false || screenLocked==true）；未知不伪装（仅 errorCode device_asleep 兼容旧路径）。
- [已验证] 点击直接发送幂等唤醒（wakeScreen 幂等），亮屏再执行不熄屏；恢复后隐藏。
- [已验证] 应用打开弹层只保留应用名 + 两个动作 + 取消（phone_app.dart:71-113）。
- [已验证] 删除 pxuLr 通用说明/登录态/任务交回描述；旧系统仅简短标注（api<29 一行）。
- [已验证] 两按钮间距 12px（spacingSm），共享主/次按钮（FilledButton/OutlinedButton），窄屏/明暗可用。

## 八、应用级设备活动后台
- [已验证] 默认开启后台保持随 APP 进入启动：bridge.initialize → ApplicationBackgroundPolicy.apply(automatic:true)，不等画面（application_settings.dart 默认 backgroundKeepAlive: true）。
- [已验证] 无画面/关一个/关最后一个都不停止：后台与画面生命周期分离（background.request 独立命令；音频 policy 单独）。
- [已验证] 画面/音频不反向启停后台：失败仅记 background.failed；系统 stopped 阻止自动重连但不撤销偏好。
- [已验证] 保留显式关闭与系统停止处理；不虚报（background.status 呈现真实状态）。
- [已验证] 保持后台不自动打开画面/播放声音/重放历史（职责分离已核对）。
- [待验证] 目标设备实际后台服务运行（需 AVD；既有记录已通过，本轮如环境允许复核）。

## 九、设备数据页
- [已验证] 只读设备数据页从首卡摘要进入、支持刷新（DeviceDataRoute + revision refresh）。
- [已验证] 分组：设备与系统/电池与电源/屏幕与显示/网络与连接/内存与存储；字段来自 ADB 实际数据（device.data.get）。
- [已验证] 不堆放原始键/日志；未知/不支持/失败区分（shown() 未获取 + failures 组说明）。
- [已验证] 动态数据按来源更新；离线注明时效（stale StateNote + observedAt）。
- [已验证] 刷新与迟到回执不污染另一设备（connectionId 栅栏 + deviceId 校验）。
- [已验证] 首卡电量/充电持续更新（DeviceFacts 周期刷新 + 过期屏障；受控电量变化已通过）。

## 十、三项真实问题排查与修复
- [已验证] 远控顶部黑区：SystemChrome immersiveSticky + 布局使用完整可绘制视口（修后 Rect(0,0,400,800)），有可失败 Widget 回归（remote_loading/lifecycle 测试）。
- [已验证] 多余主控顶部占位已去除；浮动工具自行避让安全区（ExitHandle/_dragBoundsFor）。
- [已验证] 源画面比例留边与主控黑区区分，不拉伸/裁切（fit 逻辑 + 测试）。
- [已验证] 输入坐标/刘海/横屏/导航区域：remote 测试覆盖；设备实机证据保留在既有记录。
- [已验证] 独立窗口密度：scaled_density（scrcpy_display.rs:80）按实体密度换算；720px/280dpi ≈ 411dp；测试含 720/1280/1080 断言。
- [已验证] 不缩放整幅 Flutter 纹理掩盖；密度在原生层修正（wm density -d display_id 并核验）。
- [已验证] 通知内容：NotificationContent.java 取 EXTRA_TITLE_BIG/BIG_TEXT/TEXT_LINES，MessagingStyle 保留系统预览（第16-40行）。
- [已验证] 通知链路：真实 Binder 事件→UI→list 交叉核对（notifications-02 记录）；更新/撤回/重新附着覆盖。
- [已验证] 目标设备实际通知样本复核：本轮在 emulator-5556 实跑 `notification-snapshot.dart`，PASS（真实 BigText/Inbox 快照、更新、撤回、Binder 回调、观察重附着）；`companion_android` 三条用例在 5560 目标通过（实时通知、合成来电替换、启动取消）。
- [已验证] 独立窗口密度实机复核：`virtual_display_density_evidence` 通过。实体 1080×2400@420dpi（约411dp）与独立显示 720×1280@280dpi（同约411dp），`cmd activity stack list` 含 `sw411dp`，独立窗口保持手机逻辑宽度。

## 十之二、本轮新发现并修复的缺陷（Rust 栈溢出）
- [已验证] 缺陷：仓库官方检查入口 `tool/check.sh` 直接运行 `cargo test --workspace`，但三个用例在默认 2MiB 测试线程栈溢出（既有基线即复现，非本轮改动引入）：`host_identity::reset_only_retires…`、`audio_activities::stopping_an_audio_activity…`、`quality_reconfiguration_android::virtual_display_density_evidence`。此前文档以 `RUST_MIN_STACK=8388608` 规避，与仓库自身“堆分配 future 而非加大栈掩盖”的既有原则冲突。
- [已验证] 修复（按仓库既有 `Box::pin` 边界惯例，均在关键 await 边界堆分配，不加大栈）：
  - `crates/interop_core/src/snapshot.rs`：`state_snapshot` 对 `session_command` 结果 future `Box::pin`。
  - `crates/interop_core/src/runtime.rs`：`invoke` 拆为薄包装 + `invoke_inner`，公开签名不变，728 处调用点无需改动。
  - `crates/interop_core/src/scrcpy.rs`：`OwnedProcess::capture` 对 `verify` `Box::pin`。
  - `crates/adb/src/error.rs`：`bounded` 对传入 operation `Box::pin`（shell 携带 16KiB 缓冲，是深层链的主要体积）。
- [前序证据] 三个用例在默认栈单独通过；`cargo test --workspace`（无 RUST_MIN_STACK）全量通过 431 passed / 0 failed / 86 ignored；`cargo clippy --workspace --all-targets -D warnings` 与 `cargo fmt --all --check` 通过。该结果来自本轮最终新增文件偏好重启用例之前，不能代替最终树复跑。

## 十一、液态玻璃与设计源稿
- [已验证] 浅色稳定选中玻璃：三层组合（regular track + 静止 AnimatedGlassIndicator + 官方前景），design_system.dart:659-760 `resting-navigation-lens`。
- [已验证] 选中轮廓/光学层次/离面感；保留按压/拖动/归位与降低透明度分支（glowOnly/实体偏好路径）。
- [已验证] GPU 成像证据：navigation_lens_test.dart + 8 张捕获（既有记录）；本轮如环境允许复核。
- [已验证] 设计文件组织：同一 mobile.pen，一页面一顶层画布（57 顶层：40 页面 + 17 载体）。
- [已验证] 大画布浅灰底（canvas），组件与页面配色按职责保留。
- [已验证] .pen 仅通过 Pencil MCP / 对象 API 读写（本轮未按文本修改）。
- [已验证] 最终对象扫描：`MaHXL`/`C2ZhGv`/`Baclb` 为 `$surface`，`lm0us`/`a7A57` 为 `$canvas`，`XL2nI` 为 56px `$surface`；`RwXvW` 与 126×56px `ngnln` 同行。740 个文本对象中不存在“Node ID:”或指定 ID 标注，`Sjzxf`/`ftaRY`/`mVNnf` 已不存在，也没有快捷回复文案。

## 十二、执行、验证与完成条件
- [已验证] 本清单持久化（本文件）。
- [已验证] 生成文件/路由清理/文档同步按依赖顺序（sessions 路由 redirect、token 生成一致）。
- [已验证] app 全量测试：438 通过 / 1 按需跳过（本轮最终复跑）。
- [已验证] design_system 25 项通过；interop_bridge 191 项通过（本轮复跑）。
- [待验证] Rust：新增 `preferences_lifecycle` 磁盘重启用例覆盖视频模式、排序键与方向恢复；当前环境没有 `cargo`/`rustfmt`，最终树未能复跑 workspace、Clippy 或格式检查。前序 431 passed 结果只保留为旧证据。
- [已验证] `rtk dart analyze` 无问题；Dart 格式检查 211 文件 0 变化；`build_runner --only-check`、token 生成一致性与 `git diff --check` 通过。
- [已验证] 宿主 Widget 实采 402×874：文件网格、文件列表、独立文件搜索和实时通知；核对文件页 `surface`、缩略区 `surface-low`、文件夹／文件自然行高、居中名称与元数据、短日期、紧凑大小及无快捷回复。测试图片缩略图受本地解码路径／时序限制，不作为生产缩略图失败。
- [已验证] 实际设备运行（API36 x86_64 AVD，Mesa llvmpipe 软件 GL；主控 5554 / 被控 5560）：
  - `application_background_test`（进入即启后台、显式开关、引擎重附着）通过。
  - `device_details_android` 真实读取系统/1080×2400/420dpi/60Hz/电池/内存/多接口地址通过。
  - `apps_android` 真实已启动任务与真实图标通过。
  - `notification-snapshot.dart` 真实 BigText/Inbox 快照/更新/撤回/Binder 回调/重附着通过。
  - `quality_reconfiguration_android` 8 项单线程通过（含独立窗口 720×1280@280dpi 与实体 411dp 一致、真实 task 87 保留、质量重建）。
  - `device_lifecycle` 元数据读取与“睡眠目标仅显式唤醒”通过。
  - `scrcpy_device` 5 项通过（真实 H.264 解码、真实任务关闭后保留、真实触控/文本、paused/streaming 主画面与独立应用启动互不影响）。
  - `navigation_lens_test` + 8 张实际 GPU(软件)成像，`navigationLensComplete:true`；rest/drag 逐图核对静止镜片与移动镜片。
- [已验证] 视觉验证（宿主 Widget 实采 402×874）：workspace-main（首卡/快捷操作/活跃应用/分组）、app-open-method（弹层精简+主次按钮）、connection-config-ip（只读私钥）、add-ip/add-qr（四形式+全宽黑色重新生成）。
- [已验证] 报告实现位置、验证结果与未完成项（最终回复）。

## 本轮设备验证环境与注意事项（复现者必读）
- 目标 AVD 重启在 **5560**（console 5560 / adbd 5561），因为本机 nginx 占用了 5556，使 `adb emu` 控制台命令被代理拦截；modem-call 用例依赖 `adb emu gsm`。
- 不要对目标执行 `adb root`：root 后 `cmd notification post` 以 uid 0（package "root"）提交，NotificationService 以 `NameNotFoundException: root` 拒绝，会让 `companion_android` 的实时通知用例假失败（本人操作造成，已 unroot 复验通过）。
- `quality_reconfiguration_android` / `scrcpy_device` 等共享同一目标设备的用例必须 `--test-threads=1`，并行会互相干扰虚拟显示与 Settings 任务。
- `apps_android` 要求目标无既有 Settings 任务（用例声明）；跑完质量用例后需 `am force-stop com.android.settings` 再运行。
- `remote_display_android` 与 `video_quality_android` 需要 `INTEROP_FFMPEG` 独立解码器；本机无 ffmpeg，保留为环境缺口。
- 成像为 Mesa llvmpipe 软件渲染，非物理 GPU。

## 仍未验证（保留缺口，不虚构通过）
- 物理 USB 双端授权、真实 Wi-Fi 发现/漫游、系统扫码配对、真实转 IP 互操作（主机夹具已过，设备互操作未做）。
- 32 位 ARM、OEM 旧手机、物理 GPU、Apple/Windows 整包。
- `remote_display_android`、`video_quality_android`（缺 INTEROP_FFMPEG）。
- 其他 ignored 设备用例按各自声明的目标条件未逐一执行。

## 已知缺口（不虚构通过）
- 物理 USB / 真实 Wi-Fi / OEM / 物理 GPU / ARM 设备运行未在本轮覆盖。
- 转 IP 真实切换互操作、系统扫码配对：既有记录为待验/已验分层，本轮按环境能力复核。
- 目标设备相关验证（通知样本、后台服务、独立窗口密度对照）依赖 AVD 启动；环境不可用时保留缺口。
