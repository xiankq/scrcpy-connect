# 主控、被控与功能支持基线

日期：2026-10-16。本轮先汇总文档与固定源码证据，不是兼容验收结果。基础事实补查见[报告](../../docs/research/requirements-gap-verification.md)，工程前沿见[任务04](issues/04-compatibility-capabilities.md)。

## 证据与状态必须分开

每个实测条目最终记录：主控OS/ABI/应用与SDK版本、被控API/build/ROM/用户、连接方式、JAR摘要、功能与权限、证据来源、测试步骤/结果、状态/原因/替代路径。文档支持→实验通过→目标真机通过为不同证据等级；不可用与尚未测试不同。

以下统一为“有文档/源码依据、未做本项目实验”。未知/需要设置/可用/受限/不可用由实际探测与结果决定，不能仅按API数字在所有ROM启用。

| 功能 | 主控条件 | 被控基线及分级条件 | 尚须验证／受限路径 |
| --- | --- | --- | --- |
| 基础主屏/输入 | Android当前重点；正式主控下限由锁定Flutter/插件闭包确认 | scrcpy5.0.1官方API21/Android5+基础目标 | API21真机首帧/触控/多点/旋转/重连；编码器与OEM输入授权 |
| 启动原应用 | 同一已授权设备连接 | 固定源码有launch intent路径，不能统一写为Android10+ | 启动真实task/登录态与通知定位；无独立窗口仍可主屏接续 |
| 独立应用窗口 | 主控呈现/输入与资源可用 | 新显示与非主屏输入API29/Android10+ | 应用单实例迁移、多实例和系统限制；不支持时回主屏 |
| USB连接 | Android USB主机能力、普通USB系统权限；无需主控调试 | 被控USB调试、解锁/RSA授权与ADB接口 | 线材/角色/供电/撤销/拔插；iOS无通用USB后端不阻断核心编译 |
| 现代无线配对 | 网络权限/可达与发现；主控无需调试 | Android11+系统无线调试；码或QR配对建立信任 | pair/connect端口分离、过期/拒绝/已配对不可达；mDNS失败可手动地址但不绕过权限 |
| 较旧无线 | 有已授权USB引导路径 | Android10及以下官方USB授权→TCP listener路径 | 不承诺未授权纯无线冷启动；旧TCP与TLS安全条件不同，不能混成同一路 |
| Wi-Fi2优化 | 自有主机须实现对应发现/元数据/重连行为 | 官方Android17＋对应主机支持；元数据版本可核查 | Android11–16与17分组，切网/DHCP/旧端口/VPN和授权撤销 |
| 设备媒体声音 | 主控解码/音频焦点/路由 | Android11+；11启动解锁条件独立，12+不同 | 捕获失败与画面可用分开；不是双向电话语音 |
| 被控本机同时发声 | 主控与被控路由同时支持 | duplication Android13+，应用可opt-out | 把应用限制显示为声音受限，非投控整体失败 |
| 双向通话语音 | 普通麦克风权限、通信音频/后台资格 | 现代系统API/权限/HAL/实际上下行条件；本轮不存在可承诺所有版本统一门槛 | 电话控制、VoIP与PSTN分别记录；受限时留手机通话 |
| 实时通知/原动作 | 主控发布通知权限另验，不赋予远端监听权限 | 临时shell/JAR listener与action权限逐ROM/用户验证 | 点击/清除/RemoteInput/锁屏/认证与失效分开；不启SMS数据库 |
| 文件管理/传输 | 路径/SAF/MediaStore权限、目标能力 | 远端shell可访问路径及sync能力 | 不能访问所有私有数据；恢复、覆盖、seek/rename和部分成功逐端点 |
| 图片/视频相册 | 解码/容器与保存分享授权 | 可读取内容/索引及实际媒体格式 | 视频、HEIF/HEVC/动态内容组合不能仅凭系统版本保证 |
| 剪贴板/分享 | 普通App焦点与系统读写条件，尤其Android10+后台读限制 | scrcpy文本与远端权限；图片/文件需重新发布内容和授权 | 不用主控调试补后台无限读取；不支持粘贴转手动保存/分享 |
| 后台保持 | Android真实FGS用途/系统版本/权限/Doze/OEM条件 | 连接/JAR/目标网络与授权持续有效 | 按活动恢复；iOS等后台资格另研究，不能承诺永久socket |
| 玻璃/解码呈现 | Flutter/渲染器/Texture/插件及设备性能 | 视频配置/尺寸和目标编码器 | 各端构建、Android动态效果/延迟/可访问性分别验收 |

基础与音频/虚拟显示的固定来源：[scrcpy README](https://github.com/Genymobile/scrcpy/blob/v5.0.1/README.md#prerequisites)、[Server](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/Server.java)、[Device](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/device/Device.java)、[Audio](https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/audio.md)。无线：[官方ADB](https://developer.android.com/tools/adb#wireless)、[Platform Tools发行说明](https://developer.android.com/tools/releases/platform-tools)。其余逐项证据见现有[研究索引](../../docs/research/README.md)。

## 平台交付分层

| 主控平台 | 当前承诺 | 本轮真实状态 |
| --- | --- | --- |
| Android | 当前功能实施/运行重点；核心/FRB/Flutter实际编译 | 无应用工程与构建/运行通过结果；已有静态稿与研究 |
| iOS | 核心/FRB/Flutter实际编译；TCP/发现/媒体等保留适配 | 构建未执行；USB候选排除/条件返回，本地网络与后台运行未验 |
| Windows | 核心/FRB/Flutter实际编译 | 构建未执行；WinUSB驱动、媒体和玻璃运行未验 |
| macOS | 核心/FRB/Flutter实际编译 | 构建未执行；本地网络/沙箱/USB与媒体运行未验 |

Q32要求实际构建，不允许以“Rust/Flutter支持平台”替代。正式CPU/最低OS/SDK/feature闭包须在任务03形成建议和证据；这里不以示例目标静默排除其他架构。

## 最低端与能力边界验证

保留API21基础目标；按21/22、23、24/25、26–28、29、30、33及较新系统布置有理由的回归，优先覆盖行为变化边界，不要求每个数字都无差别重复全部用例。模拟器/真机、主控/被控分列。扩展JAR不得用更高minSdk将整机基础投控误抬高；若某扩展需高版本，应隔离功能并显示状态。

当前矩阵没有任何“本项目真机通过”行。后续发现真实不兼容应定位JAR、协议、插件或设备条件，先修复或提出有证据的取舍，不自动删掉已确认目标。
