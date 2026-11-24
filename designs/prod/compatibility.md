# 平台与能力边界

主控作为普通应用运行。安装版本以各端构建配置为准。被控 Android 开启调试并授权后，通过 shell 运行临时服务。主控权限由各宿主系统授权。

## 窗口与形态适配目标

窗口重排和会话归属见[窗口交互规则](interaction-rules.md#窗口环境与响应式结构)，各形态的导航和窗格见[适配规范](../design.md#adaptive-windows--form-factors)。

| 平台 | 窗口与姿态来源 |
| --- | --- |
| Android | WindowManager 提供尺寸和折叠特征。分割窗格依据 `FoldingFeature.isSeparating`。每个画面打开为独立 Activity，并以设备和画面名出现在系统最近任务。平板由系统桌面窗口模式决定能否出浮窗，并按手机画面比例请求初始尺寸。系统以全屏呈现时，使用同一个独立 Activity。 |
| iOS 与 iPadOS | 窗口尺寸和安全区来自 Scene。iPad 支持通过 UIKit Scene 开独立窗口，由系统决定窗口呈现与尺寸。iPhone 及无法创建独立 Scene 的 iPad 使用应用内全屏控制页。iPhone Duo 通过 `foldable` 取得外屏、内屏和折叠保留区。 |
| macOS、Windows、Linux | 远控子窗口使用 Flutter 3.50 的实验性单引擎桌面窗口能力。宿主不支持时使用应用内窗口切换。macOS 开启读屏时，现有远控画面回到应用内，保留原会话。各端布局见[桌面窗口标题栏](../design.md#桌面窗口标题栏)。 |
| HarmonyOS | 具备 Flutter 布局契约。原生宿主待接入，适配时由 `windowSizeChange` 更新尺寸、`windowStatusChange` 更新模式、`foldStatusChange` 触发姿态重查。API 12+ 可使用 `FoldSplitContainer`。 |

宿主将可用边界、安全区、保留区、姿态和模式投影为 `WindowEnvironment`。半折的安全窗格见[iPhone Duo 专项](../design.md#iphone-duo-专项)。

Android Activity 和 iPad Scene 共用工作台的设备连接与控制会话，各自持有画面输出。系统拒绝开窗时使用应用内控制页。宽屏及展开的折叠屏在安全宽度足够时可并排两路。系统恢复窗口时只接续仍有效的会话。

窗口验收覆盖两台设备同时控制、同一设备的整机与独立应用并行、重复打开聚焦原窗口、尺寸和折叠变化、后台和恢复、关闭单窗，以及活动中的 USB 连接保留。原生系统恢复以设备和会话身份接续，失效时提供关闭入口。 [Flutter 多引擎](https://docs.flutter.dev/add-to-app/multiple-flutters) · [Android 最近任务](https://developer.android.com/guide/components/activities/recents) · [UIKit 多场景](https://developer.apple.com/documentation/uikit/uiapplication/supportsmultiplescenes) · [Flutter 桌面窗口](https://flutter.dev/blog/desktop-windowing-apis) · [HarmonyOS Window API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-window-window/)

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
| 桌面 | 使用应用管理的 ADB 服务和宿主可用连接能力。Windows 优先使用应用目录下的 Platform-Tools，也支持系统已安装的 ADB。 |
| Windows 提醒 | 应用内查看通知与电话。 |

## 远控性能验收目标

启动至首份真实解码像素 ≤ 1000 ms。输入响应从发出按键到目标变化进入解码帧，P50 ≤ 200 ms、P95 ≤ 300 ms。独立记录屏幕实际呈现。结果注明设备、解码后端、构建模式、尺寸和连接方式。保持负载一致，并核对纹理输出、暂停恢复及结束后的释放。

## 当前交付边界

- 电话提供「打开手机电话界面」。独立接听、拒接、挂断和双向声音按[电话接力](calls.md#交付与验证门槛)实测后提供。
- 按包名打开原应用时由手机系统选择任务。熄屏发送休眠请求，认证由手机管理。画质请求上限和实际协商结果分别展示。暂停呈现后按捕获事实更新连接状态。
- 目录发送使用 Android 的系统授权目录及 Linux 原生路径选择。取回原件的原子发布由 Android 和 Linux 提供；Apple 宿主可读设备目录，取回发布当前返回 `atomic_save_unavailable`。系统保存、分享和打开方式分别按[交付流程](content-and-transfer.md#原件取回与系统交付)提供。
- 视频详情显示可用的取回与分享。直接在手机中打开视频需要能够定位并交付原件的手机侧入口。
- 本机暂存预算为 512 MiB，准入还需核对磁盘可用空间和受保护占用。释放范围见[媒体暂存](content-and-transfer.md#媒体暂存与空间准入)。
- 当前版本读取安装信息。检查、下载与安装按[渠道](app-updates.md#渠道交付)接入。
- 液态玻璃按[外观偏好](information-architecture.md#设置与本地数据)和宿主渲染能力呈现。极致模式在完整折射不可用时使用标准渲染。关闭特效、初始化期间、降低透明度或提高对比度时使用实体材料。[材质规范](../design.md#elevation--depth)

## 数据与授权保护

授权身份保存在本机。导入设备记录后重新授权，密钥迁移使用[授权密钥](device-connection.md#授权密钥)。明确的用户动作发起系统分享、复制和远端写入。

诊断仅记录脱敏标识、操作与阶段，保护密钥、配对码、通知正文、剪贴板及原始参数。容量不足时暂停受影响项或拒绝新任务，保留现有数据及其他设备的活动。能力验收按实际运行环境记录。
