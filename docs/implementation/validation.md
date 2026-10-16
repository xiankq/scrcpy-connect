# 实施与真实验收记录

目标入口为 [.scratch/interop/goal.md](../../.scratch/interop/goal.md)。下列结果区分协议单测、真实被控 adbd 和 Android 主控界面；未列通过的能力不推定已完成。下列历史验收保留当时的后端和测试名；当前共享媒体结果以最新迁移小节为准，旧AudioTrack/自写MediaCodec证据不能冒充新后端结果。

## 当前环境

Ubuntu 24.04 x86_64；Rust 1.99.1；Flutter 3.47.6 / Dart 3.13.5；Java 21；Android SDK 36，NDK 28.2.13676358。三个独立 API36 x86_64 Google APIs AVD，经 KVM 加速无头运行：controller emulator-5554、target A emulator-5556、target B emulator-5558。官方 adb 仅部署/对照，产品仅经 Rust 直连。主控测试部署调试不构成产品使用条件。

测试转发：host 127.0.0.1:15556 → target adbd:5555；controller 经 10.0.2.2:15556 连接。现代无线 TLS 使用独立临时端口；配对码/私钥不入库。临时截图均在 /tmp/connect-avd、/tmp/connect-ui-visual、/tmp/connect-e2e。

## 已获得证据

| 范围 | 结果 | 复现入口 |
| --- | --- | --- |
| ADB 协议/服务 | 33 单测与11 transport测试通过，clippy -Dwarnings / fmt通过；坏帧、取消、超时、有界流/背压 | `cargo test -p interop-adb` |
| Android / iOS ADB源码编译 | x86_64-linux-android、aarch64-apple-ios cargo check通过；不是整包链接证据 | `cargo check -p interop-adb --target <target>` |
| 实际无线互通 | 错码拒绝→正确PAKE→STLS/TLS1.3→shell→重连shell通过 | `crates/adb/tests/android_wireless.rs` opt-in |
| 官方独立密码对照 | SPAKE2/exporter/GCM 及 TLS 和官方BoringSSL helper互通；实际UDP mDNS fixture通过 | `wireless_boringssl.rs`、`wireless_mdns.rs` opt-in |
| 设备生命周期 | 5项默认测试、实际型号/API/时间/shell/sync探测通过；旧attempt取消不影响新attempt | `crates/interop_core/tests/device_*` |
| 视频与真实任务 | 固定官方5.0.1 JAR推送执行、SPS/PPS/IDR、token拒绝、虚拟display启动Settings及clipboard往返通过 | `crates/interop_core/tests/scrcpy*` opt-in |
| 真实输入 | 读取实际UI控件坐标，经scrcpy触摸聚焦，英文注入与中文粘贴在被控UI XML中核验 | `scrcpy*` opt-in |
| 真实暂停/恢复 | 核验进程starttime及会话标记，SIGSTOP进入T且停帧，恢复重新出帧；断链监护自动解冻 | `scrcpy*` opt-in |
| 音频源 | 实采118 PCM包；已知880Hz输出采集，频谱与邻频能量比2344.8 | `scrcpy_audio.rs` opt-in；不等于主控播放验收 |
| 设置/恢复 | 原子校验错误不部分修改；导出无私钥，恢复不迁移信任、不自动连接 | `cargo test -p interop-core --test preferences_lifecycle` |
| Flutter UI | 57项widget当前全量通过（包含输入释放与旧队列回归）；页面/路由新要求正在迁移 | `flutter test` |
| Android首包/启动 | debug APK构建成功，主控AVD实际启动设备空列表，FRB加载正常，DTD hot reload通过 | `flutter build apk --debug --target-platform android-x64` |
| Rust core 跨端 | Windows x64 / iOS arm64 cargo check通过；macOS arm64也通过 | `cargo check -p interop-core --target <target>` |

## 实际发现并修复

