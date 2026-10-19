# 手机主控的中文输入与跨设备剪贴板

研究日期：2026-10-16。仅文档与源码调查，未运行原型。先查 Context7 的 Flutter 文档，再核对 Android、AOSP、scrcpy 及厂商一手资料。本文区分「事实」「工程建议」「待验证」，不更改已确认的免安装 APK／无 root、完整互联产品、直接操作且无查看模式等约束。Q23–27 的后台、设备级声音、真实任务接续、身份不自动迁移与通知默认实时策略沿用访谈结果；Q27 的可选通知历史随后已被最新范围取舍移除；剪贴板历史也没有因此成为产品目标。

## 最影响承诺的结论

1. **不能承诺普通 Android 主控 App 在后台无条件读取并自动广播系统剪贴板。** Android10+ 的读权限受焦点／默认 IME 等条件限制，FGS 不补齐这项权限；远端 shell 的权限不能转授主控 App。
2. **手机软键盘不是桌面键盘事件源。** 中文 IME 提供 composing、提交、替换、选区和删除等编辑操作；Flutter HardwareKeyboard 与 UHID 不能自动把这些操作接成完整跨设备编辑器。
3. **文本剪贴板与图片／文件剪贴板需要不同数据路径。** 当前 scrcpy wrapper 与 Flutter 标准 ClipboardData 均只覆盖文本；跨设备发送 URI 字符串不会连同数据、provider 和读授权一起迁移。
4. **厂商产品可作为普通用户体验参考，不能作为第三方 App 权限证明。** 已找到跨设备普通 Copy/Paste、镜像交互及图片／文件共享的官方依据；尚无足够官方资料证明手机软 IME 跨屏完整编辑语义。

## 主控普通 App 的剪贴板边界

| 情形 | 核实事实 | 工程含义 |
| --- | --- | --- |
| Android10+ 主控失去焦点 | 非默认 IME、非当前有焦点 App 不能读取剪贴板 | 退后台、分屏失焦、点到另一个 App 都要重新判断，不能以「Activity 可见／FGS 存在」代替焦点 |
| 注册剪贴板监听 | AOSP 在派发 listener 回调前同样检查读剪贴板权限 | 常驻 listener 并不保证后台能收到变化；回到前台只能重新读取当时内容，不能补回未知历史 |
| 被控 shell JAR | AOSP Shell 声明 `READ_CLIPBOARD_IN_BACKGROUND`；该权限是 `signature|role`，非普通应用可申请的运行时权限 | scrcpy 远端能读，不代表 Android 主控普通 App 能照搬；Rust／JNI 换语言不改 UID 权限 |
| 锁屏／工作资料／虚拟设备 | 当前 AOSP 另有设备锁定、用户与设备 ID 等检查 | Shell 也不是无条件读任何剪贴板；实际支持状态按系统与 profile 验证 |

来源：[Android10 剪贴板限制](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data)、[AOSP ClipboardService 的权限与回调检查](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/clipboard/ClipboardService.java)、[Shell manifest](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/packages/Shell/AndroidManifest.xml)、[权限 protectionLevel 定义](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml)。main 源码用于解释机制，支持承诺仍需锁定 Android 版本验证。

