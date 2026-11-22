# 平台与能力边界

主控作为普通应用运行。安装版本以各端构建配置为准。被控 Android 开启调试并授权后，通过 shell 运行临时服务。主控权限由各宿主系统授权。

## 窗口与形态适配目标

窗口用可用宽高、方向、安全区、显示特征和输入方式决定布局。旋转、开合、分屏和缩放保留当前设备、任务、焦点、选择、草稿及滚动位置。具体宽高、导航和窗格见[宽高阈值](../design.md#通用宽高阈值)与[iPhone Duo 专项](../design.md#iphone-duo-专项)。

| 平台 | 窗口与姿态来源 |
| --- | --- |
| Android | WindowManager 提供尺寸和折叠特征。分割窗格依据 `FoldingFeature.isSeparating`。独立控制使用 `FlutterEngineGroup` 和单独的 Activity 任务。 |
| iOS 与 iPadOS | 使用 scene 和 `FlutterEngineGroup` 创建独立窗口。系统恢复 scene 时沿用原会话身份；iPhone Duo 通过 `foldable` 取得外屏、内屏和折叠保留区。 |
| macOS、Windows、Linux | `desktop_multi_window` 维护独立引擎与窗口身份。窗口操作由宿主提供，应用页头避让原生控件。各端布局见[桌面沉浸式窗口](../design.md#桌面沉浸式窗口)。 |
| HarmonyOS | 具备 Flutter 布局契约。原生宿主待接入，适配时由 `windowSizeChange` 更新尺寸、`windowStatusChange` 更新模式、`foldStatusChange` 触发姿态重查。API 12+ 可使用 `FoldSplitContainer`。 |

宿主将可用边界、安全区、保留区、姿态和模式投影为 `WindowEnvironment`。每个控制窗口独立拥有设备、应用任务、视频捕获和输入焦点。宿主不支持额外窗口时使用同页分栏，保留会话身份。半折默认选择安全单窗格，用不同窗格分别呈现画面与工具的布局见[交互稿](../interaction-motion.md#响应式窗口与辅助交互)。

窗口验收覆盖真实创建、调整大小、折叠、切换、恢复、关闭和迟到的回执。[Android FoldingFeature](https://developer.android.com/reference/androidx/window/layout/FoldingFeature) · [Apple iPhone Duo 准备指南](https://developer.apple.com/iphone-duo/prepare/) · [HarmonyOS Window API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-window-window/)

## 功能条件与替代路径

| 能力 | 条件与行为 |
| --- | --- |
| 基础连接 | 以授权握手与网络或 USB 实际连接确认；见[连接规则](device-connection.md)。 |
| 整机画面与输入 | Android API 21 起，需被控设备允许捕获、编码和输入。 |
| 独立窗口、活跃应用 | Android API 29 起，按实际任务能力提供。无独立窗口时可选择同页分栏或手机画面。 |
| 设备输出声音 | Android API 30 起，Android 11 启动时需满足解锁条件。声音按设备组织，受应用捕获权限约束。 |
| 剪贴板 | 同步两端可读取的新复制文字。权限受限、失焦和后台时暂停。 |
| 文件、搜索、相册 | 范围由当前身份的读取权限决定。分别呈现读取失败、未查完和完整空结果。 |
| 预览 | 图片按解码结果和方向呈现。视频缩略图需 API 27，受限时提供原件入口。 |
| 通知、通话 | 按当前用户、系统接口和授权检查。电话接力的逐通话操作与音频见[电话接力](calls.md)。 |

单项故障在对应入口显示原因，待确认时提供检查动作。需要权限时说明在主控还是手机上操作。

## 主控差异

| 平台 | 当前路径 |
| --- | --- |
| Android | 无线配对、扫码、已授权 IP 和获系统许可的 USB。后台保持随服务与通知权限状态。 |
| iOS 与 iPadOS | 无线配对、扫码与已授权 IP。连接操作在前台提供。 |
| 桌面 | 使用应用管理的 ADB 服务和宿主可用连接能力。 |
| Windows 提醒 | 应用内查看通知与电话。 |

## 远控性能验收目标

启动至首份真实解码像素 ≤ 1000 ms。输入响应从发出按键到目标变化进入解码帧，P50 ≤ 200 ms、P95 ≤ 300 ms。独立记录屏幕实际呈现。结果注明设备、解码后端、构建模式、尺寸和连接方式。保持负载一致，并核对纹理输出、暂停恢复及结束后的释放。

## 当前交付边界

- 电话提供「打开手机电话界面」。独立接听、拒接、挂断和双向声音按[电话接力](calls.md#交付与验证门槛)实测后提供。
- 按包名打开原应用时由手机系统选择任务。熄屏发送休眠请求，认证由手机管理。画质请求上限和实际协商结果分别展示。暂停呈现后按捕获事实更新连接状态。
- 目录发送使用 Android 的系统授权目录及 Linux 原生路径选择。取回原件的原子发布由 Android 和 Linux 提供；Apple 宿主可读设备目录，取回发布当前返回 `atomic_save_unavailable`。系统保存、分享和打开方式分别按[交付流程](content-and-transfer.md#原件取回与系统交付)提供。
- 本机暂存预算为 512 MiB，准入还需核对磁盘可用空间和受保护占用。释放范围见[媒体暂存](content-and-transfer.md#媒体暂存与空间准入)。
- 当前版本读取安装信息。检查、下载与安装按[渠道](app-updates.md#渠道交付)接入。
- 玻璃按[视觉规范](../design.md#elevation--depth)呈现。初始化、低透明度、高对比和缺少光学支持时使用实体材料。Windows 需在 Windows/Impeller 构建运行，核对涉及采样器的 shader 警告与实体回退。

## 数据与授权保护

授权身份保存在本机。导入设备记录后重新授权，密钥迁移使用[授权密钥](device-connection.md#授权密钥)。明确的用户动作发起系统分享、复制和远端写入。

诊断仅记录脱敏标识、操作与阶段，保护密钥、配对码、通知正文、剪贴板及原始参数。容量不足时暂停受影响项或拒绝新任务，保留现有数据及其他设备的活动。能力验收按实际运行环境记录。