- adbd EOF会连续发送尾WRTE，原单包状态误拒导致首次shell断连；改为有界尾包缓冲并按消费ACK。
- 聚合async命令future叠加导致默认测试栈溢出；对大handler Future加Box，默认栈真实scrcpy测试通过。
- Android没有桌面nusb枚举入口；走系统UsbManager授权并复制FD。物理USB尚无设备证据。
- native_toolchain_rust 1.0.7写死NDK API35；hook按runner最低API覆盖compiler/linker，避免把编译成功误当低版本兼容。
- 全屏退出控件点击手势会引发onPanCancel，旧逻辑误收起；仅实际拖动时处理取消。
- 文件发布与重命名原有复制/删除竞态：已用四ABI临时Rust助手的renameat2/renameat替换；FUSE原子发布、目录/链接/目标竞争与源竞争实测通过，缺失回执标为结果未知。

## 尚未通过或外部受限

- 当前目标AVD `ro.adb.secure=0`，AOSP在该模式接受任意TLS身份。未配对身份拒绝的负例明确失败；因此强制授权/撤权仍需安全配置设备验收，不能宣称通过。
- 纯Rust密码提供器为experimental，RSA时序风险与发布评估未解决，互通不能替代安全评估。
- Android实际Texture首帧、全屏点击、拖动收起、展开退出与HOME后台恢复已通过。native_audio_test现也通过实际暂停/恢复及两种HOME声音策略；外部应用AudioFocus争用、完整分享入站与故障矩阵仍待真实验证。
- macOS/iOS FRB最终链接尝试被本宿主缺Xcode SDK/xcrun阻挡；Windows FRB链接缺MSVC lib.exe。没有用Rust cargo check冒充Flutter四端整包通过。
- 免APK通知/通话扩展、资源仲裁、旧Android/OEM矩阵、物理USB和硬解/热功耗尚未完成目标验收。

## Android E2E

从 apps/connect 执行（要求两个AVD已准备并转发端口）：

