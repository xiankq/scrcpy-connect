# 实施与真实验收记录

目标入口为 [.scratch/interop/goal.md](../../.scratch/interop/goal.md)。2026-10-17的[完整重新核查](../../.scratch/interop/completion-reassessment.md)逐项纠正产品断链：本文件的历史实验通过不表示对应整个用户流程完成。下列结果区分协议单测、真实被控 adbd 和 Android 主控界面；未列通过的能力不推定已完成。下列历史验收保留当时的后端和测试名；当前共享媒体结果以最新迁移小节为准，旧AudioTrack/自写MediaCodec证据不能冒充新后端结果。

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

该脚本操作真实连接和渲染器；本轮已消除缺端点时静默成功的旧行为：缺少合法端点必须失败，完整链路结束才写产品完成回执，driver必须校验。新的实际回归结果另记，不能继承旧版本退出码。正式验收应保存命令退出码、设备能力与失败原因；截图不得放回designs/previews。

- 官方设计NPM lint：0 errors、26 warnings；5条为玻璃组件的扩展字段不在标准子token内，其余为颜色未在标准组件引用，不能写成零告警。
- 新增非UTF8真实文件名碰撞测试通过：不可解析条目path=null/canManage=false，不会误删合法replacement-character命名的另一文件。

## 后续安全与真实回归（2026-10-17）

- `INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 cargo test -p interop-core --test files_android -- --ignored --test-threads=1`：5项全部通过，25.74秒。覆盖真实push/pull哈希、当前批次冲突策略、取消后显式从零重启、非UTF8碰撞路径保护、FUSE原子发布/重命名。
- `cargo test -p interop-core remote_helper::tests --lib`：3项通过；含缺失/截断/矛盾回执必须返回`result_unknown`，不允许自动重试未知提交。
- 四ABI助手由`servers/helpers/build.py`构建，清单同时锁定源文件与每个产物SHA256；Android 16目标实际验证目录、链接、路径转义、并发无覆盖，以及共享存储。不是依赖系统`mv -n`的假原子实现。
- 原生USB选择器在系统授权前即登记待取消请求，按generation丢弃晚到广播；FD授权使用一次性lease，Rust复制后释放Java FD。物理USB缺设备，不能由编译/代码回归推定实物通过。
- 通话聚合状态无法保证具体call身份：真实快速替换来电负例证实旧观察ID不可靠。产品拒绝全局接听/挂断动作，展示`call_targeting_unavailable`与远控入口。安全逐通话控制仍是未完成项。
- 通知快捷回复原PendingIntent已被系统接受，但测试接收器未证明应用送达；界面明确“系统已接受，送达未知”。草稿及禁止一键重发只在该回复页仍存活时成立：离页重进会丢失Hook状态，不能据此宣布跨导航/重建保护完成，见重新核查A40。

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

## 全量核查后的实际页面回归（2026-10-17）

本轮全量缺口见[重新核查](../../.scratch/interop/completion-reassessment.md)，不把局部通过当整个目标完成。UI修复`1660805`：诊断页消费真实Rust JSON；首次编码允许runtime candidate，已知不可用继续禁选；远控独立消息作用域，上一页保存反馈不遮挡手机，当前会话资源调整仍可显示。

- 指定诊断/画质6项回归先红后绿；新增旧页面30秒SnackBar隔离测试先红后绿。整合后应用全量83项通过，严格全仓Flutter分析无问题，格式/diff通过。整合首轮遗漏confirm导入造成编译失败，修正后重新全量通过，日志`/tmp/connect-reaudit-app-tests-final.log`。
- 使用本文件Android E2E命令，把capture目录设为`/tmp/connect-e2e/requirements-reaudit-final`。本次20秒真实退出0：手动连接/非法端口校验、真实文件目录、实际设备详情→诊断、实际画质页首次H.265选择、下一会话确实H.265且`firstFrameDecoded=true/evidence=mdk.snapshot`，全屏/触控/退出拖动吸附展开/返回均通过。诊断、编码选择和最终远控图已目视；日志`/tmp/connect-requirements-reaudit-fullscreen-final.log`，result.json的产品完成回执true。
- 实际H.265码流230×512，截图仍明显低清；仅能证明页面选择到实际解码，不是视觉质量或低延迟验收。前一轮截图发现本地保存提示跨路由覆盖画面，独立作用域修复后最终截图已无此遮挡。动态玻璃/大字/读屏及完整IME仍未通过。
- `product_flow_test.dart`不再在缺端点时静默成功。正常完整结束才产出`productAcceptanceComplete=true`；通用driver要求该回执，保留独立audio/background/clipboard/documents模式。纯Dart契约`test_driver/integration_test_contract_test.dart`通过，`--missing-product`真实退出255；该检查已接入`tool/check.sh`。新增页面滚动按具体route/scrollable定位、等转换完成，点击未命中即失败。中间失败如实留在临时日志，没有降低健康/像素/对象断言换取通过。

本轮没有运行新的物理设备/四端整包/密码安全或当前共享SAF验收；多窗口、持续通知/认证/后台发布、安全通话、活动恢复/事件重取、完整文件/相册交付等仍是实现工作，不能称仅差测试。

## 保留多窗口与协作捕获暂停（2026-10-17）