**事实补充。** CompanionDeviceManager 的普通设备关联也不能直接解决该权限：`DEVICE_PROFILE_APP_STREAMING` 需要特定 profile 权限，AOSP 将 `REQUEST_COMPANION_PROFILE_APP_STREAMING` 定义为 `signature|privileged` 且标明不供第三方应用使用。因此不能把“做一次配对”当成获得厂商互联权限的方案。[AssociationRequest](https://developer.android.com/reference/android/companion/AssociationRequest#DEVICE_PROFILE_APP_STREAMING)、[AOSP 权限定义](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/AndroidManifest.xml)。

**工程建议：** 设备连接的后台保持与剪贴板读取资格分别建模。UI 显示「当前设备可同步」「返回应用后可读取」「点按发送」等真实状态；不要用一个一直亮着的“双向同步”开关暗示后台读取持续有效。系统分享入口可承接用户主动发送的文本／图片／文件，补充跨 App 流程，但它不是后台全局监听的替代权限。

### 系统预览、读取提示和敏感标志

**事实。** Android12+ 首次读取其他 App 的某条剪贴板数据可能显示读取 toast；`getPrimaryClipDescription()` 不触发该读取提示。Android13+ 写入剪贴板后有系统复制确认／预览，平台还会自动清理一定时间后的内容；应用不应再叠加重复的“已复制”toast。[Android12 读取提示](https://developer.android.com/about/versions/12/behavior-changes-all#clipboard-access-notifications)、[复制反馈规则](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste)、[Android 剪贴板安全指引](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling)。

**事实。** `ClipDescription.EXTRA_IS_SENSITIVE` 是隐藏／遮蔽预览的提示，不改变剪贴板访问权限，也不禁止另一个应用或同步程序转发。未标记不代表内容不敏感。当前 scrcpy wrapper 只取第一项 text，设置时用 `newPlainText`，不会把整个 ClipDescription、敏感标志、MIME 与 item 列表作为原剪贴板传输；Flutter `ClipboardData` 当前也只支持 plain text。[EXTRA_IS_SENSITIVE API](https://developer.android.com/reference/android/content/ClipDescription#EXTRA_IS_SENSITIVE)、[scrcpy ClipboardManager 源码](https://github.com/Genymobile/scrcpy/blob/master/server/src/main/java/com/genymobile/scrcpy/wrappers/ClipboardManager.java)、[Flutter ClipboardData](https://api.flutter.dev/flutter/services/ClipboardData-class.html)。

**工程建议：** 扩展协议保留来源设备、内容版本、类型及可取得的敏感元数据；主控写本地剪贴板时保留相应遮蔽标志。标记敏感的内容默认不自动跨设备发送、不生成正文预览、不写日志；用户主动发送仍需清楚显示目标。现有 scrcpy 文本事件不足以可靠识别远端敏感标志，不能在尚未扩展和验证前宣传“自动过滤所有密码”。也不应为避免系统提示去使用平台专有的隐藏权限。

自动清理／clipboard 变化要视为版本失效：不得周期性把旧缓存写回以“保活”，否则会复活用户已删除内容并反复覆盖新复制内容。跨设备写入、对端回传会形成回环，需来源 ID 与事件去重；内容相同的用户再次复制仍可能是一次新意图，不能只靠永久字符串去重。

### 多设备与图片／文件

**工程建议：** 键盘焦点属于控制会话，系统剪贴板通常属于主控系统的当前剪贴板；二者不要混成“所有在线设备”。为发送操作绑定明确的目标设备／display／会话 generation，在提交前重验焦点。切设备、打开主控搜索框、弹出授权页时，不把上一字段尚未完成的 composing 或粘贴命令发送到新设备。多窗口中只有正在输入的窗口接收本次输入，后台设备复制来的内容不应悄悄覆盖该窗口准备粘贴的内容。

**事实。** Android ClipData 可以含文本、URI、Intent 和多个 item。URI 的可读性依赖本机 ContentProvider 及授权；AOSP 对接收读取者执行 URI 授权，剪贴板替换时也管理授权释放。接收图片的编辑器要支持相应 MIME／receive-content 或 IME `commitContent`；API25+ 的 IME 图片提交可携带临时 URI 读权限。[Android copy/paste](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste)、[AOSP URI grant 实现](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/clipboard/ClipboardService.java)、[Receive rich content](https://developer.android.com/develop/ui/views/receive-rich-content)、[Image keyboard support](https://developer.android.com/develop/ui/views/touch-and-input/image-keyboard)。

**工程建议：** 主控先在拥有读授权时取得内容，再按传输任务发送字节；接收端重新发布为本机可读 URI，并给最终目标应用合法读取资格。不要把 `content://` 或文件路径当可跨设备访问的链接。临时 JAR 没有自动注册的 FileProvider；被控端如何在免 APK 前提下提供可供目标 App 读取的媒体／文件 URI，需独立验证。接收应用不支持粘贴该 MIME 时，提供保存／分享给应用的正常入口，不假报“粘贴成功”。图片复制也不能简单退成 URI 文本粘贴。

## 中文软键盘：三条链路必须分别验证

**事实。** Android 明确要求不要依赖软 IME 产生 KeyEvent；Flutter HardwareKeyboard 处理的是实体键盘。`InputConnection` 支持提交／组合文本、选区、周边删除、editor action 与内容提交，这些不等于按下某个物理键。[Android KeyEvent](https://developer.android.com/reference/android/view/KeyEvent)、[Flutter HardwareKeyboard](https://api.flutter.dev/flutter/services/HardwareKeyboard-class.html)、[InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)。

| 链路 | 已证能力与未证部分 | 普通用户体验 |
| --- | --- | --- |
| 点击远端画面里的软键盘 | 触摸经远端注入，让远端自己的 IME 与目标编辑器完成中文组合、候选选择、选区与删除；实际注入／安全画面仍需兼容验证 | 不增加查看模式，保持直接操作；使用远端输入法、词库与键盘布局 |
| 主控常用软键盘 → 提交文本 | Flutter 可接本机 IME 编辑状态；Unicode 文本可尝试经远端剪贴板＋Paste 提交。普通 scrcpy SDK text injection 字符范围有限 | 候选与本机词库在手边，但“提交一段文字”不等于自动同步远端光标、完整原文和 composing；不能承诺密码框／禁止粘贴字段都可用 |
| 实体键盘 → UHID → 远端 IME | scrcpy UHID 支持 IME、无线传输；旧被控系统可能权限失败，需配置远端物理键盘布局。AOA 仅 USB | 适合接外设场景；不能因它支持中文就声称主控任意软键盘已接通同一路径 |

来源：[scrcpy keyboard](https://github.com/Genymobile/scrcpy/blob/master/doc/keyboard.md)、[scrcpy copy/paste 行为](https://github.com/Genymobile/scrcpy/blob/master/doc/control.md)。上述是输入链路的工程区分，不是让用户切换查看／操作模式；默认与具体入口仍需实机和厂商交互验证。

### composing／Delta 能解决本机编辑观察，不能自动解决远端编辑

**事实。** Flutter `DeltaTextInputClient` 搭配 `enableDeltaModel=true` 接收细粒度更新，包括插入、删除、替换及只改变 selection／composing 的更新，默认 delta model 为 false。Delta 包含 oldText、selection、composing 等状态。它描述本机输入客户端，不会自动取得另一个设备目标 App 的 InputConnection。[DeltaTextInputClient](https://api.flutter.dev/flutter/services/DeltaTextInputClient-mixin.html)、[enableDeltaModel](https://api.flutter.dev/flutter/services/TextInputConfiguration/enableDeltaModel.html)、[TextEditingDelta](https://api.flutter.dev/flutter/services/TextEditingDelta-class.html)。

**事实。** 当前 scrcpy 控制消息有 key、text、touch、clipboard、UHID 等类型，设备回传有 clipboard／ack／UHID output；这些接口没有通用的目标编辑器原文、selection、composing／InputConnection 镜像协议。Android 的常规自建 IME 需要应用 manifest 声明 InputMethodService 等组件；不能把“加一个 IME APK”偷偷当成临时 JAR 实现的一部分。[ControlMessage](https://github.com/Genymobile/scrcpy/blob/master/server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java)、[DeviceMessage](https://github.com/Genymobile/scrcpy/blob/master/server/src/main/java/com/genymobile/scrcpy/control/DeviceMessage.java)、[Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)。

**工程建议：** 本机桥接先作为输入客户端建模，处理组合中／已提交、replace、delete、action 和焦点 generation；不要按 onChanged 的字符串长度差发送若干退格与字符。UTF-16 code unit、Unicode code point 与可见 grapheme 长度不同，emoji 肤色／家庭组合等尤其不能用“一个字符＝一次退格”。如何与远端字段对齐、能否安全桥接已存在的编辑器、能否自动判断输入类型，属于实现调查与 POC，不应让用户选择算法或被要求理解这些术语。

### 密码、粘贴与回车没有统一成功条件

**事实／边界。** Android InputConnection 的 `commitText`、`setComposingText`、`setSelection`、`deleteSurroundingText`、`performEditorAction` 是不同操作；`sendKeyEvent` 还可能因异步焦点变化落到另一个 view。scrcpy 官方也明确 Copy/Paste 快捷键由当前目标 App 决定，不能保证每种应用都同样处理。[InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)、[scrcpy control](https://github.com/Genymobile/scrcpy/blob/master/doc/control.md)。

**工程建议：** 密码框不等于一律禁止粘贴，禁止粘贴也不等于禁止真实键入；应按实际字段能力处理，不能承诺一种剪贴板方案覆盖全部。不能把本机中转的密码／验证码写入普通草稿、诊断日志或剪贴板历史。Enter／换行／发送／搜索／完成要区分，默认不把本机提交文字直接等同点击远端“发送”。目标 App 未反馈时用“已发送到设备”与可见结果区分，不以传输 ack 宣称目标编辑器已经接受。

## 厂商官方交互参考与证据缺口

| 厂商 | 能支持的产品观察 | 不能据此声称 |
| --- | --- | --- |
| Samsung | 官方指导是设备1长按选择复制、设备2在目标文字区长按粘贴；支持 Galaxy 手机／平板，同账号、Wi-Fi、蓝牙及 Continue apps 条件 | 不证明第三方 App 可后台读剪贴板；也不证明所有图片／文件 MIME 与多设备焦点争用的处理 |
| Xiaomi | 官方互联隐私说明列 Home screen+ 镜像跨设备操作、共享剪贴板文字／图片／文件和跨设备键鼠 | 没有给出足够细节说明手机软 IME 的候选、选区、密码框在跨屏场景如何同步 |
| OPPO | 官方说明平板与手机的 ColorOS 内置 Connect 支持镜像、拖放文件和剪贴板；用户在设备／应用上下文完成操作 | PC 鼠标键盘描述不能直接推广为手机软键盘链路，系统内置能力也不是第三方权限保证 |

来源：[Samsung 官方跨设备复制粘贴](https://www.samsung.com/us/support/answer/ANS10003445/)、[Xiaomi 官方互联隐私说明](https://privacy.mi.com/Miinterconnectivity/en_US)、[OPPO Connect 官方说明](https://www.oppo.com/en/newsroom/stories/oppo-connect/)。只采用厂商正文，没有把社区发言当官方实现证据。本轮未找到足以还原手机／平板中文软键盘底层链路的官方公开技术说明；后续需要真机体验或更具体的官方手册，不能填补为已知结论。

## 后续 POC 与只涉及体验的决策

本轮未执行下列 POC。技术细节和常规默认由代理依据后续授权选择，先形成可观察体验与限制；只有实验证明现有授权无法涵盖的实质取舍才回到用户。

| POC | 必须观察的结果 |
| --- | --- |
| C1：剪贴板权限与焦点 | Android API24–28、29–32、33+及当前目标版本；前台／分屏失焦／后台／锁屏／profile。观察 listener、实际读取、恢复前台后的当前值；验证不会虚报后台同步 |
| C2：系统反馈与敏感内容 | 普通／敏感 text、复制来源不同、两端预览／读取提示、自动清理、手动清空、两设备循环；确认不会复活旧内容、丢失敏感标志或刷屏 |
| C3：本机中文与远端编辑 | 至少 Gboard 中文与一种厂商 IME；拼音候选替换、语音／手写、emoji、选区中间插入、撤销、长按删除、密码／禁粘贴、WebView、自绘输入框、远端 IME、外设 UHID；切控制会话时不得错发 |
| C4：图片／文件 | 多 item、MIME、临时／撤销 URI grant、来源 App 退出、接收编辑器不支持、大小限制、跨设备重新发布 URI、取消／断连后的缓存回收。明确哪些是可粘贴内容，哪些需转到保存／分享 |
| C5：完整交互 | 真机比较厂商手机／平板互联中的键盘弹出位置、遮挡、候选与焦点；与本产品候选链路对照，不引入查看模式，不靠 desktop scrcpy 演示冒充手机体验 |

## 当前默认与剩余验证

1. **现行同步对象：** 当前操作且开启自动同步的设备；切换到该设备时以其文本覆盖主控剪贴板。不提供固定对象、冲突选择或独立发送设置页。C1/C2 仍用于核验权限、焦点与循环，产品规则见[交互规则](../../designs/prod/interaction-rules.md#声音与剪贴板)。
2. **权限受限的默认由代理落实：**不在失焦或后台状态虚报自动读取，不轮询抢回剪贴板；用户回到前台或明确复制／发送时再按系统许可处理。两端内容与来源、敏感标记、到期和失败需要可辨，不建立历史中心。C1/C2/C4 决定可执行的具体状态。
3. **本机输入与远端输入并行研究：**验证本机常用 IME，保留画面内远端键盘；若只能可靠提交一段文字，则按真实能力呈现，不承诺所有字段无感。密码与禁粘贴字段、焦点切换不得旁路认证，不新增查看模式或主控调试。C3/C5 驱动对应设计状态。

执行入口见输入任务（历史路径 `../../.scratch/interop/issues/08-mobile-input-and-windows.md`）与剪贴板、音源和分享任务（历史路径 `../../.scratch/interop/issues/13-device-targets-and-sharing.md`）。

## 补充：主控通过本机 ADB 启动 shell 辅助进程

本节保留曾调查的候选路线。**Q33 用户已明确否决：主控始终不要求开启调试，因此本项目不提供该增强入口。**以下源码事实不构成实施建议；既定被控设备 ADB 方案不受影响。

**事实：有现成一手实现，不能再把主控后台剪贴板概括为没有可行路径。** LADB 的官方 README 说明其内嵌 ADB 经无线调试连接本机；`ADB.kt` 实际执行 `pair localhost:配对端口` 与 `connect localhost:连接端口`，`DnsDiscover.kt` 用 NSD 发现 `_adb-tls-connect._tcp`。这是 Android11+ 无 root、无外部电脑自连接的现成实现证据，并非 AOSP 对所有手机的兼容承诺。[LADB README](https://github.com/tytydraco/LADB#how-does-it-work)、[本机连接源码](https://github.com/tytydraco/LADB/blob/main/app/src/main/java/com/draco/ladb/utils/ADB.kt)、[端口发现源码](https://github.com/tytydraco/LADB/blob/main/app/src/main/java/com/draco/ladb/utils/DnsDiscover.kt)。

**额外前提与恢复限制：** 主控本身需开启开发者选项和无线调试，允许所用网络，并首次输入系统配对码／配对端口；LADB 要求配对设置对话框在完成前保持打开。配对端口与正常 TLS 连接端口不同，后者由系统随机选择；重启／重新启动无线调试后应重新发现，不能保存端口当身份。`localhost` 避免数据绕行路由器，却不使系统无线调试的 Wi-Fi 前提消失：AOSP Android11 在 Wi-Fi 关闭／断开时会停无线调试，热点单独开启、仅蜂窝或完全离线能否启用不能据此保证。Android17 的 ADB Wi-Fi2.0 改善可信网络自动重连，仍需按版本／厂商验证。Android10及以下的官方 TCP 路径需先由已授权 USB 主机开启，不能宣传同样的纯本机首次配对。[官方 ADB 无线说明与旧版本前置 USB 流程](https://developer.android.com/tools/adb#wireless)、[AOSP TLS／mDNS／动态端口架构](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/adb_wifi.md)、[Android11 Wi-Fi 生命周期源码](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android11-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java)。

**工程推论：可复用本项目 Rust ADB 协议能力连接主控自身，经 `adb shell` 临时启动本机 JAR，代理主控剪贴板监听／读取。** 生产设备 adbd 降权至 `AID_SHELL`，由它启动的辅助进程以 shell 身份工作；Shell 的后台剪贴板权限与普通 App 的 UID 权限是两套资格，结果经受控本机通道交回 App，不是把 shell 权限授予 Flutter。须沿用正确 shell 调用身份、检查实际 UID／Binder 调用、锁屏／profile 和 OEM 限制。这是待 POC 的组合方案；本机 shell 或 scrcpy 的按键／粘贴能力仍不能证明已获得任意 App 的完整 InputConnection。[AOSP adbd 身份处理](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/daemon/main.cpp)、[Shell 权限](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/packages/Shell/AndroidManifest.xml)、[剪贴板服务检查](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/core/java/com/android/server/clipboard/ClipboardService.java)。

**仍需验证：** 配对授权持久化与端口重发现、mDNS 失败回退、Wi-Fi／热点／切网、锁屏、主控 App 被回收、adbd 停止及重启后的 JAR 重新启动与单实例归属；辅助进程存活不等于 App 的后台网络／调度限制消失。配对信任通常可保留，“重启后重新启动辅助进程”不等于每次重新配对，只有授权失效／撤销等情况才需重新授权。Shizuku 的官方手册同样给出 Android11+ 本机无线启动、一次配对、重启后重新启动及 OEM 后台差异，可作第二份一手运行经验；不能由此承诺永久免维护常驻。[Shizuku 官方手册](https://shizuku.rikka.app/guide/setup/)。本轮未配对、安装或启动任何辅助进程，也未将 LADB 选为依赖；当前 LADB main 的 LICENSE 含 Google Play 分发限制，不能仅凭“GPL”标签推定可直接复用。[当前许可证](https://github.com/tytydraco/LADB/blob/main/LICENSE)。

**现行边界：** [ADR 0006](../adr/0006-controller-without-debugging.md)规定主控不要求开启调试；本机 ADB 方案仅保留为技术比较，不是可选产品入口。剪贴板按当前设备的自动同步开关处理，不提供固定对象。前台同步与系统分享分别受普通应用权限约束，远端 shell 的权限不属于主控。