```sh
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/product_flow_test.dart -d emulator-5554 \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

该脚本操作真实连接和渲染器；未提供端点时只验证启动/表单，不可计为远控通过。正式验收应保存命令退出码、设备能力与失败原因；截图不得放回designs/previews。

- 官方设计NPM lint：0 errors、26 warnings；5条为玻璃组件的扩展字段不在标准子token内，其余为颜色未在标准组件引用，不能写成零告警。
- 新增非UTF8真实文件名碰撞测试通过：不可解析条目path=null/canManage=false，不会误删合法replacement-character命名的另一文件。

## 后续安全与真实回归（2026-10-17）

- `INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 cargo test -p interop-core --test files_android -- --ignored --test-threads=1`：5项全部通过，25.74秒。覆盖真实push/pull哈希、当前批次冲突策略、取消后显式从零重启、非UTF8碰撞路径保护、FUSE原子发布/重命名。
- `cargo test -p interop-core remote_helper::tests --lib`：3项通过；含缺失/截断/矛盾回执必须返回`result_unknown`，不允许自动重试未知提交。
- 四ABI助手由`servers/helpers/build.py`构建，清单同时锁定源文件与每个产物SHA256；Android 16目标实际验证目录、链接、路径转义、并发无覆盖，以及共享存储。不是依赖系统`mv -n`的假原子实现。
- 原生USB选择器在系统授权前即登记待取消请求，按generation丢弃晚到广播；FD授权使用一次性lease，Rust复制后释放Java FD。物理USB缺设备，不能由编译/代码回归推定实物通过。
- 通话聚合状态无法保证具体call身份：真实快速替换来电负例证实旧观察ID不可靠。产品拒绝全局接听/挂断动作，展示`call_targeting_unavailable`与远控入口。安全逐通话控制仍是未完成项。
- 通知快捷回复原PendingIntent已被系统接受，但测试接收器未证明应用送达；界面明确“系统已接受，送达未知”，保留草稿并禁止一键重发。

多次端到端发现并修复的错误不能由某次进程退出0掩盖：早期一轮退出0的截图实际包含Missing video token，已修复暂停结果被误当新媒体启动；后一轮健康断言捕获首帧后暂停竞态。最终product_flow与下述真实HOME后台回归均通过，健康截图已逐一检查。

Android发现补齐：Activity可见与connectedDevice前台服务分别持有Wi-Fi MulticastLock，避免系统默认过滤多播而让Rust mDNS仅在桌面fixture成功。锁随对应生命周期释放；实际Wi-Fi/OEM发现仍须验证。依据[Android MulticastLock API](https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock)。

## 真实后台与目录验收

- `background_resume_test.dart`（host环境`CONNECT_E2E_BACKGROUND=1 CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_ADB=<SDK>/platform-tools/adb`，其他drive参数同上）真实退出0：主控HOME两秒→hidden/paused→设备capturePaused→主控Activity返回→streaming→之后原生session.frame→健康画面→退出。9秒测试；Screenshot `/tmp/connect-e2e/remote-after-actual-background.png`已目视无暂停/错误覆盖、全屏且唯一退出控件。
- 首次首帧失败的实际目标状态为`mWakefulness=Asleep`/display OFF；官方测试工具明确WAKEUP后无需更换decoder即可正常首帧。产品保持`power_on=false`，新增`device_asleep`状态与用户明确的`devices.wake`动作，不自动点亮实体屏，不绕过锁屏。
- 另一个初始暂停竞态已复现：Android inactive在session绑定前到达则不暂停，绑定后到达则误暂停。修复为inactive释放触点并关闭输入；真正hidden/paused/detached才暂停capture。回前台仍等实际frame，未用streaming状态假装新画面。
- `cargo test --workspace`默认全部通过，ADB44/core25（含remote_helper复用单测3）；需要实际设备的用例保持opt-in，另列真实执行结果。workspace全部target clippy `-D warnings`通过。
- 目录`files_tree_android`4项与既有`files_android`5项真实全部通过；目录场景覆盖内容/中文/空目录/零字节、local与remote symlink循环跳过、文件冲突、本批策略、整批取消、部分失败、目录keepBoth子路径映射、源最终变化检查。默认file_tree2与files_state3通过。
- 目录有界快照：10000项、64层、16MiB路径、120秒上限。保留已完成项、不删除目标额外内容，不宣称整个目录事务。远端秒精度stat仍无法证明同尺寸同mtime内容未变化。
- Android本机下载改为私有暂存，传输持久`destinationScope:privateCache`；“取回”与“保存到系统位置”分开，系统SAF通过下述真实验收，不以cache复制冒充保存完成。
- 新ADB真实验收：reverse完整双向TCP并发、JDWP、单路径LST2及Brotli/LZ4/Zstd压缩双向互操作通过；ABI交叉check Android两ABI/iOS/macOS/Windows通过。`81e3bd2`记录本批。
- 一次dev:服务探索对不可epoll文件触发官方adbd abort（API36指纹BE2A.250530.026.F3，错误epoll EPERM），系统重启丢失host转发；已移除泛化文件API/测试，未改权限或重启adbd，恢复测试端口后真实回归通过。文件传输继续只走sync。
- 免视频剪贴板companion真实2项通过：Unicode往返、独立companion写入触发Binder事件与启动中断开。默认校验1项及原通知实时回归通过；主控自动同步协调仍在实施。
- 显式隔离休眠用例通过：`INTEROP_ALLOW_DEVICE_SLEEP_TEST=1 INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 cargo test -p interop-core --test device_lifecycle sleeping_target_requires_explicit_wake -- --ignored`。目标Asleep/Dozing时`session.start`返回`device_asleep`且不创建会话，用户明确`devices.wake`后实际回到Awake；没有声称该用例验证了密码锁或生物认证。
- 取消连接回归改为分别核验网络和持久化：新attempt socket必须2秒内真实EOF，旧attempt取消不得关闭它；磁盘fsync另给20秒期限，避免繁忙宿主把持久化慢误报网络取消失败。默认5项通过。

## 系统文件选择器真实验收

`native_documents_test.dart`配合host `CONNECT_E2E_DOCUMENTS=1`，第二轮真实退出0，4分38秒。主控AVD实际DocumentsUI三次选择，未替换ContentResolver或provider。隔离fixture `/sdcard/Download/interop-documents-1792170084903`：

- ACTION_CREATE_DOCUMENT导出文本；host独立读实际共享存储字节核对。
- ACTION_OPEN_DOCUMENT_TREE导入source目录；应用实际读私有cache文本并核对empty空目录。
- 重新选取父目录导出整个cache目录；host独立核对sub/one.txt及empty空目录。

修复provider按返回URI树形态误判源类型，现按源lstat结果确定单文件／目录分流。第一次失败为操作员VM查询挂起导致2分钟选择预算超时；取消正确回收选择器，未观察到产品原生崩溃。第二轮仅将测试操作预算改为4分钟、总14分钟，所有字节和目录断言保留，最后一轮核验ack后driver立即结束以避免VM关闭竞态。

复现参数与前述drive相同，改target为`integration_test/native_documents_test.dart`并增加`CONNECT_E2E_DOCUMENTS=1 CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_ADB=<SDK>/platform-tools/adb`。driver打印隔离目录，操作者在真实系统选择器选择该目录；操作脚本与XML/PNG均在/tmp。本轮仅证明API36本地ExternalStorageProvider；云provider、拒绝/进程回收、大文件、API24/25目录安全遍历仍未通过。SAF不承诺provider原子覆盖，部分或未知结果不会显示完整保存。

## 三AVD剪贴板、声音与五种视频编码

- `native_clipboard_test.dart`真实退出0/1分30秒：主控5554、目标5556:15556和5558:15560独立userdata；本机Clipboard→A、独立host Rust Runtime改A→本机、跟随B后A不能覆盖、固定A后焦点B不改变目标、HOME期间自动读/写/发送计数零变化，回前台核对实际值，禁用后不再同步并还原测试内容。使用`CONNECT_E2E_CLIPBOARD=1`、`CONNECT_E2E_CLIPBOARD_CLIENT=<repo>/target/debug/examples/clipboard_fixture_client`及SECOND_PORT=15560；工具须先`cargo build -p interop-core --example clipboard_fixture_client`，只作隔离测试、不进入产品。
- `native_audio_test.dart`真实退出0/13秒：实际AudioTrack首次写入、去重、音量/静音、pause后trackPlayState=2且稳定期head/bytesWritten不增、resume后playState=3且写入继续；HOME默认停止播放，主动backgroundAudio后继续写入，系统dumpsys确认`isForeground=true types=0x00000012`包含mediaPlayback。首次host断言误找旧字段foregroundServiceType，修为兼容实际types字段后复用相同APK通过，产品未靠修改状态绕过断言。命令增加host`CONNECT_E2E_AUDIO_LIFECYCLE=1`及Dart define同名=true。JVM7项另测焦点租约共享、永久loss、旧gain不复活与pause/flush/play失败回收；这些不是实际外部App抢焦点证明。
- 所有native音频状态携带单调revision，core拒绝迟到旧回执覆盖新状态；手动/焦点/后台暂停分别保留。暂停期间在途PCM丢弃、不排队回放，默认无mediaPlayback后台资格，用户主动开启才动态声明该FGS类型。
- `native_video_codecs_test.dart`真实退出0/26秒：H264/H265/AV1/VP8/VP9均经过实际目标encoder枚举∩本机MediaCodecList、逐设备质量保存、产品RemotePage实际首帧/Texture、截图和悬浮退出。实际decoder分别为c2.goldfish.h264.decoder、c2.goldfish.hevc.decoder、c2.android.av1-dav1d.decoder、c2.goldfish.vp8.decoder、c2.goldfish.vp9.decoder。AVD的hardwareAccelerated标志不等于物理硬解验收。
- 五张`/tmp/connect-e2e/remote-codec-*-live.png`已逐张目视：都是全屏和唯一悬浮退出，无错误覆盖；HEVC文字明显更糊；独立官方JAR日志、码流与FFmpeg已确认请求1280触发目标软件编码器约束，实际230×512，改为1080后486×1080。见[专项证据](../research/hevc-emulator-constraints.md)。不能把五种渲染成功写成五种视觉质量均通过；已补1080选项与画质页实际码流尺寸，界面仍待新包复核。
- 独立Rust真实codec用例另对五格式各解码出324×720 PNG、单次H264覆盖288×640，验证无效encoder不打断旧会话；固定FFmpeg7.0.2-static测试工具SHA为e7e7fb30477f717e6f55f9180a70386c62677ef8a4d4d1a5d948f4098aa3eb99，来自临时imageio-ffmpeg0.6.0，不是产品依赖。质量改变只保存下次打开，旧会话不隐式重建。
- 当前core五target check通过：Android x64/arm64、iOS arm64、macOS arm64、Windows x64；iOS专属USB未实现，已将未使用adopt_usb按平台隔离。仍不代表FRB最终链接或四端Flutter整包通过。

## 输入释放、实际尺寸与资源预留补充

- 当前Flutter全量57项通过，新增持键退后台释放、迟到输入不进入新会话、排队UP在stop前flush等回归。真实目标dispatchKeyEvent计数接收器已编译，尚未运行；单测载荷不能代替目标真正收到UP。
- 画质页新增1080上限与每个正在使用会话的实际scrcpy尺寸；decodedWidth/Height只作诊断，不允许解码器padding覆盖远端输入坐标。新界面尚待页面拆分后重启验证。
- 资源模块默认5项、core默认39 passed/26 ignored及真实guard1项通过。实际guard以1条自身H264流+15个隔离测试预留填满应用16名额，拒绝新启动后旧会话ID和码流仍可用，失败/取消释放预留；这不是实际耗尽设备编码器。暂停并不释放名额或codec，不提示暂停后必然能开新会话。
- 固定scrcpy日志无法可靠提供MediaCodec数值错误，未知错误不重试。Android本机仅精确1100资源不足且未启动应用的全新整屏请求可单次降低该次负载；1101 reclaimed、应用任务已启动或未知失败不重放。原生自动降载和资源不足选择流程仍待运行验收。
- 用户追加Flutter组织要求：lib/pages下每页独立目录和*_page.dart；共享widgets/services/router保持浅层，业务导航迁移go_router。迁移中的旧57测试证据不推定新路由已经通过。

## 共享媒体迁移最新验收（2026-10-17）

- 首帧依据官方scrcpy开发文档和源码逐项对照，定位起播前同步waitFor0阻塞；静止补帧已在官方server启用，没有重复配置冒称修复。按MDK官方decoder优先级启用实际AV1路径。五编码共享视频完整生命周期12秒通过；删除267行RemoteVideoDecoder及Native视频入口后，真实产品五codec再测28秒通过。详见[完整实验与来源](../research/scrcpy-first-frame-and-latency.md)。
- 新共享状态确认每次请求后以正数1ms查询native状态；迟到Dart callback只触发实际查询。close先取消并排空确认再释放句柄。4项竞态回归与独立review通过；五codec各3次暂停/恢复，共15次实际像素恢复在15秒内通过，首帧本地1179/406/284/293/282ms（另计server启动），每种4次snapshot回执。
- 共享视频真实HOME2秒→返回Activity→capture恢复→snapshot→健康全屏通过；同session/relay旋转generation 1→2、新Texture/实际像素/Core触控尺寸同步与bridge.dispose正常结束通过。固定目标自动旋转条件后还原原值；稳定截图已目视检查方向和比例。空闲Rust事件观察者取消导致退出挂起的问题已修复，7项Rust接口测试与真实退出通过。
- 共享音频已接入，313行RemoteAudioPlayer删除。Native只负责OS焦点/耳机断开/FGS，Dart Player由进程Flutter engine持有、channel保持engine所有权、Activity弱引用转交UI适配；不宣称进程死亡可继续播放。直接真实PCM生命周期4秒通过：48000Hz/双声道、mediaInfo、native playing确认、源PCM与播放时钟前进；暂停clock采样每200ms为73/153/153/153/153/153ms，证明先短暂稳定后停止前进，恢复250ms后前进262ms。没有伪造bytesWritten或宣称物理扬声器可闻。
- 实际产品音频HOME两轮、Activity真实销毁再创建14秒通过：默认后台暂停，启用backgroundAudio后时钟持续前进且实际mediaPlayback FGS存在；新Activity身份与同一PID均由host实际dumpsys/pidof核对，Dart同一音源继续使用。系统setAlwaysFinish运行标志由独立host测试夹具调用并恢复；直接改数据库不能证明Activity重建。日志 `/tmp/connect-shared-audio-real-recreate.log`。补host结束前等待finally清理后，13秒复验通过；完成回执true、设置恢复为原值且临时archive不存在。最终日志 `/tmp/connect-shared-audio-recreate-final.log`，metadata `/tmp/connect-e2e/shared-audio-recreate-final/result.json`。
- 独立review发现取消的旧焦点获取回复可能释放新音源复用的epoch，已保持真实acquire/release barrier，包含调用超时后实际release仍pending的情况。22项音频测试先红后绿，独立复查通过。真实外部App焦点争夺另已先红后绿16秒通过：双设备同时播放、临时loss双方暂停/时钟稳定、gain保留其中手动暂停、永久loss关闭旧Core source与output，释放外部焦点不复活旧ID；用户新开取得新ID。首次失败捕获共享迁移只暂停但未终止旧捕获的回退，生产Bridge按sourceId+deviceId停止并释放，重复/迟到事件不能关闭替代源。日志 `/tmp/connect-shared-audio-focus-fixed.log`、metadata `/tmp/connect-e2e/shared-audio-focus-fixed/audio-focus-result.json`，独立fixture已卸载。长期后台/系统回收、扬声器/耳机物理输出与四平台最终链接仍需独立证据。
- 当前已完成生成typed routes/Notifier、78项app widget、严格分析、真实workspace only-check及Riverpod插件违规负例。Rust工作区133默认测试通过、41项设备/外部工具用例显式ignored；all-target clippy通过。Google DESIGN.md官方lint为0 errors/26 warnings/1 info。整合 `tool/check.sh` 第二轮已实际退出0：133 Rust/41 ignored、78应用与71桥接、生成检查、严格分析、插件负例及官方设计lint全部执行；首轮发现新增helper/driver的严格lint并修正。随后永久焦点语义修正又经分析与上述真实红→绿验证，不将其他历史证据自动继承为新版本全通过。

- 音频/engine整合后再次运行实际产品五codec，26秒通过；完成回执true，日志 `/tmp/connect-final-product-five-codecs.log`，metadata `/tmp/connect-e2e/final-product-five-codecs-result.json`。HEVC截图目视仍明显低清，与此前目标AVD软件encoder降尺寸现象相似；本轮未重新独立测量实际码流尺寸，不能把首帧可渲染当作五种视觉质量均通过。画质验证继续保留，未隐藏此缺口。

## 共享导入与桌面返回（2026-10-17）

- 外部独立分享APK经真实Intent/系统grant/可读pipe，进入共享Rust导入器与Flutter typed分享页。九模式验证文字、图片、多文件、外部provider别名，准确拒绝无grant/本应用URI/33文件/513MiB声明，慢源进入importing后可取消；逐文件校验实际字节/长度、消费后pending清空、未提交来源删除。超大来源提供真实AssetFD，由Rust容量检查拒绝，不依赖fixture自己抛异常，也不声称metadata查询前拒绝。
- 增加实际HOME与MAIN/LAUNCHER返回回归，先证实旧singleTop产生两个UI宿主且旧实例失去engine；singleTask后同一宿主经onNewIntent接收分享，Flutter Navigator状态保留。am start -W并不确认Flutter window focus，测试有界等待真实resumed；最终等待4ms。九模式+返回组合16秒退出0、shareAcceptanceComplete=true，日志/tmp/connect-share-acceptance-final.log，metadata /tmp/connect-e2e/incoming-share/result.json。图片分享页与返回后的设备列表截图均已目视，保留/tmp不进Git。
- 每个Activity独立持有发现锁；USB已交付fd仅精确Rust ACK关闭Java原句柄，无Activity仍可释放，未ACK上限16。重叠Activity生产协调器JVM端口测试与全Kotlin编译通过；物理USB与Wi-Fi多播环境未验。修复提交0cf1b66。
- 全仓严格Flutter分析无问题，Dart格式与diff检查通过。共享SAF新路径、实际分享提交到被控设备、恶意provider/压力/120秒deadline、外部分享打断系统picker的取消语义仍需专项，不以此九模式替代。具体边界及复现见[研究记录](../research/android-share-trust.md)。
