# Apple 连续互通：实际操作路由与平台条件

核查日期：2026-10-17。依据 Apple Support、用户手册和 Apple Developer 一手资料正文；未安装、连接或实操 Apple 设备。阅读对象是实际跨设备任务、平台条件和权限边界，不是 HIG 或玻璃材质。支持页会更新，本报告记录此次读取结果，不推断尚未核验的系统版本、地区开放时间或将来能力。

## 1. Mac 操作 iPhone：iPhone Mirroring 的具体边界

| 官方事实 | 可据此判断什么 |
| --- | --- |
| 基础条件是支持的 Mac（Apple silicon 或 T2，macOS Sequoia 15+）、iOS 18+ 且设有密码的 iPhone；两端同一 Apple Account 并启用双重认证，Wi-Fi／蓝牙开启，iPhone 锁定且在 Mac 近旁；Mac 不同时使用互联网共享、AirPlay 或 Sidecar；一次只用一台 Mac 与一台 iPhone。官方当前注明欧盟不可用。[设置与要求](https://support.apple.com/en-us/120421) | 这是带设备、账号、安全及位置条件的能力，不能只写“连接成功即可使用全部功能”。 |
| Mac 内置镜像应用可操作 iPhone 的真实屏幕和应用；退出镜像或解锁实体 iPhone 会停止镜像。镜像不能访问 iPhone 相机／麦克风，包括 Face ID 和电话；电话另走 Mac 通话能力。[操作与停止](https://support.apple.com/en-us/120421) | 原应用接续与专门通话链路分开；Apple 的“保持锁定仍可操作”不能被解释为本项目可绕过 Android 锁屏或应用认证。 |
| 官方演示从镜像中的 Photos 拖视频到 Mac，或把 Mac 的图片拖进镜像中的 Messages／Mail；也能拖入、拖出 iPhone Files。[跨设备复制](https://support.apple.com/en-us/120421) | 这是“远端真实应用 + 内容交接”。它不证明镜像应用另有原生相册数据页、远端文件系统挂载或自动编辑回写。 |

上述同一 Apple 页面还列有更高系统版本的附加操作；本报告只采用解决本次路由判断所需的基础条件，不把可变的最新版手册等同于本项目兼容矩阵。官方的欧盟限制未在该帮助正文中给出完整的账号地区／实际位置资格算法；不能补写成“改账号或切换地区即可用”，也不能推断何时开放。[官方要求](https://support.apple.com/en-us/120421)

## 2. 通知可达与原应用可操作并非同一状态

Apple 首次成功设置镜像后，Mac 可在镜像应用未使用、iPhone 不在近旁时接收其通知，条件是 iPhone 开机；iPhone 在近旁时，交互通知才会打开镜像中的相关应用。通知图标有 iPhone 来源标识，远端清除也会同步；用户可分别控制各应用是否显示。Mac 本机应用自己的通知与 iPhone 通知有不同来源；设置过 iPhone 通话的 Mac 收到来电通知，与镜像通知机制无关。[通知与实时活动帮助](https://support.apple.com/en-us/120684)

Apple 同时提供独立的 Text Message Forwarding：在同一 Apple Account、iPhone 开机联网且可发收消息的条件下，SMS／MMS／RCS 可出现在 Mac、iPad 等设备的 Messages；Messages in iCloud 还会维持完整历史。这是主控本机 Messages 的消息接力，不能归入通知点击后远控原应用。[短信转发](https://support.apple.com/en-us/102545)

## 3. Handoff、Universal Clipboard 与 AirDrop 的任务差异

| 能力与实际操作 | 条件／语义 | 对本项目的取舍建议 |
| --- | --- | --- |
| Handoff：在一端打开支持的应用并开始任务，再从另一端的 Dock／应用切换器接力入口继续。iPhone 有应用切换器底部入口，iPad 有 Dock 入口。[使用 Handoff](https://support.apple.com/en-us/102426) | 同一 Apple Account、Wi-Fi／蓝牙及 Handoff 开启，源设备解锁、近旁且任务在前台；目标也有支持的应用。[设置条件](https://support.apple.com/en-us/102426) | 保持“原应用接续”和“在本机打开”两种文案。本机接力需要具体应用或链接支持，不能把任意远端应用的状态称为可迁移。 |
| Handoff 由应用提供 NSUserActivity，声明活动类型、更新活动信息，在目标应用恢复；跨平台应用需共享开发者 Team ID。文档要求传递临时活动信息，文档本体通过其他机制共享。[开发文档](https://developer.apple.com/documentation/foundation/implementing-handoff-in-your-app) | 不是把原设备任意应用实例直接搬到目标系统；应用活动恢复与内容数据可达是两个问题。 | 不让 Handoff／应用合作成为本项目免 APK 远控的基础条件，也不为此追加编辑副本管理或自动回写。 |
| Universal Clipboard：在一台设备正常复制，在另一台正常粘贴；内容短暂保留，或被任一端下次复制替换。[通用剪贴板](https://support.apple.com/en-us/102430) | 近旁、同账号、Wi-Fi／蓝牙和 Handoff 开启；官方列举文本、图像、照片、视频等内容。[设置与使用](https://support.apple.com/en-us/102430) | 保留就近复制／粘贴与内容发送，不建立剪贴板历史中心。 |
| AirDrop：Photos／Files 选择内容 → 系统分享 → AirDrop → 选择接收者；接收方接受。需要近旁、Wi-Fi／蓝牙开启，使用个人热点时先断开；非联系人须开启相应可发现范围，新的系统组合还有 AirDrop code 条件。[iPhone／iPad 操作](https://support.apple.com/en-us/119857) | 是明确的内容发送／接收流程；不能把已分享一张照片理解为获得远端图库浏览授权。 | 专用文件／相册页服务浏览、选择和手动取用，系统分享服务已取得内容的下一步；不要让发送一份内容自动开启备份或后台全量下载。 |
| Mac 可通过应用分享或 Finder 的 AirDrop 发送；同账号的自有设备可自动接收，接收内容进入 Photos、Files 或 Downloads 等实际位置，取决于内容及设备。[Mac AirDrop](https://support.apple.com/guide/mac-help/mh35868/mac) | 官方还说明已经开始的传输离开近距离后可继续通过互联网；这是 Apple 的能力。 | 成功反馈应给出本机真实保存位置／打开入口。本项目只有已有可达网络路径，不承诺复制 AirDrop 的互联网续传或自动穿透。 |

Handoff 的基础支持范围、Universal Clipboard 的系统门槛、镜像与其他连续互通功能各有独立要求；Universal Control 的对象是 Mac 及其他 Mac／iPad，Sidecar 是把 iPad 用作 Mac 第二显示器。这些不应冒充手机主控访问 iPhone。[连续互通功能要求](https://support.apple.com/en-us/108046)

## 4. 通话具有独立入口，也具有独立依赖

Apple 的蜂窝通话接力让 iPhone 转接通话到同账号的 Mac／iPad：基础路径要求 iPhone 有已启用运营商套餐、开机近旁、两端同网络，并分别开启 Calls on Other Devices／Calls from iPhone 及相关 FaceTime 设置；无需从镜像中的电话应用完成全部操作。主控可从来电通知接听／拒接，也可通过 Phone（macOS／iPadOS 26+）、FaceTime 或其他应用中的号码拨出。通话可交回 iPhone；iPhone 不在近旁时另需 Wi-Fi Calling 路线。[通话设置与操作](https://support.apple.com/en-us/102405)

## 5. iPhone／iPad 的 FaceTime 远程控制

不能写成“Apple 没有手机控手机”。Apple 官方 iPhone 与 iPad 手册均提供 FaceTime 远程控制：在一对一音频／视频通话中共享屏幕后，请求控制；对方接受后可点击、滑动并用屏幕键盘操作。两端需要 iOS／iPadOS 18+，控制者须在被控者联系人中；被控者本机操作优先，可随时停止；结束通话同时结束控制与屏幕共享。修改账号／Face ID、支付或抹除设备等可能受限，远控期间 Face ID／Touch ID 停用，欧盟当前不可用。[iPhone 操作](https://support.apple.com/guide/iphone/iph5d70f34a3/ios)、[iPad 操作](https://support.apple.com/guide/ipad/ipada92df253/ipados)

| 主控形态 | 已有官方证据 | 尚缺／不应混淆 |
| --- | --- | --- |
| Mac → iPhone | iPhone Mirroring 对已授权、近旁且锁定的 iPhone 提供真实应用操作及通知接续。[镜像帮助](https://support.apple.com/en-us/120421) | 一次一对，不能由此宣称 Apple 已提供任意多设备并发应用窗口或远程公网控制。 |
| iPhone／iPad → 另一手机／平板 | FaceTime 中有人参与并接受的屏幕远控；同时有 Handoff、AirDrop、Universal Clipboard、iPad 通话接力等各自路径。[iPhone FaceTime](https://support.apple.com/guide/iphone/iph5d70f34a3/ios)、[iPad FaceTime](https://support.apple.com/guide/ipad/ipada92df253/ipados)、[连续互通要求](https://support.apple.com/en-us/108046) | iPhone Mirroring 官方主控条件没有 iPhone／iPad。FaceTime 协助不能当成同账号、自有设备、锁定近旁且平时已授权的镜像工作台；未据这些资料确认移动端拥有等同 Mac 的后台 iPhone 通知接续。 |

以上“没有列入主控条件”限定于核查的 iPhone Mirroring 官方产品，不是断言 Apple 所有辅助功能、企业管理或第三方工具都不支持任何远控。FaceTime 资料的地区可用性也不能与镜像可用性合并；中国等目标市场须按对应功能另核查，不能从“非欧盟”直接推成全部可用。
