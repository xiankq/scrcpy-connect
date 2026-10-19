# Apple 连续互通：实际操作路由与本项目取舍

核查日期：2026-10-17。依据 Apple Support、用户手册和 Apple Developer 一手资料正文；未安装、连接或实操 Apple 设备。阅读对象是实际跨设备任务、平台条件和权限边界，不是 HIG 或玻璃材质。支持页会更新，本报告记录此次读取结果，不推断尚未核验的系统版本、地区开放时间或将来能力。

## 研究与既定范围的关系

用户已确定手机控制手机优先；被控为无 root、无额外 APK 的 Android，允许 ADB 推送和临时运行 JAR；主控不要求开启调试。文件、相册预览和通话可有专用功能页；短信只通过通知进入被控手机原应用；录屏及文件／相册自动备份已移除。联系人、专用相机、终端、长期通知档案及自动编辑回写等由代理按授权移出范围。以上区分沿用产品规格（历史路径 `../../.scratch/interop/spec.md`）与[功能取舍](../../designs/prod/scope.md)，不是本研究重新征求的决定。

Apple 的镜像、原生业务应用、活动接力和内容传送是不同路由。下列事实只能作为交互参考；Apple 系统能力不能证明普通第三方应用或 ADB 临时 JAR 具有同等权限。相关约束仍以 [ADR 0001](../adr/0001-apk-free-controlled-device.md)、[ADR 0005](../adr/0005-real-application-tasks-in-linked-windows.md)、[ADR 0006](../adr/0006-controller-without-debugging.md) 为准。

## 1. Mac 操作 iPhone：iPhone Mirroring 的具体边界

