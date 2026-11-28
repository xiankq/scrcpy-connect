# 平台与能力边界

本文列出各平台上每项功能的前提条件、当前已交付的范围，以及用不了时的替代路径。

- 主控上的邻接是普通应用，各平台支持的系统版本以构建配置为准。主控权限由各系统自己授权。
- 被控 Android 开启调试并授权后，邻接通过 shell 在手机上运行临时服务。

## 窗口与形态适配目标

窗口重排见[窗口环境与响应式结构](interaction-rules.md#窗口环境与响应式结构)，画面与会话的对应关系见[画面与窗口](interaction-rules.md#画面与窗口)，各形态的导航和窗格见[自适应窗口与形态](../design.md#自适应窗口与形态)。

| 平台 | 窗口与姿态从哪里获得 |
| --- | --- |
| Android | WindowManager 提供尺寸和折叠特征，是否分割窗格依据 `FoldingFeature.isSeparating`。每个画面打开为独立 Activity，在系统最近任务里显示设备名和画面名。平板能否打开浮窗由系统桌面窗口模式决定，初始尺寸按手机画面比例请求。系统以全屏显示时，仍使用同一个独立 Activity |
| iOS 与 iPadOS | 窗口尺寸和安全区来自 Scene。iPad 通过 UIKit Scene 打开独立窗口，窗口呈现和尺寸由系统决定。iPhone，以及无法创建独立 Scene 的 iPad，使用应用内全屏控制页。iPhone Duo 通过 `foldable` 取得外屏、内屏和折叠保留区 |
| macOS、Windows、Linux | 远控子窗口使用 Flutter 3.50 实验性的单引擎桌面窗口能力；系统不支持时改用应用内窗口切换。macOS 开启读屏时，已打开的远控画面回到应用内，会话保留。标题栏见[桌面窗口标题栏](../design.md#桌面窗口标题栏) |
| HarmonyOS | 只有 Flutter 侧的布局接口，原生宿主还没接入。接入时：`windowSizeChange` 更新尺寸，`windowStatusChange` 更新窗口模式，`foldStatusChange` 触发重新读取姿态。API 12+ 可用 `FoldSplitContainer` |

- 各平台把可用边界、安全区、保留区、姿态和窗口模式汇总为 `WindowEnvironment` 交给布局使用。半折时的安全窗格见 [iPhone Duo 专项](../design.md#iphone-duo-专项)。
- Android 的独立 Activity 和 iPad 的 Scene 与工作台共用设备连接和控制会话，各自显示自己的画面。系统拒绝打开新窗口时，改用应用内控制页。
- 宽屏和展开的折叠屏，在安全宽度足够时可以并排两路画面。
- 系统恢复窗口时，只接续仍然有效的会话；会话已失效时提供关闭入口。

窗口验收覆盖：两台设备同时控制；同一设备的整机画面和独立应用并行；重复打开时聚焦原窗口；尺寸和折叠变化；后台和恢复；关闭单个窗口；活动中的 USB 连接保持。

[Flutter 多引擎](https://docs.flutter.dev/add-to-app/multiple-flutters) · [Android 最近任务](https://developer.android.com/guide/components/activities/recents) · [UIKit 多场景](https://developer.apple.com/documentation/uikit/uiapplication/supportsmultiplescenes) · [Flutter 桌面窗口](https://flutter.dev/blog/desktop-windowing-apis) · [HarmonyOS Window API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-window-window/)

## 功能条件与替代路径

| 功能 | 条件与行为 |
| --- | --- |
| 基础连接 | 授权握手成功，且网络或 USB 实际连通，见[设备与连接](device-connection.md) |
| 整机画面与输入 | Android API 21 起；被控设备需允许屏幕捕获、编码和输入 |
| 独立应用窗口、正在运行的应用 | Android API 29 起，按实际任务能力提供。不能开独立窗口时，可选同页分栏或手机画面 |
| 设备声音 | Android API 30 起；Android 11 启动声音时手机需已解锁。受各应用的声音捕获权限限制 |
| 剪贴板 | 同步两端都能读到的新复制文字。权限受限、失焦和后台时暂停 |
| 文件、搜索、相册 | 范围取决于当前身份的读取权限。读取失败、没查完、确实为空分开显示 |
| 预览 | 图片按解码结果和方向显示。视频缩略图需 API 27；不支持时提供原件入口 |
| 通知、通话 | 按当前用户、系统接口和授权检查。电话接力见[电话接力](calls.md) |

- 某项功能出故障时，在对应入口显示原因；结果待确认时提供检查操作。
- 需要权限时，说明是在主控还是手机上操作。

## 主控差异

| 主控 | 当前支持的连接方式与限制 |
| --- | --- |
| Android | 无线配对、扫码、已授权 IP、获得系统许可的 USB。后台保持取决于前台服务和通知权限 |
| iOS 与 iPadOS | 无线配对、扫码、已授权 IP。只在前台提供连接操作 |
| 桌面 | 使用应用内置的 ADB。内置文件缺失时，提示重新安装邻接或重新解压便携包。USB 连接受系统的设备访问权限限制 |
| Windows 提醒 | 在应用内查看通知和电话 |

## 远控性能验收目标

- 从打开到第一帧真实解码画面：≤ 1000 ms。
- 输入响应（从按键发出到目标变化出现在解码帧里）：P50 ≤ 200 ms，P95 ≤ 300 ms。
- 屏幕实际呈现时间单独记录。
- 结果注明设备、解码后端、构建模式、画面尺寸和连接方式。测试时保持负载一致，并检查纹理输出、暂停恢复和结束后的资源释放。

## 当前交付边界

- 电话：只提供「打开手机电话界面」。在主控接听、拒接、挂断和双向声音，按[交付与验证门槛](calls.md#交付与验证门槛)实测通过后再提供。
- 按包名打开原应用时，由手机系统选择复用哪个任务。熄屏发送休眠键，解锁认证由手机管理。画质的请求上限和实际协商结果分别显示。画面暂停后，按手机返回的捕获状态更新连接状态。
- 目录发送：Android 使用系统授权目录，Linux 使用系统路径选择框。
- 取回原件的原子写入：Android 和 Linux 已支持。Apple 平台可以读取设备目录，但取回写入目前返回 `atomic_save_unavailable`。系统保存、分享和打开方式见[原件取回与系统交付](content-and-transfer.md#原件取回与系统交付)。
- 视频详情提供可用的取回和分享。直接在手机上打开视频，需要手机端有能定位并打开原件的入口。
- 本机暂存上限 512 MiB；是否允许新任务还要看磁盘可用空间和受保护占用，见[媒体暂存](content-and-transfer.md#媒体暂存与空间准入)。
- 应用更新：读取已安装版本信息。检查、下载和安装按[渠道交付](app-updates.md#渠道交付)接入。
- 液态玻璃：按[外观偏好](information-architecture.md#设置与本地数据)和平台渲染能力显示，回退规则见[材质](../design.md#材质)。

## 数据与授权保护

- 主控授权身份只保存在本机。导入设备记录后需要重新授权；迁移密钥见[授权密钥](device-connection.md#授权密钥)。
- 系统分享、复制和写入手机，都只由用户明确操作发起。
- 诊断只记录脱敏后的标识、操作和阶段，不记录密钥、配对码、通知正文、剪贴板和原始参数。
- 容量不足时，暂停受影响的功能或拒绝新任务，保留已有数据和其他设备的活动。
- 能力验收按实际运行环境记录。