范围：手机切换保留会话、窗口级工具/截图与当前共享播放器生命周期。完整前沿见[核查第10节](../../.scratch/interop/completion-reassessment.md#10-持续会话批次实际进展与未完成部分)，并非大屏并排或断线/进程恢复完成。

### 实际失败与修复

- START_APP之前等待首关键帧会卡住空虚拟显示；独立控制actor先发送应用启动后，实际单Settings启动由11.26秒失败变4.25秒通过。
- 真实主屏持续编码＋Settings启动通过4.74秒，但SIGSTOP暂停主屏＋Settings失败11.89秒。最小临时服务补丁保留Binder/控制线程，视频线程释放实际MediaCodec后在gate等待；同一真实回归5.71秒通过。见[协议/构建依据](../research/cooperative-capture-pause.md)。不把具体Binder死锁机制写成已证实。
- 新多窗口流程暴露HTTP配置完整但下一帧暂停时10秒误杀。真实TCP回归先失败10.30秒；取消配置组之间总超时，保留半包/首次输入/下一代消费者超时、配置容量限制与取消，12项TCP默认检查通过20.01秒。
- 恢复旧播放器与新generation提交并发导致取消。新增最小挂起恢复→提交新代测试先失败，改为逻辑会话持有呈现意图和队列，恢复跟随当前代；迟到回执不能覆盖更高generation。播放器18项、呈现协调15项通过。核心另测迟到ready只更新纹理而不覆盖确认暂停及资源状态。

### 真实UI与独立进程核对

在`apps/connect`运行，`PATH`包含本机Rust/Flutter，target5556已将15556转发到5555：

```sh
rtk proxy env CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/session-workspace \
  flutter drive --driver=test_driver/session_workspace.dart \
  --target=integration_test/session_workspace_test.dart -d emulator-5554 \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_DIAGNOSTICS=true
```

这是已准备端口的隔离双AVD媒体验收，不是未授权首次连接。测试通过真实页面打开主屏、Settings、Google Dialer，各退出后保留session且capturePauseMode=cooperative/captureStateConfirmed=true；从会话列表恢复原Settings，工具截该窗口最后显示帧，明确关闭Settings后恢复原Dialer。driver通过测试端等待的checkpoint，在各状态当时独立检查被控端process/cmdline，而非测试结束才推断截图时的进程。

完整运行退出0、40秒，8个独立检查点均通过：paused服务为S而不是T；Settings关闭后其进程消失，其余两个仍存活；最终Dialer实际Texture及MDK snapshot可用。回执`sessionWorkspaceComplete=true/pausedWindowsVerified=3`，日志`/tmp/connect-session-workspace-cooperative4.log`，JSON/PNG在`/tmp/connect-e2e/session-workspace/`。已目视会话列表、Settings截图和最终全屏Dialer；列表的包名/材质仍有产品呈现改进空间，未称视觉设计完成。

同一扩展下真实HOME/Activity返回13秒通过：增加`CONNECT_E2E_BACKGROUND=1 CONNECT_E2E_DEVICE=emulator-5554`，driver改`test_driver/integration_test.dart`、target改`integration_test/background_resume_test.dart`；回执`mediaAcceptanceComplete=true`，日志`/tmp/connect-cooperative-background.log`，图在`/tmp/connect-e2e/cooperative-background/`。

五编码改target为`integration_test/video_codecs_test.dart`，显式`CONNECT_E2E_ACCEPTANCE=media`，不设置BACKGROUND；45秒通过H264/H265/AV1/VP8/VP9的真实共享渲染。每种离开后确认paused，再只停止当前ID，保证下种编码创建新窗口而非误复用旧设置。日志`/tmp/connect-cooperative-codecs.log`，JSON/PNG在`/tmp/connect-e2e/cooperative-codecs/`；H264/H265图已比较，HEVC低清仍存在，不记视觉质量通过。通用driver默认仍要求product回执；media模式缺/false/错误类型回执同样失败，显式product失败不能被media掩盖，纯Dart契约通过。

### 源码、产物和默认检查

`servers/scrcpy/build.py --check`从固定源归档/补丁重建到忽略目录，实际输出SHA与受控产物一致：`91606a603a49bbea2be37ec500cde44a588483ac3162bc466d23b2f9d840deab`。JVM协议/gate检查通过，二者已接入`tool/check.sh`。CI配置安装JDK21/platform36/build-tools36.0.0；当前仅本机执行，不能称CI已绿。官方vendor JAR保持原样，新增Java仅在被控端临时运行，主控播放器仍为跨平台Flutter/fvp。

当前默认Rust工作区135 passed/43 ignored、all-target clippy、cargo fmt通过；严格Flutter分析无问题，真实workspace build_runner only-check通过。43项忽略用例须各自实际配置执行；默认通过不替代设备证据。FRB、companion其余产物门禁、旧系统/OEM/物理USB/HAL、四宿主整包、完整恢复、通知和液态玻璃仍开放。

最终应用全量91项、Bridge全量83项均通过，日志`/tmp/connect-session-final-app.log`和`/tmp/connect-session-final-bridge.log`。Rust日志`/tmp/connect-session-final-rust.log`，严格分析与生成日志分别`/tmp/connect-session-final-analysis.log`、`/tmp/connect-session-final-generation.log`。生成检查在隔离工作目录运行真实builder比对，控制器和typed route生成文件已经提交对应源；测试通过不代表上述开放任务完成。


## 事件缺口核验与编码会话边界（2026-10-17）

当前范围见 [恢复契约](state-recovery.md) 和 [完整核查第11节](../../.scratch/interop/completion-reassessment.md#11-事件缺口后的状态核验批次)。核心与桥接批次为 `cf35daf` / `3ee0318`，媒体边界 `d7d60d8`，应用 `591d48e`。不以本节关闭全产品目标。

### 默认及交错回归

- 工作区 `cargo test --workspace`：146 passed / 43 ignored / 0 failed，日志 `/tmp/connect-recovery-csd-workspace.log`。all-target clippy `-D warnings` 通过，日志 `/tmp/connect-recovery-csd-clippy.log`。忽略用例需真实 Android/外部工具，未计通过。
- 应用全量114项通过（`/tmp/connect-recovery-app-complete.log`）；之后新增终态迟到恢复保护，远控20项定向全部通过（`/tmp/connect-recovery-final-remote-tests.log`）。桥接全量93项通过（`/tmp/connect-recovery-bridge-complete.log`）。包含真实生成 provider、覆盖页面返回、冻结触点/按键/剪贴板、核验失败重试、短屏大字保留停止操作；widget 证据不替代实际手机权限或全局读屏验收。
- 严格全仓 Flutter analyze 通过（`/tmp/connect-recovery-final-analysis.log`），真实 build_runner only-check 通过（`/tmp/connect-recovery-generation-check.log`）。本批无新的FRB导出签名，不以此宣称正式FRB重生成门禁已补齐。
- 已实际先红后绿：设置发布、forget设置发布、设置保存旧回执、已消费分享的转发、companion旧list回执和已取消缓存、FRB真实256通道溢出及媒体配置边界。具体测试源纳入版本，不依赖临时日志才能复现。

### 真实流程中的失败与修复

首次真实流程在最后重试点击时触发测试监听器 expect 的异步 guard 冲突，改为记录后在测试主流程断言，未削弱实际状态条件。随后曾9秒通过，继续复验却捕获真实媒体故障；没有把这次通过当稳定验收。

失败 `/tmp/connect-recovery-repeat-2.log` 实际报告 `media_mux: AVC requires one SPS and bounded PPS records`；另一次先看到原始媒体 EOF→Core stopped，250ms poll 尚未来得及读取 relay 原因。HTTP真实TCP用例重现 `[session A,CSD A,session B,CSD B,keyframe B]`，旧实现拼接两会话 CSD、重复 SPS，实际失败。新 Dimensions 边界只保留本编码会话的配置；相同配置继续现有 HTTP，不同配置正确切换 generation/CodecPrivate。HTTP13＋mux6通过，未放宽单活动 SPS 约束或配置/半包限制。

### 修复后真实核验

主控5554→被控5556，使用已经准备的转发端点；target secure=0，不能证明未授权首次设置或强制认证。运行目录 `apps/connect`，PATH 包含本机 Rust/Flutter：

```sh
rtk proxy env CONNECT_E2E_ACCEPTANCE=media \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/recovery-csd-fixed \
  flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/state_recovery_test.dart -d emulator-5554 \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_DIAGNOSTICS=true
```

该流程使用生产 Bridge 的 `state.reconcile`，不声称在 AVD 人为挤满 FRB 队列。FRB溢出由真实容量默认测试独立验证。实际打开远控→两次同ID核验（含并发合并）→MDK真实snapshot→退出保留且捕获暂停→后台核验仍暂停→同ID重开→明确结束→重新检查仍不存在。修复后新APK首次11秒、同APK重复两次各10秒，三次均完整退出0，`stateRecoveryComplete=true/mediaAcceptanceComplete=true/endedSessionNotRecreated=true`，每次独立UUID、两次同ID实际恢复。日志 `/tmp/connect-recovery-csd-fixed.log`、`/tmp/connect-recovery-csd-repeat-{1,2}.log`；回执/图分别在 `/tmp/connect-e2e/recovery-csd-fixed/`、`recovery-csd-repeat-{1,2}/`。

恢复后的全屏画面与已结束状态图已实际目视，退出入口始终保留；结束状态清除旧Texture，标题明确“控制会话已结束”。早期图发现结束状态仍写“正在核验”，已修正并在真实断言中保留；截图等待点击提示消退，只保存在临时目录。本节不是液态玻璃、视觉质量、完整IME或大字读屏总体验收。


同一最终代码另回归：主屏＋Settings＋Google Dialer 三个真实会话保留/暂停/恢复/截图/单独关闭，40秒退出0，`sessionWorkspaceComplete=true`，宿主8次独立进程检查均通过；暂停进程为S、不是整进程冻结T，关闭Settings后其余两路存活。日志 `/tmp/connect-recovery-workspace-real.log`，8图及回执 `/tmp/connect-e2e/recovery-session-workspace/`。实际HOME→两秒后台→回前台→新MDK snapshot与健康全屏，11秒退出0，日志 `/tmp/connect-recovery-background-real.log`、图/回执 `/tmp/connect-e2e/recovery-background/`。代表会话列表、恢复全屏与结束状态已目视；列表仍有包名代替友好应用名、材质仍偏白卡，属于A06/A27/A29待补，不能把本次行为通过说成视觉设计完成。

## 再次逐指令审计及新增回归

本次稳定审计基准 `48c5003`。完整差距和每次可见用户输入对应见[重新核查第12节](../../.scratch/interop/completion-reassessment.md#12-再次逐指令复核当前交付远未完成)，新增A37–A42；不把工作转述为“只剩补测试”。已有77页独立分行/组件、Flutter工程化和删除旧自写播放器仍然成立；液态材质、完整状态、通知/通话/内容/恢复与四宿主交付仍未完成。

### TLS策略与真实协议负例

`8a91df6`引入独立于TLS配置的`TlsPolicy`。公开Client两项降级负例先实际失败，随后Required拒绝明文CNXN/AUTH且不发送RSA签名/公钥；真实TLS1.3正例、Optional legacy AUTH/CNXN及缺配置零握手共5项通过。Core恢复配对记录原先实际返回connected=true，修复后tls/GUID记录拒绝并且零设备服务请求。ADB默认49 passed/11 ignored，Core策略/连接生命周期7 passed/2 ignored；固定独立BoringSSL Required互通1项通过。现代新发现服务到Flutter表单仍有类型丢失路径，A37整体未关闭；安全adbd/撤权、生产密码成熟度及证书绑定也没有因此通过。

### 免APK持续观察的真实端点

`df2af2d`将设备持久观察意图与共享helper分开。连接成功自动建立通知/来电观察；stop真实注销listener并清除动作，保留剪贴板/媒体用途；代际隔离迟到数据，断线保留意图，显式停止不因列表/重连复活。新JAR SHA256为`0026e5af2db8558b2ba1eebac22c84303e20d3ee1a7b184bc683f808cf3889bb`。

API36目标`emulator-5556`、转发`127.0.0.1:15556`执行：

```sh
rtk proxy env INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  ANDROID_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  ANDROID_TARGET_SERIAL=emulator-5556 \
  cargo test -p interop-core --test observation_android -- \
  --ignored --exact connection_observes_without_page_queries_and_explicit_stop_survives_reconnect --nocapture
```

1项11.10秒通过，日志`/tmp/connect-reaudit-observation-real-ready.log`。独立生成唯一shell通知，核对不查询页面即可live、stop后clipboard allowStart=false读写仍有效、只读list不能重启、断线/重连仍stopped、显式start后真实Binder新通知事件；正常及失败路径精确清理/断开。首轮`/tmp/connect-reaudit-observation-real.log`在任何剪贴板写入前因没有文字ClipData明确失败，随后隔离AVD建立`observation acceptance baseline`文字基线，复验结束恢复该文字。不能声称首次失败也通过或已经精确恢复无ClipData。用例前置条件和清理已写入源码，现有未跟踪操作示例未擅自纳入Git。

同一新版JAR的原通知快照/更新/旧引用拒绝/远端清除真实回归1项3.28秒通过，日志`/tmp/connect-reaudit-notification-real.log`。不包含后台OS通知投递、锁屏/认证续接、回复实际应用送达、OEM或安全逐call控制/双向音频。

### 返回焦点、主标签核验和实际APK

`a117976`修复Remote路由返回/恢复时的当前设备焦点，旧/被覆盖窗口的迟到恢复不能抢焦点；专用页如Files/Workspace返回仍需统一设备上下文，A38不关闭。两条焦点回归先红后绿，日志`/tmp/connect-focus-{red,green}.log`。

设置/传输实际typed主标签接入核验提示。有效红为`/tmp/connect-tabs-recovery-red-verified.log`；320×640、2倍字号下重试、停止精确原活动/取消原批次均实际点击通过，绿日志`/tmp/connect-tabs-recovery-green-final.log`。最初fixture漏接事件的两轮结果未当作有效红绿。两个相关文件27项通过；合并App全量120项通过，`/tmp/connect-reaudit-app-tests.log`。严格分析首次捕获测试finally缺大括号，修正后`/tmp/connect-reaudit-analysis-final.log`无问题。

当前Rust workspace157 passed/43 ignored、all-target clippy通过（`/tmp/connect-reaudit-workspace.log`、`/tmp/connect-reaudit-clippy.log`）；该次默认执行启动后才新增`observation_android`，因此其opt-in设备结果以上面单独执行为准，不伪加为默认通过。build_runner only-check退出0，`/tmp/connect-reaudit-generated.log`。

合并APK重新构建安装，controller5554→target5556真实产品流程19秒通过：`productAcceptanceComplete=true`、`pageSelectedCodec=h265`，日志`/tmp/connect-reaudit-product-real.log`；结果和6张图仅在`/tmp/connect-e2e/complete-reaudit-current/`。诊断、实际全屏/侧边退出图已目视；实际码流仍230×512且低清，A10画质未通过。该流程使用准备好的legacy TCP端点，未验证现代首次配对、密码安全或全部产品功能。


### 显式观察入口与逐事件来电展示

`1236987`：通知/通话页的明确核验操作改为`observation.start`后只读刷新；页面打开与事件刷新不会重启已停止观察，starting仍显示未核验。Bridge在事件缺口pending期间阻止start，允许stop/status/list和真正只读列表。四种unknown/stopped页面组合先红后绿，重复点击只发一次start；Bridge门禁7项通过，日志`/tmp/connect-observation-gate-green.log`。

A42原先使用lastEvent触发来电，连续calls.incoming→observation.changed→settings.changed会丢提示，`/tmp/connect-incoming-stream-red.log`实际失败；改逐事件订阅后绿色。后台前已排队的回调必须被生命周期代次废弃，不能因后台→前台抢先恢复而弹出旧来电；有效红为`/tmp/connect-incoming-background-red-verified.log`。同帧、去重、未知来源、后台晚回调和销毁重挂载等communication11项通过，`/tmp/connect-incoming-stream-all.log`。这些是widget证据，不冒充真实PSTN来电或后台OS投递。

最终应用全量126项与Bridge全量93项通过，日志`/tmp/connect-reaudit-final-app.log`、`/tmp/connect-reaudit-final-bridge.log`；六个修改Dart文件格式检查零变更。生成检查`/tmp/connect-reaudit-final-generated.log`成功，随后app.dart只改无注解的事件订阅，不涉及生成输入。


该最终代码的严格全仓分析无问题（`/tmp/connect-reaudit-final-analysis.log`），最新APK重新构建安装后双AVD产品流程18秒退出0，`productAcceptanceComplete=true/pageSelectedCodec=h265`；日志`/tmp/connect-reaudit-final-product.log`，6图及回执在`/tmp/connect-e2e/reaudit-final-observation/`。实际再次目视全屏远控和返回工作台；前者仍230×512低清，后者仍偏白卡，继续判画质/液态材质未通过。该流程未加入真实来电及后台OS通知，不能把相应widget回归推定成设备端验收。


最后按Flutter工具要求启动普通`lib/main.dart`并实际发送`R`，回执`Restarted application in 1,375ms`；原生截图`/tmp/connect-reaudit-hot-restart.png`已目视为正常浅色设备列表空态，随后detach保留应用。重启阶段FRB打印两次旧Dart消息投递失败提示；不以此次启动截图证明全部热重启资源回收或完整恢复生命周期。


## 连接入口、设备归属与原通知回复闭环

本批持续修复上一轮A37/A38/A40，而非重新缩小目标。代码分为`fb6b69d`连接类型、`9f8448e`可见设备、`ebd9bcb`跨页回复及`06a6c99`独立接收验收四批本地提交。

### 连接与路由的红绿

发现kind=tls曾到表单/devices.add变普通TCP；Core又忽略transport。`/tmp/connect-transport-entry-red.log`中前7项为有效失败，初版pairing fixture的点击超出视口不算产品红，修正滚动后8项全绿。Core公开add→重启→显式tcp更新→连接必须仍TLS，非法transport不得写入；新增2项先红后绿，策略总4项通过。已有tls/GUID不能被表单或Core降级，新手动入口默认TLS；旧TCP明确选择，端口本身不决定安全类型。

工作台A→B→返回实际停留焦点B的红见`/tmp/connect-reply-focus-red.log`。共享可见设备声明后typed Workspace/Files/Gallery/Remote、follow/fixed及实际ClipboardCoordinator、late lookup替换、同帧核验及前后台资格6项通过，`/tmp/connect-reply-focus-route-green.log`。一次扩展夹具用非法inactive→paused跳转被framework拒绝，补齐hidden过渡后通过；不算产品缺陷，不是物理三机音频/剪贴板通过。

### 草稿和提交保护

`/tmp/connect-reply-focus-red.log`另外2项重现离页后accepted/unknown文字与保护丢失。修复应用级有界内存状态后，原通知revision变化、实际typed route原通知消失也先红后绿（`/tmp/connect-reply-revision-red.log`、`/tmp/connect-reply-route-red.log`）。新状态按device/id/revision隔离，最多64项/每项16384字符，不保存通知正文/标题历史或持久化草稿；满时保留未决提交，空未提交草稿释放空间。

独立只读审查继续发现并用4个真实失败覆盖：authentication_required明确未发送却被永久unknown锁住；resynced漏清被移除设备；恢复companion快照漏失效动作；空editing草稿占满。`/tmp/connect-reply-review-red.log`为7 passed/4 failed，修复后11项全绿`/tmp/connect-reply-review-green.log`。只有Main在PendingIntent.send前明确抛出的authentication_required/observation_required允许用户完成条件后再提交，Core仍重验原动作；过期/不可回复旧动作禁止使用，其他未知继续保护。恢复快照按devices及companions校准，迟到结果不能重建已删内容。

### 独立Android接收证据

旧JAR fixture脚本遗漏MediaJobs/Thumbnail导致编译失败，已修复源码集。严格receiver probe连续两次实际超时，目标日志两条`registerReceiverWithFeature: no app for null`已由主代理独立复核保存`/tmp/connect-receiver-probe-failure-evidence.log`；不是没测或skip通过。[固定AOSP分支](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-16.0.0_r1/services/core/java/com/android/server/am/BroadcastController.java#L291)要求对应ApplicationThread的ProcessRecord，旧裸shell测试receiver没有实际注册。原严格断言保留。

新增[临时通知测试APK](../../tool/e2e/notification_fixture/README.md)仅为独立原接收端；不进产品/companion，不新增被控安装前提。只在明确API36隔离AVD安装本次不存在的测试包、授予该fixture自己的POST_NOTIFICATIONS；有既有包就拒绝覆盖，精确清理并仅卸载本次拥有安装。主控/产品权限和AppOps均未修改。构建产物仅tmp，签名验证通过；独立manifest receiver从原RemoteInput结果key读中文/换行/emoji，AtomicFile记录run/id/原文/count，并在关闭run资格、取消PI后发布最终清理回执防止删除次数证据。

PATH已含本机Rust/Flutter；先在仓库根目录构建`rtk proxy python3 tool/e2e/notification_fixture/build.py`，再进入`apps/connect`运行：

```sh
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/notification-reply-final \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/notification_reply.dart \
  --target=integration_test/notification_reply_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

两轮分别日志`/tmp/connect-notification-reply-real.log`、`/tmp/connect-notification-reply-final.log`，均约16秒完整退出0，`notificationReplyComplete=true`。实际Flutter通知UI打开原动作→发送→展示accepted而未宣称送达→离页重进继续禁止重发→仅通过UI清除通知0→旧typed route只核对/复制原文。host用run-as读取独立receipt及CLEANUP最终snapshot，原文完全匹配、count均1；独立Android列表证明IDs1/2/3仍在、仅0消失，随后精确清理/卸载且无hostErrors。结果及两张图各在`/tmp/connect-e2e/notification-reply-{current,final}/`，accepted和过期复制页面已实际目视。是合成原接收端实际收到，不是第三方聊天App或消息服务送达，也不证明后台OS提醒、锁屏认证或OEM覆盖。

最终轮还要求主控已存在可读纯文本剪贴板基线，复制前检查、finally恢复该文字；回执`clipboardBaselinePresent/clipboardRestored=true`。不声称恢复任意ClipData/MIME或空剪贴板。测试自己新建的device记录最终forget，既有记录不被删除。host验收缺完成报告/receiver、次数0或2、错文/跨run、保护缺失、清理/文字恢复未确认均失败；文字恢复门禁实际红→绿`/tmp/connect-notification-clipboard-contract-{red,green}.log`。

### 当前合并检查与剩余边界

Rust工作区159 passed/44 ignored（`/tmp/connect-context-rust.log`）、all-target clippy `-D warnings`（`/tmp/connect-context-clippy.log`）通过；忽略用例没有冒记默认通过。App全量154项`/tmp/connect-context-app-final.log`，随后host文字恢复3项定向通过。初次严格分析捕获格式/nullable问题，修正后最终`/tmp/connect-context-final-analysis-verified.log`无问题；build_runner真实生成/only-check通过`/tmp/connect-context-generated-check.log`。

最新产品流程显式`--dart-define=CONNECT_E2E_TRANSPORT=tcp`选择旧TCP，保留加密无线默认，不按端口猜：日志`/tmp/connect-tls-entry-product-final.log`，19秒完整退出0，产品完成回执true、首次H265选择与真实像素通过；六图及JSON仅`/tmp/connect-e2e/tls-entry-product-final/`。全屏、退出和回复过期保留页已再次目视；实际230×512低清未通过质量，整体液态玻璃/完整设计仍未完成。

完整用户首次授权、生产密码和安全adbd、四宿主整包、IME/原应用回退、内容系统保存、断网/进程/系统Stop恢复、通知OS投递/认证和真实通话仍开放；上述默认、widget和隔离fixture的通过不替代它们。


最终另启动普通`lib/main.dart`并实际热重启，返回`Restarted application in 1,363ms`；截图`/tmp/connect-context-hot-restart.png`仅在tmp，随后detach。FRB在旧isolate切换期间仍打印两条投递失败提示，未将启动截图当成资源回收或进程恢复全部通过。

## 画质实像素与主控系统通知

代码批次：`63ad1ca`增加真实产品画质门禁；`0f8ef66`接入共享系统提醒、权限状态和通知所有权，补汇总项元数据。使用当前Android16双AVD，主控5554、目标5556，准备好的旧TCP端点15556；没有把本轮当首次配对授权验收。

### 画质检查

`product_flow_test.dart`增加可选的请求尺寸和实际码流/解码长边门禁。真实画质页选1280，保存及请求都为1280，码流与解码均230×512：`/tmp/connect-resolution-red-verified.log`实际失败，回执productAcceptanceComplete=false。最初重复文本定位失败只算夹具错误，不算产品红。

已有[HEVC专项研究](../research/hevc-emulator-constraints.md)已定位目标软件编码器约束，因此未继续改播放器或统一硬编码HEVC策略。仅通过真实产品页面选择1080，`/tmp/connect-resolution-1080.log`完整21秒通过，码流/解码均486×1080，H265保持所选格式。两份remote-live原图均已目视，文字和线条明显改善；1280的退化仍未通过，不以此关闭完整延迟/资源或所有设备画质。

运行目录`apps/connect`，用普通产品driver；在既有地址/端口/transport定义后增加：

```sh
--dart-define=CONNECT_E2E_VIDEO_MAX_SIZE=1080 \
--dart-define=CONNECT_E2E_MIN_VIDEO_EDGE=1080
```

严格1280负例则两个定义都设1280。结果和图仅在`/tmp/connect-e2e/resolution-{red-verified,1080}/`，未放入designs。

### 系统提醒的红绿与真实缺陷

共享协调器14项、App生命周期1项和host报告5项定向20项通过。覆盖基线/更新/撤回、来电状态、权限及渠道、点击不发远端动作、旧代次、stop/resync、迟到show/dispose、截断容量淘汰、初始化和重复启动回调。独立只读审查发现并修复：

- App只在build中传生命周期，暂停前没有下一帧会漏提醒。公开App widget实际红为expected1/actual[]，日志`/tmp/connect-system-notifications-lifecycle-red.log`；改同步生命周期回调后通过。
- 1000项截断合并淘汰旧元数据却没有撤回旧OS项。精确重现后补先撤回后淘汰；旧guard移除时的失败及恢复后通过由实施代理记录，主代理复核最终代码和全量结果。

首次真实通知验收不是绿：两条source已发布，但目标Android自动汇总更新被另作提醒，导致点击阶段有多余候选。安全元数据证据在`/tmp/connect-system-notifications-summary-metadata.log`，确有GROUP_SUMMARY/AUTOGROUP_SUMMARY。补`groupSummary`快照字段、共享策略不额外提醒汇总项（原列表和动作仍保留）；新回归先红，expected1/actual2，见`/tmp/connect-system-notifications-summary-red.log`，修复后20项通过`/tmp/connect-system-notifications-summary-green.log`。

临时JAR按源码构建，新SHA256为`4a3082a8c4bcfe2a83293136dae513a0d5f9436bbe4f3db353c7b95341c28960`，已同步Rust校验和构建说明。没有给被控安装APK，也没有新增主控Kotlin通知业务。

首轮失败后后台验收等待Flutter帧阻止finally推进，主代理将该既有主控Activity带回前台后完成精确清理，失败回执保留。验收改为不依赖帧的有期限ack，并在host失败时返回主控帮助清理；下一轮因Activity切换瞬间无resumed记录被过早判失败，改为等待真实稳定前台记录。`system-notifications-real`与`system-notifications-final`回执均false且清理确认，不冒记通过。

### 双AVD实际系统通知

`/tmp/connect-system-notifications-verified.log`17秒完整退出0；独立host记录两条真实远端shell通知→两条主控OS项，标题“设备有新通知”、正文“请打开邻接查看”，没有source正文；精确撤回A，B及既有2101保持；真实SystemUI展开/点击B后进入对应NotificationsPage，B的id/revision、目标前台、远控会话和回复状态不变；最终精确清理源及镜像，hostErrors=[]，systemNotificationsComplete=true。

这条流程通过的是公开系统源通知，未安装测试APK。远端命令“没有尝试执行”的证据来自协调器公开测试；真实E2E独立证明源/任务/前台结果，未声称可从OS日志逐一计数所有不可见命令。权限为该AVD实际允许状态，不代表拒绝/渠道关闭/锁屏/OEM已实测。

第一份opened截图仍在加载帧，未当作内容视觉通过；因此补“实际看到仍有效的source标题且无loading，撤回项消失”的UI门禁后重跑。此时主控AVD从ADB及qemu进程表都已消失，原因未确定；只重启同一interop-controller，未wipe，保留数据，boot_completed=1后继续。该环境退出不算产品进程恢复通过。

完整运行命令，目录`apps/connect`，PATH含本机Rust/Flutter：

```sh
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/system-notifications-content-verified \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/system_notifications.dart \
  --target=integration_test/system_notifications_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

当前Flutter全量174通过（`/tmp/connect-system-notifications-app-verified.log`），Rust工作区160 passed/44 ignored、37组（`/tmp/connect-system-notifications-rust.log`），最终all-target clippy通过（`/tmp/connect-system-notifications-clippy-final.log`），严格分析无问题（`/tmp/connect-system-notifications-analysis-verified.log`）、生成only-check退出0（`/tmp/connect-system-notifications-generated-check.log`）。前次全量background_test因新增开关出现多个Switch的定位错误已改为具体产品标签；原操作次数和顺序断言保留。

补齐内容门禁后的最终轮`/tmp/connect-system-notifications-content-verified.log`18秒完整退出0，runId为`0e1ae9ba0384e3195d245688ed4be382`；回执systemNotificationsComplete=true、hostErrors=[]及精确清理确认。源B实际标题和正文已在UI出现，源A消失；最终opened及SystemUI截图已原生目视，输出仅在`/tmp/connect-e2e/system-notifications-content-verified/`。该图也明确暴露浅色页状态栏白色图标对比不足、空内容汇总卡及白卡材质，归A27/A29/任务18继续修；没有判整体视觉完成。

实现边界见[主控系统提醒](system-notifications.md)。真实来电系统投递、锁屏、拒权/渠道关闭、冷启动点击和长时/进程停止、系统容量及汇总策略、Windows打包身份与四宿主整包仍开放。完整产品、Glass、输入、文件/相册保存、真实通话和恢复仍未完成。

最后以普通`lib/main.dart`启动并实际发送R，回执`Restarted application in 1,373ms`；原生截图`/tmp/connect-system-notifications-hot-restart.png`已目视，随后detach保留应用。FRB旧isolate切换仍有两条投递失败提示，不以此判所有资源回收/恢复已完成。

## 共享光学材质与通知页视觉复验

2026-10-17后续修复只涉及共享Flutter材质、主题/图标、通知呈现及验证入口，不增加Android原生业务。`design_system.Glass`固定easy5.0.0，支持后端使用真正背景shader，未启用View/逐帧截图；无支持时磨砂fallback，高对比/降低透明度/solid完全跳过滤镜。光学值同步design.md/Pencil，文字保护使用两色椭圆渐退，保留外沿透色。当前未实现所有控制的可打断形变，也未证明四宿主整包或GPU预算。

### 测试暴露的问题与修复

- 通知空汇总回归在旧页真实失败（expected0/actual1），修后普通通知、正文受限通知与有内容汇总仍保留，快捷回复和原手机入口继续可达。
- 共享组件新增夹具首次tap0/expected3，是空GestureDetector默认deferToChild未命中；改明确opaque。随后发现SemanticsHandle需在testBody结束前dispose，改try/finally。没有为过测试删除语义断言。
- 增加Lucide默认返回时曾使用Icon不存在的`matchTextDirection`参数，`/tmp/connect-glass-notifications.log`构建失败，未作为E2E通过；已改Transform.flip处理RTL并保留BackButton行为/tooltip，严格分析与后续实际构建通过。
- 三段保护渐变出现一条斜线；17stop平滑版本反而出现多条斜纹，图像在`/tmp/connect-e2e/glass-product-smooth/`。**反证否定“只是中间色标导数折痕”的解释**。保留lens/shader/blur，仅换两色椭圆渐变后，`glass-product-final`退出及工作台图均未见这些线。当前只确认此绘制路径消除症状，未定位engine/GPU内部原因。
- 扩大对比测试到圆形及354×72长导航的左/中/右后，旧rawRgba读法报4.32356。SDK明确rawRgba预乘alpha；传给Color.alphaBlend会重复预乘。改rawStraightRgba后同样4.5门槛通过，未修改颜色来掩盖夹具问题。这仅证明widget后端磨砂路径在黑白均匀背景的采样点，不声称覆盖所有Impeller动态视频与任意背景。

### 双AVD结果和边界

启动前两台AVD均不在ADB和进程表，原主控日志有ColorBuffer错误，未确定退出根因；原userdata重新启动，无wipe。目标启动阶段events日志记录SystemUI KeyguardService等待20018ms的ANR，早于产品验收；首轮收起截图确实带该系统对话框，因此没有当作视觉通过。后续流程目标对话框已消失。不能将这些环境事件当成产品进程恢复或Glass稳定性结论。

真实产品运行命令在apps/connect，PATH含Rust/Flutter，两台API36/x86_64：

```sh
rtk proxy env CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/glass-product-final \
  flutter drive -d emulator-5554 --no-pub \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/product_flow_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_E2E_TRANSPORT=tcp \
  --dart-define=CONNECT_E2E_VIDEO_MAX_SIZE=1080 \
  --dart-define=CONNECT_E2E_MIN_VIDEO_EDGE=1000 \
  --dart-define=CONNECT_E2E_REQUIRE_SHADER_GLASS=true
```

`/tmp/connect-glass-product-final.log`23秒退出0，shaderImageFiltersSupported=true、H.265真实encoded/decoded486×1080，全屏/输入/拖拽/收起/展开/退出与暂停原会话通过；退出按钮和工作台图已原生目视，无前述斜线或黑块。支持位加源码调用和截图不等于已独立测量折射像素或首帧/输入P95。日志仍有模拟器GLES无效纹理格式及释放后BufferQueue abandoned，没有谎称零图形告警或性能通过。

`/tmp/connect-glass-notifications-verified.log`20秒系统通知完整通过，runId=b7cf13dff7c45de14e86a99d5f2afa3d。source/镜像精确清理，hostErrors=[]；实际SystemUI点击后当前内容呈现，浅色状态栏图标深色、Lucide返回、空汇总不占位、连续行与原手机动作已目视。该运行发生在换椭圆保护层前，通知页逻辑/主题为同一版本；未将它当成最终材质证明。

当前App175通过（`/tmp/connect-glass-app-final.log`），设计系统3项通过，严格分析及生成only-check通过。默认`tool/check.sh`已纳入设计系统测试。Google官方lint0errors/31warnings：10项光学扩展、21项颜色未被标准components引用；Pencil静态引用不在该CLI扫描范围。源文件仍77页/12类/23母组件；a7A57连续通知行和新增光学tokens已通过对象API保存，预览仅`/tmp/connect-glass-source-preview/`。本次没有再逐像素验收全部77页，也不关闭完整设计/输入/文件/通话/恢复及四宿主任务。

最终验收进一步把退出位置下移、返回后等待转场再截图，`/tmp/connect-glass-product-verified.log`24秒退出0，回执仍为真实486×1080与shader能力true；`/tmp/connect-e2e/glass-product-verified/`展开/收起/工作台已原生目视，没有目标ANR弹窗或前述斜纹。Pencil保存后重新打开对象核对77页、12类别、23母组件、470ref，通知页没有报告裁切，新增折射率1.02及透明列表行仍在。单元/视觉对照与独立只读review未发现剩余有证据的本批实现缺陷；不扩大为全产品无缺陷。

最后普通lib/main.dart实际构建启动，日志确认Impeller(OpenGLES)。Dart MCP发现IDE的DTD但没有关联此CLI启动的App，hot_restart工具因此拒绝；随后直接向本次flutter run发送R，实际`Restarted application in 1,378ms`。`/tmp/connect-glass-hot-restart.png`设备列表/浅色系统栏/共享悬浮导航已原生目视，随后detach。两条FRB旧isolate投递失败警告仍存在，不能将热重启局部成功扩大为全部生命周期资源已无缺陷。