| 官方事实 | 可据此判断什么 |
| --- | --- |
| 基础条件是支持的 Mac（Apple silicon 或 T2，macOS Sequoia 15+）、iOS 18+ 且设有密码的 iPhone；两端同一 Apple Account 并启用双重认证，Wi-Fi／蓝牙开启，iPhone 锁定且在 Mac 近旁；Mac 不同时使用互联网共享、AirPlay 或 Sidecar；一次只用一台 Mac 与一台 iPhone。官方当前注明欧盟不可用。[设置与要求](https://support.apple.com/en-us/120421) | 这是带设备、账号、安全及位置条件的能力，不能只写“连接成功即可使用全部功能”。 |
| Mac 内置镜像应用可操作 iPhone 的真实屏幕和应用；退出镜像或解锁实体 iPhone 会停止镜像。镜像不能访问 iPhone 相机／麦克风，包括 Face ID 和电话；电话另走 Mac 通话能力。[操作与停止](https://support.apple.com/en-us/120421) | 原应用接续与专门通话链路分开；Apple 的“保持锁定仍可操作”不能被解释为本项目可绕过 Android 锁屏或应用认证。 |
| 官方演示从镜像中的 Photos 拖视频到 Mac，或把 Mac 的图片拖进镜像中的 Messages／Mail；也能拖入、拖出 iPhone Files。[跨设备复制](https://support.apple.com/en-us/120421) | 这是“远端真实应用 + 内容交接”。它不证明镜像应用另有原生相册数据页、远端文件系统挂载或自动编辑回写。 |

上述同一 Apple 页面还列有更高系统版本的附加操作；本报告只采用解决本次路由判断所需的基础条件，不把可变的最新版手册等同于本项目兼容矩阵。官方的欧盟限制未在该帮助正文中给出完整的账号地区／实际位置资格算法；不能补写成“改账号或切换地区即可用”，也不能推断何时开放。[官方要求](https://support.apple.com/en-us/120421)

## 2. 通知可达与原应用可操作并非同一状态

Apple 首次成功设置镜像后，Mac 可在镜像应用未使用、iPhone 不在近旁时接收其通知，条件是 iPhone 开机；iPhone 在近旁时，交互通知才会打开镜像中的相关应用。通知图标有 iPhone 来源标识，远端清除也会同步；用户可分别控制各应用是否显示。Mac 本机应用自己的通知与 iPhone 通知有不同来源；设置过 iPhone 通话的 Mac 收到来电通知，与镜像通知机制无关。[通知与实时活动帮助](https://support.apple.com/en-us/120684)

**设计推论：** 保留本项目通知列表的来源设备、当前有效性与“进入原应用”动作；“收到通知”不应让按钮提前宣称“当前可控制”。打开时重验设备连接、锁屏及动作是否仍有效。无法定位内容时明确退到原应用或手机屏幕。Apple 对通知和镜像分别设条件，是这种状态拆分的产品证据；它不意味着本项目也有 Apple 的远距离通知服务或账号云通道。项目既有的锁屏隐藏正文、验证码规则继续生效，不能因 Apple 页面展示通知预览就放宽。

Apple 同时提供独立的 Text Message Forwarding：在同一 Apple Account、iPhone 开机联网且可发收消息的条件下，SMS／MMS／RCS 可出现在 Mac、iPad 等设备的 Messages；Messages in iCloud 还会维持完整历史。这是主控本机 Messages 的消息接力，不能归入通知点击后远控原应用。[短信转发](https://support.apple.com/en-us/102545)

**已有用户决定：** 本项目不照搬独立 Messages 数据服务；短信全文、历史、新建与编辑仍进被控手机原应用。Apple 的两种路线并存，不能据此把用户排除的短信中心重新纳入。

## 3. Handoff、Universal Clipboard 与 AirDrop 的任务差异

| 能力与实际操作 | 条件／语义 | 对本项目的取舍建议 |
| --- | --- | --- |
| Handoff：在一端打开支持的应用并开始任务，再从另一端的 Dock／应用切换器接力入口继续。iPhone 有应用切换器底部入口，iPad 有 Dock 入口。[使用 Handoff](https://support.apple.com/en-us/102426) | 同一 Apple Account、Wi-Fi／蓝牙及 Handoff 开启，源设备解锁、近旁且任务在前台；目标也有支持的应用。[设置条件](https://support.apple.com/en-us/102426) | 保持“原应用接续”和“在本机打开”两种文案。本机接力需要具体应用或链接支持，不能把任意远端应用的状态称为可迁移。 |
| Handoff 由应用提供 NSUserActivity，声明活动类型、更新活动信息，在目标应用恢复；跨平台应用需共享开发者 Team ID。文档要求传递临时活动信息，文档本体通过其他机制共享。[开发文档](https://developer.apple.com/documentation/foundation/implementing-handoff-in-your-app) | 不是把原设备任意应用实例直接搬到目标系统；应用活动恢复与内容数据可达是两个问题。 | 不让 Handoff／应用合作成为本项目免 APK 远控的基础条件，也不为此追加编辑副本管理或自动回写。 |
| Universal Clipboard：在一台设备正常复制，在另一台正常粘贴；内容短暂保留，或被任一端下次复制替换。[通用剪贴板](https://support.apple.com/en-us/102430) | 近旁、同账号、Wi-Fi／蓝牙和 Handoff 开启；官方列举文本、图像、照片、视频等内容。[设置与使用](https://support.apple.com/en-us/102430) | 保留就近复制／粘贴与内容发送，不建立剪贴板历史中心。本项目只同步当前操作且开启自动同步的设备，不提供固定对象；具体行为见[交互规则](../../designs/prod/interaction-rules.md#声音与剪贴板)，与 Apple 的同账号机制分别理解。 |
| AirDrop：Photos／Files 选择内容 → 系统分享 → AirDrop → 选择接收者；接收方接受。需要近旁、Wi-Fi／蓝牙开启，使用个人热点时先断开；非联系人须开启相应可发现范围，新的系统组合还有 AirDrop code 条件。[iPhone／iPad 操作](https://support.apple.com/en-us/119857) | 是明确的内容发送／接收流程；不能把已分享一张照片理解为获得远端图库浏览授权。 | 专用文件／相册页服务浏览、选择和手动取用，系统分享服务已取得内容的下一步；不要让发送一份内容自动开启备份或后台全量下载。 |
| Mac 可通过应用分享或 Finder 的 AirDrop 发送；同账号的自有设备可自动接收，接收内容进入 Photos、Files 或 Downloads 等实际位置，取决于内容及设备。[Mac AirDrop](https://support.apple.com/guide/mac-help/mh35868/mac) | 官方还说明已经开始的传输离开近距离后可继续通过互联网；这是 Apple 的能力。 | 成功反馈应给出本机真实保存位置／打开入口。本项目只有已有可达网络路径，不承诺复制 AirDrop 的互联网续传或自动穿透。 |

Handoff 的基础支持范围、Universal Clipboard 的系统门槛、镜像与其他连续互通功能各有独立要求；Universal Control 的对象是 Mac 及其他 Mac／iPad，Sidecar 是把 iPad 用作 Mac 第二显示器。这些不应冒充手机主控访问 iPhone。[连续互通功能要求](https://support.apple.com/en-us/108046)

## 4. 通话具有独立入口，也具有独立依赖

Apple 的蜂窝通话接力让 iPhone 转接通话到同账号的 Mac／iPad：基础路径要求 iPhone 有已启用运营商套餐、开机近旁、两端同网络，并分别开启 Calls on Other Devices／Calls from iPhone 及相关 FaceTime 设置；无需从镜像中的电话应用完成全部操作。主控可从来电通知接听／拒接，也可通过 Phone（macOS／iPadOS 26+）、FaceTime 或其他应用中的号码拨出。通话可交回 iPhone；iPhone 不在近旁时另需 Wi-Fi Calling 路线。[通话设置与操作](https://support.apple.com/en-us/102405)

**设计建议：** 当前来电和通话中状态继续使用专用功能页，清楚呈现被控设备、接听／拒接／挂断及声音去向；主动拨号、联系人和通话记录仍交给被控电话原应用。这延续已有范围，未新增独立通讯录或拨号中心。通话控制成功、通话声音能听到、主控麦克风能传回应分别验收；Apple 能通过系统通话接力使用主控音频，不是 ADB 双向 PSTN 音频已成立的证据。

## 5. 手机／iPad 主控缺的是什么：必须保留 FaceTime 例外

不能写成“Apple 没有手机控手机”。Apple 官方 iPhone 与 iPad 手册均提供 FaceTime 远程控制：在一对一音频／视频通话中共享屏幕后，请求控制；对方接受后可点击、滑动并用屏幕键盘操作。两端需要 iOS／iPadOS 18+，控制者须在被控者联系人中；被控者本机操作优先，可随时停止；结束通话同时结束控制与屏幕共享。修改账号／Face ID、支付或抹除设备等可能受限，远控期间 Face ID／Touch ID 停用，欧盟当前不可用。[iPhone 操作](https://support.apple.com/guide/iphone/iph5d70f34a3/ios)、[iPad 操作](https://support.apple.com/guide/ipad/ipada92df253/ipados)

| 主控形态 | 已有官方证据 | 尚缺／不应混淆 |
| --- | --- | --- |
| Mac → iPhone | iPhone Mirroring 对已授权、近旁且锁定的 iPhone 提供真实应用操作及通知接续。[镜像帮助](https://support.apple.com/en-us/120421) | 一次一对，不能由此宣称 Apple 已提供任意多设备并发应用窗口或远程公网控制。 |
| iPhone／iPad → 另一手机／平板 | FaceTime 中有人参与并接受的屏幕远控；同时有 Handoff、AirDrop、Universal Clipboard、iPad 通话接力等各自路径。[iPhone FaceTime](https://support.apple.com/guide/iphone/iph5d70f34a3/ios)、[iPad FaceTime](https://support.apple.com/guide/ipad/ipada92df253/ipados)、[连续互通要求](https://support.apple.com/en-us/108046) | iPhone Mirroring 官方主控条件没有 iPhone／iPad。FaceTime 协助不能当成同账号、自有设备、锁定近旁且平时已授权的镜像工作台；未据这些资料确认移动端拥有等同 Mac 的后台 iPhone 通知接续。 |
| 本项目 Android 手机 → Android 手机 | 目标是已获授权设备的持续连接、远控、文件／相册及通信任务；已有产品规格，不由 Apple 文档证明实现。项目规格（历史路径 `../../.scratch/interop/spec.md`） | 不要求启动 FaceTime／同类通话才控制设备；不引入 Apple Account、厂商私有协议或主控调试作为基础条件。 |

以上“没有列入主控条件”限定于核查的 iPhone Mirroring 官方产品，不是断言 Apple 所有辅助功能、企业管理或第三方工具都不支持任何远控。FaceTime 资料的地区可用性也不能与镜像可用性合并；中国等目标市场须按对应功能另核查，不能从“非欧盟”直接推成全部可用。

## 6. 本项目的后续验证与不适用边界

本次研究不改变页面范围；新增设计建议是把每次入口的支持条件和结果呈现完整，而非增加一批 Apple 业务页。

- **通知 → 原应用：** 验证临时 JAR 获得的有效通知、原动作、失效更新和内容定位；分别覆盖可达但屏幕不可控、锁屏／应用认证、动作已过期及只有应用入口。Apple 的远距离通知不能替代本项目的后台资格验证。
- **文件／相册 → 本机：** 验证远端可访问内容、完整文件落地、系统保存／分享权限、保存回执与失败恢复；原应用窗口内拖拽不能代替专用页索引验收。不建立云相册、备份计划或自动回写。
- **应用窗口与多设备：** 继续验证 Android 真实任务、单实例迁移和资源限制；Apple 一次一对并未决定本项目并发数量。手机保持当前活动聚焦，大屏再展开并排工作区，依照[信息架构](../../designs/prod/information-architecture.md)。
- **剪贴板：** 验证普通主控应用前后台读取资格、内容类型与明确发送；不把 Apple 系统剪贴板特权用于论证主控无需调试即可无限后台读取。
- **通话：** 独立记录控制、播放与回传音频的设备／ROM 条件，来电只呈现实际可用动作；不因镜像播放媒体有声音就承诺电话音频可双向使用。
- **受限与撤销：** 设备连接、控制会话、通知观察和传输任务分别表达；撤销授权后的恢复路径遵从项目身份模型。官方可远控锁定 iPhone，不允许本项目绕过 Android 授权、锁屏或应用认证。

本报告未发现需要推翻既有 ADR 的证据。Apple Continuity 的系统集成是对照材料，项目仍保留免 APK 被控端、主控不开调试和真实远端任务路线。下一步应补上述实际验收证据及必要的受限状态，不能用 Apple 的成功流程替代四端构建或 Android 真机验收。
