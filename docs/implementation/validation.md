# 实施与真实验收记录

> 此文件是按阶段追加的历史验收账本；`.scratch/interop/` 来源现已不随仓库保留，相关正文链接仅表示当时的追溯路径。正文的旧目录、偏好、后端、统计与未决状态保留其当时语境。当前结构与资源所有权见 [架构](architecture.md)，当前产品行为见 [交互规则](../../designs/prod/interaction-rules.md)，2026-10-19 产品/材质回执索引见 [产品验收记录](product-refinement.md)。

> 当前结构见[架构说明](architecture.md)。本文件包含已被替代的实验与后端路径：
> 例如下文历史 `servers/scrcpy/build.py` 与 cooperative 暂停记录，不适用于当前
> 官方 scrcpy JAR 路径。当前来源与暂停语义以 `servers/vendor/README.md` 为准；
> 历史通过不自动成为当前提交通过。

> 当前播放器使用社区原版 fvp 0.39.1，已移除本地源码副本、snapshot 空结果补丁与 MDK 固定回归。旧 snapshot 接缝、CMake 用例、补丁版媒体运行和 APK 回执仅证明各自当时版本；原版依赖规则与已知限制见[工具链契约](repository-tooling.md#社区原版-fvp-0391)。

目标入口为 .scratch/interop/goal.md（历史路径 `../../.scratch/interop/goal.md`）。2026-10-17的完整重新核查（历史路径 `../../.scratch/interop/completion-reassessment.md`）逐项纠正产品断链：本文件的历史实验通过不表示对应整个用户流程完成。下列结果区分协议单测、真实被控 adbd 和 Android 主控界面；未列通过的能力不推定已完成。下列历史验收保留当时的后端和测试名；当前共享媒体结果以最新迁移小节为准，旧AudioTrack/自写MediaCodec证据不能冒充新后端结果。

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

以下命令从仓库根目录开始，进入 `app/` 运行（要求两个AVD已准备并转发端口）：

```sh
cd app
CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e flutter drive \
  --driver=../tool/driver/integration_test.dart \
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
- 四ABI助手由`servers/helpers/build.dart`构建，清单同时锁定源文件与每个产物SHA256；Android 16目标实际验证目录、链接、路径转义、并发无覆盖，以及共享存储。不是依赖系统`mv -n`的假原子实现。
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

本轮全量缺口见重新核查（历史路径 `../../.scratch/interop/completion-reassessment.md`），不把局部通过当整个目标完成。UI修复`1660805`：诊断页消费真实Rust JSON；首次编码允许runtime candidate，已知不可用继续禁选；远控独立消息作用域，上一页保存反馈不遮挡手机，当前会话资源调整仍可显示。

- 指定诊断/画质6项回归先红后绿；新增旧页面30秒SnackBar隔离测试先红后绿。整合后应用全量83项通过，严格全仓Flutter分析无问题，格式/diff通过。整合首轮遗漏confirm导入造成编译失败，修正后重新全量通过，日志`/tmp/connect-reaudit-app-tests-final.log`。
- 使用本文件Android E2E命令，把capture目录设为`/tmp/connect-e2e/requirements-reaudit-final`。本次20秒真实退出0：手动连接/非法端口校验、真实文件目录、实际设备详情→诊断、实际画质页首次H.265选择、下一会话确实H.265且`firstFrameDecoded=true/evidence=mdk.snapshot`，全屏/触控/退出拖动吸附展开/返回均通过。诊断、编码选择和最终远控图已目视；日志`/tmp/connect-requirements-reaudit-fullscreen-final.log`，result.json的产品完成回执true。
- 实际H.265码流230×512，截图仍明显低清；仅能证明页面选择到实际解码，不是视觉质量或低延迟验收。前一轮截图发现本地保存提示跨路由覆盖画面，独立作用域修复后最终截图已无此遮挡。动态玻璃/大字/读屏及完整IME仍未通过。
- `product_flow_test.dart`不再在缺端点时静默成功。正常完整结束才产出`productAcceptanceComplete=true`；通用driver要求该回执，保留独立audio/background/clipboard/documents模式。纯Dart契约`tool/driver/integration_test_contract_test.dart`通过，`--missing-product`真实退出255；该检查已接入`tool/check.sh`。新增页面滚动按具体route/scrollable定位、等转换完成，点击未命中即失败。中间失败如实留在临时日志，没有降低健康/像素/对象断言换取通过。

本轮没有运行新的物理设备/四端整包/密码安全或当前共享SAF验收；多窗口、持续通知/认证/后台发布、安全通话、活动恢复/事件重取、完整文件/相册交付等仍是实现工作，不能称仅差测试。

## 保留多窗口与协作捕获暂停（2026-10-17）

范围：手机切换保留会话、窗口级工具/截图与当前共享播放器生命周期。完整前沿见核查第10节（历史路径 `../../.scratch/interop/completion-reassessment.md#10-持续会话批次实际进展与未完成部分`），并非大屏并排或断线/进程恢复完成。

### 实际失败与修复

- START_APP之前等待首关键帧会卡住空虚拟显示；独立控制actor先发送应用启动后，实际单Settings启动由11.26秒失败变4.25秒通过。
- 真实主屏持续编码＋Settings启动通过4.74秒，但SIGSTOP暂停主屏＋Settings失败11.89秒。最小临时服务补丁保留Binder/控制线程，视频线程释放实际MediaCodec后在gate等待；同一真实回归5.71秒通过。见[协议/构建依据](../research/cooperative-capture-pause.md)。不把具体Binder死锁机制写成已证实。
- 新多窗口流程暴露HTTP配置完整但下一帧暂停时10秒误杀。真实TCP回归先失败10.30秒；取消配置组之间总超时，保留半包/首次输入/下一代消费者超时、配置容量限制与取消，12项TCP默认检查通过20.01秒。
- 恢复旧播放器与新generation提交并发导致取消。新增最小挂起恢复→提交新代测试先失败，改为逻辑会话持有呈现意图和队列，恢复跟随当前代；迟到回执不能覆盖更高generation。播放器18项、呈现协调15项通过。核心另测迟到ready只更新纹理而不覆盖确认暂停及资源状态。

### 真实UI与独立进程核对

复现时从仓库根目录开始，`PATH`包含本机Rust/Flutter，target5556已将15556转发到5555：

```sh
cd app
env CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/session-workspace \
  flutter drive --driver=../tool/driver/session_workspace.dart \
  --target=integration_test/session_workspace_test.dart -d emulator-5554 \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_DIAGNOSTICS=true
```

这是已准备端口的隔离双AVD媒体验收，不是未授权首次连接。测试通过真实页面打开主屏、Settings、Google Dialer，各退出后保留session且capturePauseMode=cooperative/captureStateConfirmed=true；从会话列表恢复原Settings，工具截该窗口最后显示帧，明确关闭Settings后恢复原Dialer。driver通过测试端等待的checkpoint，在各状态当时独立检查被控端process/cmdline，而非测试结束才推断截图时的进程。

完整运行退出0、40秒，8个独立检查点均通过：paused服务为S而不是T；Settings关闭后其进程消失，其余两个仍存活；最终Dialer实际Texture及MDK snapshot可用。回执`sessionWorkspaceComplete=true/pausedWindowsVerified=3`，日志`/tmp/connect-session-workspace-cooperative4.log`，JSON/PNG在`/tmp/connect-e2e/session-workspace/`。已目视会话列表、Settings截图和最终全屏Dialer；列表的包名/材质仍有产品呈现改进空间，未称视觉设计完成。

同一扩展下真实HOME/Activity返回13秒通过：增加`CONNECT_E2E_BACKGROUND=1 CONNECT_E2E_DEVICE=emulator-5554`，driver改`tool/driver/integration_test.dart`、target改`integration_test/background_resume_test.dart`；回执`mediaAcceptanceComplete=true`，日志`/tmp/connect-cooperative-background.log`，图在`/tmp/connect-e2e/cooperative-background/`。

五编码改target为`integration_test/video_codecs_test.dart`，显式`CONNECT_E2E_ACCEPTANCE=media`，不设置BACKGROUND；45秒通过H264/H265/AV1/VP8/VP9的真实共享渲染。每种离开后确认paused，再只停止当前ID，保证下种编码创建新窗口而非误复用旧设置。日志`/tmp/connect-cooperative-codecs.log`，JSON/PNG在`/tmp/connect-e2e/cooperative-codecs/`；H264/H265图已比较，HEVC低清仍存在，不记视觉质量通过。通用driver默认仍要求product回执；media模式缺/false/错误类型回执同样失败，显式product失败不能被media掩盖，纯Dart契约通过。

### 源码、产物和默认检查

`servers/scrcpy/build.py --check`从固定源归档/补丁重建到忽略目录，实际输出SHA与受控产物一致：`91606a603a49bbea2be37ec500cde44a588483ac3162bc466d23b2f9d840deab`。JVM协议/gate检查通过，二者已接入`tool/check.sh`。CI配置安装JDK21/platform36/build-tools36.0.0；当前仅本机执行，不能称CI已绿。官方vendor JAR保持原样，新增Java仅在被控端临时运行，主控播放器仍为跨平台Flutter/fvp。

当前默认Rust工作区135 passed/43 ignored、all-target clippy、cargo fmt通过；严格Flutter分析无问题，真实workspace build_runner only-check通过。43项忽略用例须各自实际配置执行；默认通过不替代设备证据。FRB、companion其余产物门禁、旧系统/OEM/物理USB/HAL、四宿主整包、完整恢复、通知和液态玻璃仍开放。

最终应用全量91项、Bridge全量83项均通过，日志`/tmp/connect-session-final-app.log`和`/tmp/connect-session-final-bridge.log`。Rust日志`/tmp/connect-session-final-rust.log`，严格分析与生成日志分别`/tmp/connect-session-final-analysis.log`、`/tmp/connect-session-final-generation.log`。生成检查在隔离工作目录运行真实builder比对，控制器和typed route生成文件已经提交对应源；测试通过不代表上述开放任务完成。


## 事件缺口核验与编码会话边界（2026-10-17）

当前范围见 [恢复契约](state-recovery.md) 和 完整核查第11节（历史路径 `../../.scratch/interop/completion-reassessment.md#11-事件缺口后的状态核验批次`）。核心与桥接批次为 `cf35daf` / `3ee0318`，媒体边界 `d7d60d8`，应用 `591d48e`。不以本节关闭全产品目标。

### 默认及交错回归

- 工作区 `cargo test --workspace`：146 passed / 43 ignored / 0 failed，日志 `/tmp/connect-recovery-csd-workspace.log`。all-target clippy `-D warnings` 通过，日志 `/tmp/connect-recovery-csd-clippy.log`。忽略用例需真实 Android/外部工具，未计通过。
- 应用全量114项通过（`/tmp/connect-recovery-app-complete.log`）；之后新增终态迟到恢复保护，远控20项定向全部通过（`/tmp/connect-recovery-final-remote-tests.log`）。桥接全量93项通过（`/tmp/connect-recovery-bridge-complete.log`）。包含真实生成 provider、覆盖页面返回、冻结触点/按键/剪贴板、核验失败重试、短屏大字保留停止操作；widget 证据不替代实际手机权限或全局读屏验收。
- 严格全仓 Flutter analyze 通过（`/tmp/connect-recovery-final-analysis.log`），真实 build_runner only-check 通过（`/tmp/connect-recovery-generation-check.log`）。本批无新的FRB导出签名，不以此宣称正式FRB重生成门禁已补齐。
- 已实际先红后绿：设置发布、forget设置发布、设置保存旧回执、已消费分享的转发、companion旧list回执和已取消缓存、FRB真实256通道溢出及媒体配置边界。具体测试源纳入版本，不依赖临时日志才能复现。

### 真实流程中的失败与修复

首次真实流程在最后重试点击时触发测试监听器 expect 的异步 guard 冲突，改为记录后在测试主流程断言，未削弱实际状态条件。随后曾9秒通过，继续复验却捕获真实媒体故障；没有把这次通过当稳定验收。

失败 `/tmp/connect-recovery-repeat-2.log` 实际报告 `media_mux: AVC requires one SPS and bounded PPS records`；另一次先看到原始媒体 EOF→Core stopped，250ms poll 尚未来得及读取 relay 原因。HTTP真实TCP用例重现 `[session A,CSD A,session B,CSD B,keyframe B]`，旧实现拼接两会话 CSD、重复 SPS，实际失败。新 Dimensions 边界只保留本编码会话的配置；相同配置继续现有 HTTP，不同配置正确切换 generation/CodecPrivate。HTTP13＋mux6通过，未放宽单活动 SPS 约束或配置/半包限制。

### 修复后真实核验

主控5554→被控5556，使用已经准备的转发端点；target secure=0，不能证明未授权首次设置或强制认证。以下复现命令从仓库根目录开始，PATH 包含本机 Rust/Flutter：

```sh
cd app
env CONNECT_E2E_ACCEPTANCE=media \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/recovery-csd-fixed \
  flutter drive --driver=../tool/driver/integration_test.dart \
  --target=integration_test/state_recovery_test.dart -d emulator-5554 \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_DIAGNOSTICS=true
```

该流程使用生产 Bridge 的 `state.reconcile`，不声称在 AVD 人为挤满 FRB 队列。FRB溢出由真实容量默认测试独立验证。实际打开远控→两次同ID核验（含并发合并）→MDK真实snapshot→退出保留且捕获暂停→后台核验仍暂停→同ID重开→明确结束→重新检查仍不存在。修复后新APK首次11秒、同APK重复两次各10秒，三次均完整退出0，`stateRecoveryComplete=true/mediaAcceptanceComplete=true/endedSessionNotRecreated=true`，每次独立UUID、两次同ID实际恢复。日志 `/tmp/connect-recovery-csd-fixed.log`、`/tmp/connect-recovery-csd-repeat-{1,2}.log`；回执/图分别在 `/tmp/connect-e2e/recovery-csd-fixed/`、`recovery-csd-repeat-{1,2}/`。

恢复后的全屏画面与已结束状态图已实际目视，退出入口始终保留；结束状态清除旧Texture，标题明确“控制会话已结束”。早期图发现结束状态仍写“正在核验”，已修正并在真实断言中保留；截图等待点击提示消退，只保存在临时目录。本节不是液态玻璃、视觉质量、完整IME或大字读屏总体验收。


同一最终代码另回归：主屏＋Settings＋Google Dialer 三个真实会话保留/暂停/恢复/截图/单独关闭，40秒退出0，`sessionWorkspaceComplete=true`，宿主8次独立进程检查均通过；暂停进程为S、不是整进程冻结T，关闭Settings后其余两路存活。日志 `/tmp/connect-recovery-workspace-real.log`，8图及回执 `/tmp/connect-e2e/recovery-session-workspace/`。实际HOME→两秒后台→回前台→新MDK snapshot与健康全屏，11秒退出0，日志 `/tmp/connect-recovery-background-real.log`、图/回执 `/tmp/connect-e2e/recovery-background/`。代表会话列表、恢复全屏与结束状态已目视；列表仍有包名代替友好应用名、材质仍偏白卡，属于A06/A27/A29待补，不能把本次行为通过说成视觉设计完成。

## 再次逐指令审计及新增回归

本次稳定审计基准 `48c5003`。完整差距和每次可见用户输入对应见重新核查第12节（历史路径 `../../.scratch/interop/completion-reassessment.md#12-再次逐指令复核当前交付远未完成`），新增A37–A42；不把工作转述为“只剩补测试”。已有77页独立分行/组件、Flutter工程化和删除旧自写播放器仍然成立；液态材质、完整状态、通知/通话/内容/恢复与四宿主交付仍未完成。

### TLS策略与真实协议负例

`8a91df6`引入独立于TLS配置的`TlsPolicy`。公开Client两项降级负例先实际失败，随后Required拒绝明文CNXN/AUTH且不发送RSA签名/公钥；真实TLS1.3正例、Optional legacy AUTH/CNXN及缺配置零握手共5项通过。Core恢复配对记录原先实际返回connected=true，修复后tls/GUID记录拒绝并且零设备服务请求。ADB默认49 passed/11 ignored，Core策略/连接生命周期7 passed/2 ignored；固定独立BoringSSL Required互通1项通过。现代新发现服务到Flutter表单仍有类型丢失路径，A37整体未关闭；安全adbd/撤权、生产密码成熟度及证书绑定也没有因此通过。

### 免APK持续观察的真实端点

`df2af2d`将设备持久观察意图与共享helper分开。连接成功自动建立通知/来电观察；stop真实注销listener并清除动作，保留剪贴板/媒体用途；代际隔离迟到数据，断线保留意图，显式停止不因列表/重连复活。新JAR SHA256为`0026e5af2db8558b2ba1eebac22c84303e20d3ee1a7b184bc683f808cf3889bb`。

API36目标`emulator-5556`、转发`127.0.0.1:15556`执行：

```sh
env INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
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

PATH已含本机Rust/Flutter；先在仓库根目录构建`dart tool/e2e/notification_fixture/build.dart`，再从仓库根目录按下列命令进入 `app/` 运行：

```sh
cd app
env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/notification-reply-final \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/notification_reply.dart \
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

运行目录仓库根目录，用普通产品driver；在既有地址/端口/transport定义后增加：

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

以下复现命令从仓库根目录开始，PATH含本机Rust/Flutter：

```sh
cd app
env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/system-notifications-content-verified \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/system_notifications.dart \
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

以下产品复现命令从仓库根目录开始，PATH含Rust/Flutter，两台API36/x86_64：

```sh
cd app
env CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/glass-product-final \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/integration_test.dart \
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

## 原文件系统保存与外部分享交付

继续核对完整目标时，单项取回只进入全局传输中心，未直接完成用户原本的保存/分享意图。现增加固定任务的原件准备页：核验权威任务、设备和方向，保留进度/冲突/精确取消；就绪后复用系统保存表单或主动调用Sharesheet。切换当前设备不改变在途原件来源。保存与分享分别陈述完成点，结果未知需先核对再重试。实现、提供方边界和可复现命令见[内容交付](content-delivery.md)及[固定AOSP研究](../research/provider-output-streams.md)。

### 红绿与真实缺陷

- 新增公开页面/协调器回归先暴露保存回执丢失可直接重试、选择器前失败误标部分保存、固定来源任务丢失等问题；修正后App178项、Bridge98项通过。失败/取消不清除用户原件，未知结果不自动重放。
- 提供方完成改为显式success/abort；真实PFD执行checkError、close、再次checkError并收束首错。共享层保留原复制异常、检查lease回执，迟到取消不能被成功回执覆盖。原生runner实际执行3个JVM main，包括真实PlatformDocuments完成顺序测试；仅Gradle编译不是该测试通过的依据。
- 首轮三ABI构建发现armv7的mode类型不一致，统一宽度后通过。最终`flutter build apk --debug --no-pub --target-platform android-arm,android-arm64,android-x64`104.9秒退出0，日志`/tmp/connect-content-delivery-android-abis.log`。
- 首轮普通Android应用取回失败；SELinux拒绝私有app_data_file硬链接。`/tmp/connect-content-delivery-publication-red.log`6秒通过公开任务状态明确定位Permission denied。Linux子进程拒绝linkat的公开CopyManager回归也先红；共用raw renameat2(RENAME_NOREPLACE)后绿。已有目标原子拒绝，成功后核验身份并同步；不采用覆盖式rename降级。
- 缓存发布修好后，系统保存仍在选择器前失败：path_provider为`/data/user/0/.../cache`，能力环境使用canonical后的`/data/data/.../cache`。改用一致absolutePath；没有放宽私有根检查。临时路径诊断日志已从源码删除。选择器前失败现显示“本次保存未开始”，允许用户主动重试。
- 夹具也出现过编译引用错误、DocumentsUI抽屉定位失败和Sharesheet折叠导致接收器不可见，均保留失败结果；它们不算产品通过。host改为实际可访问节点/面板边界操作，外部命令超时会终止并等待进程，安装尝试也纳入精确清理责任。

### 实际Android交付与视觉

测试源为`integration_test/content_delivery_test.dart`、`tool/driver/content_delivery.dart`及controller-only独立接收器`tool/e2e/content_delivery_fixture/`。接收器无额外权限，只凭真实Intent content URI及read grant读取并计算SHA-256；不安装在被控设备或进入产品。源/导出文件采用唯一runId，host独立读取系统保存位置，再清除本次精确文件与自有接收器；不清空应用数据来伪造取消语义。

第一次完整38秒通过，`/tmp/connect-content-delivery-verified.log`、结果目录`/tmp/connect-e2e/content-delivery-verified/`；但“保存后”截图仍是系统文件页，不登记为产品结果页视觉通过。补阶段确认和返回后截屏门禁，再次39秒退出0，日志`/tmp/connect-content-delivery-visual-verified.log`，结果目录`/tmp/connect-e2e/content-delivery-visual-verified/`：

- runId `7ce135daa5ed16bd1133d5967b910a26`，真实UTF-8原件63字节，SHA-256 `db82ab8b8a76e2b5d7cdf8a78dbfab0d6bbd154d2e1dd0b7669e847a7fa44c1b`。
- 真实文件详情→取回→原件准备；取消实际系统选择器后缓存仍可用；再次实际选择Downloads保存，host读取的字节/hash一致。
- 实际Sharesheet选择独立接收器，回执`ACTION_SEND`、`text/plain`、`content`、`readGrant:true`，实际63字节/hash一致。返回产品只显示交给系统选择的应用，不承诺接收器后续发送或云同步。
- `savedProductPageCaptured`、`shareProductPageCaptured`、`sharedProductPageCaptured`均true。实际保存结果/分享结果产品截图已经原生目视：长文件名可换行，小琥珀图标不再伸展成整宽色带，没有回归深绿主按钮；系统DocumentsUI蓝色不是产品主题。该检查不替代完整动画/性能/无障碍验收。
- `contentDeliveryComplete:true`、`hostErrors:[]`、`exactFilesAbsent:true`、`ownedReceiverUninstalled:true`；所有必要产品与OS回执纳入最终结果，缺项失败。

额外实际adbd回归`actual_push_pull_hash_atomic_conflict_rename_delete_and_preview_cache`11.22秒通过，包含8MiB、并发同名目标、保留两份、hash和预览；该host测试不替代普通Android应用SELinux验收。Rust workspace161通过/44忽略、37套件，相关clippy无警告；App178、Bridge98、原生3个实际main、严格分析与生成检查通过。独立只读review未发现有证据的本批缺陷。

仍观察到SurfaceSyncGroup等待、跳帧及PFD缺少comm channel日志；不能推断提供方远端提交ACK或达到延迟指标。此次只覆盖API36模拟器、单项UTF-8文本和本机Downloads；被控AVD已准备legacy TCP且secure=0，不代表首次安全配对。批量/目录、图片/视频大原件、非seek/云provider、写入中取消/空间满/撤权、进程死亡任务恢复和完整四宿主整包仍开放。

### Pencil与产品说明

同一mobile.pen的文件/传输类别行新增7种独立状态，使用既有母组件：ERONu、uhuiJ、Gfe22、mcRQa、vSjZS、pSoci、cdQol。对象API保存重开核验84页（82手机/2大屏）、12类、23母组件/513实例、153变量，无断链/顶层重叠；预览只在`/tmp/connect-content-delivery-design/`。7页均已目视，prod只描述产品规则，不引入库或代码路线。静态代表状态不等同可点击原型或全部84页实现一致，任务18保持开放。

最后普通lib/main.dart实际构建启动，日志确认Impeller(OpenGLES)。Dart MCP发现IDE的DTD但没有关联此CLI启动的App，hot_restart工具因此拒绝；随后直接向本次flutter run发送R，实际`Restarted application in 1,378ms`。`/tmp/connect-glass-hot-restart.png`设备列表/浅色系统栏/共享悬浮导航已原生目视，随后detach。两条FRB旧isolate投递失败警告仍存在，不能将热重启局部成功扩大为全部生命周期资源已无缺陷。

普通`lib/main.dart`随后在emulator-5554实际重新安装运行，按R热重启完成（1,401ms），设备列表首屏截图`/tmp/connect-content-delivery-main-restarted.png`已目视。FRB在热重启时记录两条Fail to post message警告；未将其写成无运行告警或进程恢复通过。

## 相册JPEG与MP4实际交付复验

针对上一节仅文本的边界，扩展同一公开页面/E2E流程：host FFmpeg7.0.2生成320×180 JPEG及6秒、15fps、无音轨H264 MP4，分别放入被控Pictures/Movies下唯一名称；从实际相册网格点击该原件，等待缩略图/原件真实解码，再执行系统选择器取消、保存和实际Sharesheet。没有将文件详情直跳冒充相册入口，也没有通过调用播放器方法代替点击播放/暂停/进度/静音控件。

JPEG初次43秒、MP4初次44秒通过。独立只读review发现接收器用URI解析MIME覆盖Intent MIME，可能掩盖分享目标匹配错误；现分别记录`intentMime`与`resolvedMime`并严格检查两者。修正后完整重跑，不沿用旧回执：

| 样本与最终日志 | 实际结果 | 原字节与SHA-256 |
| --- | --- | --- |
| JPEG，`/tmp/connect-gallery-image-mime-verified.log`，42秒 | 真实网格/缩略图/原件、取消/保存/外部分享；Intent及解析均image/jpeg | 8840；`662f90ce3844cc6195ae0876158c417992554097e5831c76d14c4e2813859662` |
| MP4，`/tmp/connect-gallery-video-mime-verified.log`，43秒 | 真实网格/缩略图/播放器；播放时钟前进、暂停、用户定位至2秒后、静音；取消/保存/分享；两者均video/mp4 | 323934；`e3be91817d465fe87a368ff79a949e467fc684255fcd65d0ef9b4e0b55fbe474` |
| UTF-8，`/tmp/connect-content-text-mime-verified.log`，39秒 | 默认文件详情链路回归；真实取消/保存/分享；两者均text/plain | 63；hash随唯一runId生成，见对应result.json |

最终结果目录分别为`/tmp/connect-e2e/gallery-image-mime-verified/`、`gallery-video-mime-verified/`和`content-text-mime-verified/`。三次`contentDeliveryComplete:true`、`hostErrors:[]`，本机实际导出字节一致，独立接收器实际读到相同字节/hash、content URI及read grant，精确源/导出文件消失及自有接收器卸载均确认。媒体回执还必须含`galleryThumbnailLoaded`/`actualMediaPreview`，视频必须含`videoPlaybackControls`；缺少判据失败。

图片/视频预览及保存/分享结果已原生目视。返回系统分享后曾捕获偏浅状态栏图标；额外记录实际`shared-product-windows.txt`，生产窗口明确`apr=LIGHT_STATUS_BARS LIGHT_NAVIGATION_BARS`，系统转场结束后的产品截图图标正常。没有把瞬时截图推断成已定位的业务错误，也没有为此增加原生样式代码；完整动态/对比/无障碍矩阵仍开放。

只扩展测试源与独立接收器，产品实现/依赖及Pencil页面数未再变化。FFmpeg仅host测试工具；JPEG/无音轨MP4的小样本成功不证明物理声音、全格式、HEIF/HEVC/动态照片、超2MiB、长原件准备/取消/空间满/撤权、索引分页或批量能力。当前剩余工作已同步goal、任务10/13及第12.2节。

## 跨目录搜索与真实文件页验收

本批补有界、可取消的跨目录名称/类型搜索。文件页当前目录筛选保留；新页固定设备与搜索根，修改条件需明确提交，同名结果展示父目录，进入详情重新核验。Rust持有独立只读搜索，Flutter处理固定ID轮询、离页迟到取消及读取世代；没有新增被控APK、主控调试要求、原生业务或媒体依赖。接口、边界和重跑命令见[搜索实现](file-search.md)。

### 真实缺陷与公开回归

- Runtime公开命令回归先因命令不存在失败，补start/get/cancel后通过。真实AOSP的Sync LIST可能因链接元数据errno13整体失败，也可能权限拒绝却返回空DONE；加入目录权限核对及有界固定glob/NUL/lstat回退，查询不进入shell。
- 独立review发现根目录`/`去尾分隔符后权限检查变空路径；真实adbd公开根目录用例先红，保留权限根后绿。链接/无效UTF-8/权限错误/上限均保留结果并标partial，不假报已搜完整范围。
- 页面公开回归覆盖固定来源、离页前start未返回后的精确取消，以及旧running快照覆盖cancelled。最后一项曾因只有一次pump而假绿；增加实际读取次数与两帧观察后确实红，独立读取世代修复后绿。没有把测试未观察到帧的成功当修复证据。
- E2E清理采用独立嵌套finally，目标唯一目录清理失败也不跳过本机临时文件与本次设备记录清理。driver只有在实际搜索、筛选、详情重验和夹具精确清理全部回执为true时通过，拒绝扩大成完整产品验收。

### 双AVD与视觉结果

API36/x86_64双AVD，主控emulator-5554，目标emulator-5556，既有host转发15556→5555，产品访问10.0.2.2:15556。目标为预先准备的legacy TCP/secure=0；不是首次授权、安全配对、USB或物理机覆盖。测试通过公开文件操作创建唯一目录/子目录及19字节UTF-8文件，再实际点击文件页搜索入口、输入“报告”、筛选文档、点击嵌套结果并验证详情路径，最后精确清理。

| 运行 | 结果及证据 |
| --- | --- |
| `/tmp/connect-file-search-ui.log`，6秒 | 失败：转场时泛TextField定位匹配两页；不是产品搜索失败。夹具创建/清理均true，未记为通过 |
| `/tmp/connect-file-search-ui-fixed.log`，10秒 | 数据链路通过，但截图仍为旧running/单条帧；不记为最终视觉通过 |
| `/tmp/connect-file-search-ui-visual.log`，11秒 | 最终通过；限定FileSearchPage定位，完成回执后等待实际绘制，再截屏。搜索全部3项、文档2项、原文件详情重验及精确清理通过 |

最终`/tmp/connect-e2e/file-search-ui-visual/result.json`含`fileSearchComplete/actualNestedNames/actualTypeFilter/actualDetailRevalidated/fixtureCreated/fixtureRemoved:true`，唯一根为`/sdcard/Download/connect-search-1792233667877933`。原生目视`file-search-documents.png`已显示“搜索完成”、两条同名文件及不同完整父目录、浅色玻璃范围控件与黑中性类型胶囊，无该页可见重叠；截图只在tmp。该结论不扩展到全部页面/字体比例/读屏或液态动态性能。

### 自动检查与源稿

- 应用全部181测试通过，`/tmp/connect-file-search-app-all.log`；视觉调整后新增3项定向回归再过，`/tmp/connect-file-search-widget-visual.log`。
- Rust workspace39套件、163通过/46忽略，`/tmp/connect-file-search-rust-workspace.log`；其中2项真实adbd用例另以include-ignored显式执行通过，不把默认忽略算通过。相关clippy及cargo fmt通过。
- build_runner生成一致性检查通过（141输入），严格Flutter分析无问题。Android arm/arm64/x64三ABI整包构建158.9秒通过，`/tmp/connect-file-search-three-abis.log`；不外推iOS/Windows/macOS。
- 独立只读最终review确认嵌套清理、driver门槛和旧快照防护，未发现新增有证据问题；review本身未运行测试。
- 同一Pencil文件/传输类别行增加lm0us/jcZXq/zD1BI及共享条件组件E0Ctfk；保存重开87页（85手机/2大屏）、12类、24母组件/545实例、153变量。原顶层/实例ID保留，无断链/占位/页重叠；预览`/tmp/file-search-design-reopen/`，不入Git。3页代表状态不等于所有异常/空结果或可点击原型完成。

普通lib/main.dart另实际构建启动并按R热重启1,414ms；设备列表首屏`/tmp/connect-file-search-main-restarted.png`已原生目视，随后detach保留运行。第一次CLI未分配TTY而无法发送R，退出该CLI后重开TTY才实际完成，不把初次启动当热重启证据。重启仍记录两条FRB旧isolate投递警告。

运行仍有SurfaceSync/跳帧/IME inactive等模拟器日志，不声称零警告或达到性能指标。目录/批量系统交付、浏览分类、provider/空间/撤权矩阵、可恢复传输意图、完整设计状态及其他第12.2节完整目标继续开放。

## 首次真实配对、强制 TLS 与系统撤权

本批针对完整核查 A02/A03/A34：不再只从预配端口开始。环境/安全边界、系统源码与重跑入口见[首次配对实现](first-pairing.md)。主控5554使用普通产品 app.main/FRB/Rust身份，被控5558仅开调试；host不执行 adb pair，不导入产品身份、不安装被控APK。宿主SDKadb仅协调测试系统界面与动态网络转发，不进入产品运行依赖。

原API36镜像secure=0的失败仍保留。本批隔离第三AVD的可写覆盖层使ro.adb.secure=1，重启后实际shell UID2000；SDK原镜像未改，前两台认证设置不变。该环境是userdebug/orange，不能替代量产锁定/OEM安全验收。仅启动参数-prop已实测被忽略，不能当设置成功。系统监听端口从实际设置读取，不依赖本镜像为空的service.adb.tls.port。

### 已修复的真实产品缺陷

新身份访问真实TLS listener时，Android发出CertificateUnknown。Core原把它记成offline并保留自动重连；公开Runtime实际回归先红（`/tmp/connect-first-trust-core-status-red.log`），补入授权拒绝分类后绿（`/tmp/connect-first-trust-core-green.log`，3.50秒）：unauthorized、autoReconnect=false、GUID未建立，仍保留原始证书拒绝理由。此前`devices.add`返回结构用错导致的unwrap失败单列为夹具错误，不能冒充产品red。

### 失败、环境与独立系统实验

| 日志（均/tmp/） | 实际范围与失败，不记通过 |
| --- | --- |
| connect-first-pairing-product.log | 约103秒；真实未配对拒绝通过，表单切换和系统配对弹窗定位错误；不含完整错码/配对/撤权 |
| connect-first-pairing-product-fixed.log | 约55秒；无线调试页晚到帧未识别，准备失败；错误路径清理握手通过 |
| connect-first-pairing-product-navigation.log | typed路由过渡中定位旧表单，点击失去目标；未扩大成产品配对失败 |
| connect-first-pairing-product-auth.log | 约133秒；未配对拒绝/错误码/真实配对/Required TLS均通过；Rust全测同时运行期间发生宿主OOM、主控被杀，另一AVD挂起后SIGSEGV。kernel journal及独立终端核对，随后保留userdata重启，未记产品或撤权通过 |
| connect-first-pairing-product-verified.log | 约52秒；到TLS通过，系统Forget后元数据清除没有在主判据完成；命名verified不等于通过 |
| connect-first-pairing-product-final.log | 约151秒；到TLS通过，系统撤权持久化及清理失败，本次记录删除/转发清理已执行；命名final不等于通过 |
| connect-first-pairing-system-interface.log | 约131秒；到TLS通过，主控连接工作台已目视；host要求指纹独占文本节点，但系统将标签与指纹合并；详情标题不在无障碍树，又导致返回定位失败。属于夹具失败，设备记录及转发仍精确清理 |

系统直接Forget的实际日志出现AtomicFile重命名失败，授权文件一度移除本次公钥、元数据却残留，重启恢复了公钥。对照AOSP AtomicFile及AdbDebuggingManager，设置返回读取与异步持久化冲突得到支持；没有声称已修复Android框架或所有时序。

独立最小实验：只针对上述本次新增身份，关闭设置后调用API36 IAdbManager.unpairDevice（事务7），确认产品公钥与元数据同时消失、基线宿主保留；不编辑key文件。host driver因此固定API36、取唯一产品详情指纹、停止设置进程后精确撤权，先等待真实授权/元数据清除再重新进入设置。清理同时检查配对条目和内存中的基线公钥；缺一不通过。此系统接口操作仅为宿主夹具，不成为主控调试/root要求；直接Forget路径仍是失败。

工作台截图在仍连接的专用握手点，拒绝截图也由宿主回执再继续；不在码输入阶段截图。结果不含配对码、VM参数、私钥或公钥原文，host命令失败只记录固定类型和本文件栈位置。独立只读review未发现新增证据误报、所有权或清理问题；review本身不算运行。

### 最终两轮产品证据

`/tmp/connect-first-pairing-system-revocation.log` 与 `/tmp/connect-first-pairing-system-repeat.log` 均64秒退出0。对应结果目录 `/tmp/connect-e2e/first-pairing-system-revocation/`、`first-pairing-system-repeat/`；两轮firstPairingComplete、initialUnpairedRejected、wrongCodeRejected、realPairingCompleted、requiredTlsConnected、revokedIdentityRejected、ownedRecordRemoved、fixtureCleanupAcknowledged全true，hostErrors=[]，OS精确撤权/基线保留/自有信任消失/转发移除全true。初次及撤权后的实际错误都为CertificateUnknown，不能用一般网络失败替代。

主控实际已连接工作台及撤权拒绝表单已原生目视。未发现这两张图中的重叠，但表单仍显示原始英文证书异常、内容卡仍偏白；**不算普通用户错误说明、液态风格或全部页面视觉通过**。Pencil未改，87页/12类/24母组件545实例保持原状态。

Rust默认工作区40套件163通过/47忽略（`/tmp/connect-first-pairing-rust-workspace.log`）；新真实负例另显式执行过，不将默认忽略算通过。相关all-target测试clippy、fmt检查与严格Flutter分析已通过。系统设置Forget失败、实验密码后端、量产/OEM/USB/QR/mDNS/过期/网络与后台变化、重装/四端私钥保护仍开放；不以本轮64秒链路关闭01/05/15或完整目标。

最终生成一致性检查通过：build_runner only-check，142输入，11秒（`/tmp/connect-first-pairing-generation.log`）。Android arm/arm64/x64三ABI debug整包102.4秒通过，`/tmp/connect-first-pairing-three-abis.log`。仍没有iOS/macOS/Windows整包证据，不能以Android或跨target check替代。新集成测试未改变应用181项widget基线，本轮未将既往widget结果冒充新增运行；本轮实测为上述两轮产品E2E、真实Runtime负例和所列自动检查。

最后普通lib/main.dart实际安装启动，Impeller(OpenGLES)，按R热重启1,393ms；设备列表空态首屏 `/tmp/connect-first-pairing-main-restarted.png` 已原生目视，未残留本次测试设备记录，随后detach。重启仍有两条FRB旧isolate投递告警，以及启动SurfaceSync/跳帧日志，不声称零运行告警或完整性能通过。本批Core修复/公开负例为914ab41，产品集成测试及宿主fixture为2e3dc5c；既有未跟踪的clipboard/documents/input测试与examples未改、未夹带提交。

## 当前全量复核与异常退出修复

当前结论集中至完成度（历史路径 `../../.scratch/interop/current-status.md`），U01–U44／R01–R60／C01–C32追溯继续保留。本轮追加A43–A49：退出受暂停回执阻塞、系统保存未知状态离页丢失、内拖展开不保持、Android CI未构包、完整ADB服务边界未决、原生产品冲突弹窗及独立应用未知启动后检查可能重提。除下述退出局部修复，其余未记录通过；A49目前是源码路径发现，未冒充故障实测。

### 退出回归和边界

公开RemotePage／typed路由测试先加入暂停抛错与永不完成两种情况，实际均因页面仍存在而失败。离开本地呈现改为不等待远端pause；输入释放仍在原session有序执行，不强停任务。首版修复曾因在返回页Scaffold就绪前发布Snackbar而失败，并发现重复pause；后置反馈、阻止退出中的重复pause后，remote_lifecycle＋session_views共32项通过。

随后扩展为悬浮退出／系统返回×暂停失败／挂起四组合，全部通过：只退回原页面、只pause原session一次、没有session.stop；失败提示确实在返回页可见并包含设备名。复现命令：在 `app/` 执行 `flutter test --no-pub test/remote_lifecycle_test.dart --plain-name 'remains reachable when capture pause' --reporter expanded`。修复本地提交`0bf9cb1`。

这没有证明同session立即重进成功：旧挂起请求仍可能阻塞SessionViews队列。真实断网／暂停故障的Android E2E、恢复核验和资源收束仍须继续，不把widget请求夹具当真实设备负例。

### 合并检查、主应用和设计

- 合并工作区应用195项测试15秒通过，`/tmp/connect-full-audit-app-tests.log`。包括在途主屏应用／连接错误文案的widget回归；本轮未运行这些新行为的完整UI E2E。
- 严格分析首次失败于5处新增代码缺少花括号，修正后 `flutter analyze --no-pub --fatal-infos` 无问题；build_runner only-check 143输入10秒通过，Cargo格式及diff检查通过。本轮没有重新执行整个Rust workspace，不沿用上轮结果冒充本轮执行。
- 普通lib/main.dart实际构建50.4秒、安装并启动，Impeller OpenGLES；CLI实际R热重启1,401ms，设备列表空态 `/tmp/connect-full-audit-main-restarted.png` 已目视，随后detach。仍有两条FRB旧isolate投递警告与SurfaceSync／跳帧日志；不登记为全部页面或低延迟通过。
- Pencil同一文件同类别行新增应用打开方式tch6A及全屏失败主动继续qTeGO；保存关闭重开核对89页／12类／26母组件／557实例／153变量，无断链／缺变量／顶层重叠。主代理另看两张新页；导出只在`/tmp/app-window-design-reopen/`。设计批次`6d00d71`，静态稿不证明对应UI或全89页视觉验收完成。

## 保存生命周期与退出把手复验（A44／A45）

A44实施与运行边界见[内容交付](content-delivery.md)。公开Runtime账本13项通过（12.59秒）；Bridge全量102项通过；页面相关25项通过，独立审查发现admission拒绝后旧身份丢失、完整回执容量失败卡pending两条恢复路径，均另加真实先红后绿回归。持久化先于provider副作用，容量失败不静默淘汰未知／已保存，最小unknown恢复只写元数据。系统保存本地提交`e75bf60`。

双AVD真实内容交付43秒通过，`/tmp/connect-delivery-journal-final.log`、`/tmp/connect-e2e/delivery-journal-final/result.json`。唯一原件63字节，SHA-256 `24517f80a3808bd472d8c1102db2a28ce93eea535b981e5bdaba66eefb863078`，系统取消／保存、完整离页后重进同一传输恢复saved、系统分享至独立receiver、content URI读授权及精确清理均有回执。重进截图已目视。首次`connect-delivery-journal-e2e.log`因路由时序失败：过渡旧页面误算重进，截图实际为文件详情，下一次分享点击未命中；已以旧页消失／当前路由完成／回执可见／命中门槛修正，不计首次通过。Android真实写入中杀进程和unknown恢复仍未验，公开Runtime重开不冒充该故障链路。

A45组件回归8项通过，覆盖左右向内拖开、最近侧边、高速、减少动态及安全区域／尺寸变化。真实产品流程25秒通过，`/tmp/connect-exit-inward-final.log`、`/tmp/connect-e2e/exit-inward-final/result.json`：通过实际连接表单及画质页选择1080，HEVC编码与实际解码486×1080，拖动收起／点击展开／再次收起／向内拖动保持展开／退出后会话暂停保留，严格host回执`inwardExitHandleExpanded:true`。对应截图已目视。当时的实际命令在仓库根目录使用`--driver=tool/driver/integration_test.dart --target=integration_test/product_flow_test.dart`、`CONNECT_E2E_EXIT_HANDLE=1`及`--dart-define=CONNECT_E2E_VIDEO_MAX_SIZE=1080 --dart-define=CONNECT_E2E_MIN_VIDEO_EDGE=1080`，其余endpoint与内容测试相同。首次`connect-exit-inward-e2e.log`因连接表单尚未完成加载失败，补页面与可命中等待后复验；不是放松选择器／质量要求。

本轮两AVD均使用已准备好的API36/secure=0 legacy TCP目标及host15556→5555。不是首次安全配对、物理USB、OEM、通话音频或全部89页验收。仍有SurfaceSync／跳帧及模拟器GLES／BufferQueue释放日志，不登记为性能或零告警通过。

## 真实应用接续与未知启动保护（A49）

应用列表提供独立窗口／在手机屏幕打开，较旧系统保留主屏路径；手机主屏使用既有会话并发送一次明确包名。Core公开`session.launch`校验包名、设备与窗口归属，不强停应用。独立应用START_APP提交前登记固定身份，后续编码首帧失败／渲染输出失败保留unknown记录并清理捕获；页面只读核验，明确关闭后再打开。状态重核验在无sessionId时仍识别同设备／包名unknown，主屏launch同样拒绝绕过。尚未提交的初始动作若在后台完成启动，会在恢复可输入时提交一次；提交前消费意图，未知回执不能重发。

实际先红后绿的路径包括：重复“重新检查”产生两次start；后台完成start后恢复从未launch；待核验入口漏掉unknown并提供主屏回退；公开Runtime主屏绕行返回`sent:true`（`/tmp/connect-app-launch-primary-bypass-red.log`）。最终应用启动10项、生命周期／会话38项通过。公开Runtime两项真实目标测试16.57秒通过（`/tmp/connect-app-launch-guard-green.log`）：原主屏display0任务变化与同sessionId、无效包名／跨设备拒绝、缺包自然首帧错误后的固定unknown、资源释放、主屏绕行拒绝，以及真实编码帧后通过公开清理指令模拟渲染失败并保留真实任务。该清理模型不是实际Android解码故障，unknown目前仅Runtime内，不覆盖进程重建。

双AVD最终真实产品链路51秒通过，`/tmp/connect-app-primary-content-verified.log`与`/tmp/connect-e2e/app-primary-content-verified/result.json`。实际点击应用列表→在手机屏幕打开，复用原ID；host独立观察display0从HOME变Settings，主控实际MDK像素等待内容而非旧HOME／白色启动面，截图已目视为Settings。再实际打开Settings／Dialer独立窗口，三个窗口保留并暂停、逐UUID恢复／截图／关闭，其他窗口存活；9个checkpoint独立检查实际目标进程，全部非整体冻结T态，关闭的精确进程消失。

失败与验收加严原样保留：第一次`connect-app-primary-and-windows-e2e.log`在本地已离页但异步pause尚未回执时即要求paused而失败，现仅只读轮询原ID至5秒上限，不补发pause。46秒后续流程虽通过，主屏截图仍为旧HOME；51秒第一版像素门槛又把白色启动面当内容。两者不计主屏视觉通过，最终加入内容对比门槛并目视Settings后才登记。该已知stock浅色Settings／深色HOME样本门槛不是通用UI识别器，不外推所有应用。当时的命令为仓库根目录下`flutter drive --no-pub -d emulator-5554 --driver=tool/driver/session_workspace.dart --target=integration_test/session_workspace_test.dart`，host指定ADB／target及capture目录，Flutter指定ADDRESS=10.0.2.2、PORT=15556。

真实副屏失败后的手机回退、旧API／OEM、实际renderer首帧故障、unknown跨进程持久化、多实例和任务迁回完整矩阵继续待验。独立代码审查发现的两项新缺陷修复后复核未再发现确定问题；这不替代上述缺口。

## Android持续门禁与本轮全量检查（A46）

CI保留既有`host-checks`身份，显式调用`./tool/check.sh --android`，安装固定NDK并留存成功APK。原生测试是Kotlin object main，不能把Gradle没有JUnit用例时的成功当成这些断言已执行；现同时执行ownership与audio两份runner。Android分支还检查实际包内三ABI的Flutter／Rust ELF class和machine，以及备份／明文策略、单Activity入口与私有前台服务类型。远端job、故障阻断和分支保护尚未运行／配置，不把本地通过写成远端CI回执。

本地首个整条运行因精简PATH漏掉npx而中止；补Node路径后，生成143输入／10秒、格式196文件零改动、可复现JAR摘要、capture JVM检查、workspace all-target clippy、Rust176 passed／49 ignored、严格分析／Riverpod lint负例、应用212项、设计系统3项、driver验收契约和Bridge102项全部通过。官方DESIGN.md工具固定0.4.0：0错误／31警告／1信息，警告仍为既有光学扩展和组件颜色引用，未隐藏。

三ABI整包构建106.8秒通过，4组native main检查通过；新增manifest检查首次误拒绝正确包，原因是apkanalyzer打印数值枚举。固定API36的android.jar经`javap -constants`确认LAUNCH_SINGLE_TASK=2，connectedDevice=16、mediaPlayback=2；解析现同时接受对应符号或精确数值，不放宽错误模式／额外服务位。[ActivityInfo参考](https://developer.android.com/reference/android/content/pm/ActivityInfo#LAUNCH_SINGLE_TASK)、[ServiceInfo参考](https://developer.android.com/reference/android/content/pm/ServiceInfo#FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)。修正后实际Android脚本分支重建11.1秒、两份runner及全部打包校验通过（`/tmp/connect-android-gates-final.log`）。独立样本仅截取实际六个ELF头并将arm64 Rust machine改为x64，原门禁明确报对应架构错误，退出非零（`/tmp/connect-android-gate-negative.log`）；没有修改真实APK或降低门禁要求。

三ABI实际APK暂存`/tmp/connect-lifecycle-three-abis-p7uhsufm/app-debug.apk`，249715366字节，SHA-256 `7d66deab1f04e767d3b2cb6b4f22eeb19f596c44152d001fc409028c34d55102`；回执`/tmp/connect-lifecycle-apk-receipt.json`。这份保留避免后续普通main单ABI部署覆盖唯一产物；不作为Git内容，也不宣称发布签名或其他三平台已构建。日志仍有Java8选项、PlatformDocuments非空断言及模拟器渲染／首屏跳帧等既有警告。

解析修正后最后重新执行**整条**`env PATH=<Rust/Flutter/Node及系统路径> CARGO_BUILD_JOBS=2 ANDROID_HOME=/home/xiankq/Android/Sdk ./tool/check.sh --android`，实际退出0，`/tmp/connect-lifecycle-all-gates-final.log`。同一轮生成143输入／10秒、应用212项16秒、设计系统3项、Bridge102项、Rust176／49 ignored和其余门禁全部通过，三ABI增量构建2,384ms，随后4组native main及实际manifest／ELF通过。此前npx缺失和错误数值枚举解析的两次失败日志仍保留，未合并包装成首次整条通过。

最后普通`lib/main.dart`实际构建11.3秒、安装启动，CLI按R热重启1,417ms，设备列表空态`/tmp/connect-lifecycle-main-restarted.png`已目视，随后detach。默认浅色／黑色主动作、紫色小图标、玻璃底部导航与固定设备首页可见；不以此替代全部设计状态或独立光学验收。仍有两条FRB旧isolate投递警告与启动SurfaceSync／跳帧日志，未称零运行告警。

## 本次逐指令审计后的实际实施

当前权威状态仍是当前完成度（历史路径 `../../.scratch/interop/current-status.md`），12领域／20原任务均未整体关闭；逐条U01–U44／R01–R60／C01–C32及新增A50–A56见重新核查（历史路径 `../../.scratch/interop/completion-reassessment.md#23-审计后的实际修复与当前边界`）。下面证据更新前面的历史缺口，不把局部通过外推成完整产品。

- `68cec63`：A52可信GUID发现候选、Required TLS及更新／撤销／ABA代际屏障；七项真实DNS-SD／TLS最终89.08秒通过，cached旧连接发布实际先红后绿。每GUID八个活动服务，仅信任记录缓存，无无界墓碑；首次配对快速发现仍取首地址，物理切网／Wi-Fi2等仍缺。[细节](wireless-reconnect.md)。
- `6abdedc`／`c08178d`：A49／A50私有持久启动操作与主屏独立UUID、断开／Runtime重建待核验、队列取消许可；四项真实Android公开Runtime50.17秒通过，包含真实START_APP丢ACK／前序ACK阻塞、精确取消后无旧启动、写盘失败／设备级关闭。49项页面／生命周期／视图回归通过，核对和关闭不被key-up／pointer-cancel／pause回执挂住。Runtime重建不是Android现场杀进程，真实decoder／副屏回退UI仍缺。[细节](app-launch-recovery.md)。
- `041452c`：A48系统目录冲突共享Flutter页／协调器，精确操作和冲突ID、当前批次策略／取消／离页。真实系统文件选择和独立文件核验最终r5全3分02秒通过；目视第四轮发现零成果误报后，先红后绿并再次实际复验。此前入口／回执夹具错误不计通过。USB产品选择、provider及中断矩阵仍缺。[细节](content-delivery.md#共享系统目录冲突与零成果结果)。
- `99491be`：A54十二个Apple官方正文来源，补自身互通与FaceTime移动端获允远控，区分事实／产品决定／代理建议；没有Apple实操，不增加已排除功能。[研究](../research/apple-continuity-workflows.md)。
- `82a8fb8`：中文配对错误与实际重新配对入口，公开16项通过；首轮真实链路捕获auth失败仍英文，补准确分支／公开红绿后完整66秒通过，`/tmp/connect-oct17-connection-feedback-r2.log`及`/tmp/connect-e2e/connection-feedback-r2/result.json`。实际rawpeer拒绝与中文呈现分开校验；fresh码／Required TLS／系统接口精确撤权／独立清理均成功，hostErrors为空。已目视工作台和撤权中文截图，不拍配对码。直接Settings Forget和量产设备仍未验。[细节](first-pairing.md#中文错误与重新配对入口复验)。

整条`tool/check.sh --android`r2退出0：`/tmp/connect-oct17-all-gates-r2.log`，应用229／Bridge106／设计3、Rust176passed／58ignored，146输入生成、严格分析／clippy、可复现capture JAR／JVM、负例lint、三ABI APK／四组native／实际manifest和ELF通过。首轮因Rust if-let格式失败，格式修正后整条重跑，不隐藏失败。新中文auth分支在此后修改，因此该r2不能冒充最终当前代码门禁；r3和普通main复验待追加。DESIGN0错误／31警告／1信息、Java8和既有Kotlin断言警告保留。

iOS／macOS／Windows Rust核心交叉check分别5.92／4.56／4.36秒通过，`/tmp/connect-oct17-core-cross-checks.log`；没有三宿主Flutter链接／整包证据。本批源稿仍89页，无仓库pen修改，导出全部在临时目录。IME／通话音频／AV同步／资源降载、缓存／相册、入站指定设备提交、后台恢复、完整ADB／生产密码及动态视觉／性能／无障碍等目标继续开放。

中文分支后最终当前代码**完整r3退出0**，`/tmp/connect-oct17-all-gates-r3.log`：应用230／Bridge106／设计3，Rust176passed／58ignored，146输入生成一致、200文件格式零修改、严格分析／clippy／插件负例、capture JAR／JVM、driver契约与DESIGN检查通过；三ABI APK24.9秒、四组native与实际打包manifest／ELF通过。默认ignored仍不计通过，真实DNS-SD／TLS七项和真实应用故障四项由上面的独立命令证明。其他三平台仍只有Rust核心cross-check，不变成完整宿主产物。

最后普通`lib/main.dart`实际构建16.4秒、安装683ms、CLI R热重启1,982ms，`/tmp/connect-oct17-main-final.log`。截图`/tmp/connect-oct17-main-restarted.png`已目视：设备列表固定首屏、浅色／黑色主动作、紫色小元素与玻璃底导航可见，随后detach。DTD可发现IDE实例但无active app，因此实际重启在本次CLI完成；两条FRB旧isolate及SurfaceSync／启动跳帧仍有，不称性能／零告警或全页面设计通过。未push，原先未跟踪的clipboard／documents／input与examples未夹带提交。

## 相册动态范围与稳定分页（A53，2026-10-18）

设计批次`f264bf1`、代码批次`513fb38`：当前用户主共享存储动态检查，明确排除／未读范围、停止与离页精确取消、mtime冻结快照分页、主动刷新及换设备隔离。10项公开Runtime协议fixture和7项公开页面测试通过。目录4097媒体被丢空、fallback失败项漏计预算、64issues后预算耗尽panic都由fixture先红后绿修复；每快照8MiB计typed容器和字符串容量，不是磁盘缓存预算。[公开契约](gallery-index.md)。

实际双AVD第三轮85秒完整通过：`/tmp/connect-gallery-index-r3.log`、`/tmp/connect-e2e/gallery-index-r3/result.json`。105个原件含共享根、Download、自定义、Android/media，实际加载更多／范围面板／主动刷新106项且旧快照105项；宿主独立原文4207字节、105项大小、精确清理全部true，hostErrors为空。前两轮截图args和滚出汇总的夹具失败原样保留，不作通过。

完整`tool/check.sh --android`退出0（`/tmp/connect-gallery-all-gates.log`）：应用237／Bridge106／设计系统3、Rust186 passed／58 ignored、150输入生成一致／205文件格式零改动／严格分析与clippy／capture JAR与JVM／lint负例、三ABI APK125.8秒／四组native main／实际manifest和ELF通过。DESIGN31警告／1信息、原有Kotlin警告保留。新增核心对iOS／macOS／Windows check分别3.80／3.24／2.89秒（`/tmp/connect-gallery-core-cross-checks.log`）；不是对应宿主Flutter整包。

Pencil保存关闭重开已核对93独立页／12行类别／26母组件／588实例／153变量；四个新增相册代表状态已目视，预览只在/tmp。该轮实际截图又发现A57多图缩略图并发失败，原至少一张解码门槛不足以证明网格可用；共享调度与更强真实多图门槛单列验收，不能从上述门禁继承。A51磁盘预算、持续增量、真实拒权／低内存／大原件／回收及其余完整领域继续开放。

## 多图调度和实际锁版后续（A57／A58）

`7654619`：共享设备队列、精确取消、busy有限恢复／手动重试；9项新公开widget与7项相册回归、严格分析通过，独立只读review无新证实问题。真实第四轮1分59秒（`/tmp/connect-gallery-index-r4.log`），首屏15张与滚动后21张可见缩略图全部实际解码；105原件范围／分页／刷新、宿主原文4207字节／全部大小／精确清理全true、hostErrors为空。回执`/tmp/connect-e2e/gallery-index-r4/result.json`，两张网格已目视，不再以单张解码证明网格可用。该轮发生在mDNS锁版修复之前，保持场景证据边界。

`e776065`：实际mDNS旧锁版核查发现上游已修复的HINFO越界panic，将生产与测试统一精确0.21.2，无发现适配源码变化。窄ADB／Core全部测试目标check、已有discovery单测通过；四端增量依赖树无新增C构建或原生密码／USB实现，系统FFI仍保留。API／feature／版本差异与影响事实、推断分别见[锁版研究](../research/locked-mdns-contract.md)。

HINFO验证只运行修复版已有回归：将registry发布源码原样复制到`/tmp/interop-a58-mdns-rm3xpyvi/mdns-sd-0.21.2`，运行`env CARGO_TARGET_DIR=/tmp/interop-a58-upstream-target /home/xiankq/.cargo/bin/cargo test --manifest-path /tmp/interop-a58-mdns-rm3xpyvi/mdns-sd-0.21.2/Cargo.toml --lib test_hinfo_char_string_at_end_of_packet --locked`。原测试1 passed／53 filtered，构建6.85秒；没有修改registry／生产解析器，没有本地旧版坏包红测，也没有向共享5353注入消息。

新锁版真实公开Runtime DNS-SD／TLS七项77.36秒全部通过（`/tmp/connect-mdns-safe-reconnect.log`）；不是默认忽略后被计通过。iOS／macOS／Windows核心cross-check分别4.24／4.18／8.26秒通过（`/tmp/connect-mdns-safe-core-cross-checks.log`）。Core发现异常关闭后的重建、其他上游修复、A56其余依赖契约与三宿主Flutter整包仍未关闭。

本批最终完整`tool/check.sh --android`退出0（`/tmp/connect-gallery-mdns-final-gates.log`）：应用246／Bridge106／设计3、Rust186 passed／58 ignored、152输入生成一致／208文件格式零改动／严格分析与clippy／lint负例／capture JAR和JVM、三ABI APK184.1秒／四组native main／实际manifest及ELF均通过。DESIGN仍31警告／1信息，既有Kotlin警告保留。没有把默认ignored计通过，也没有把旧锁版门禁继承为新锁版通过。

最终普通main实际构建15.2秒、安装881ms，CLI R热重启2,929ms，日志`/tmp/connect-gallery-mdns-main.log`；截图`/tmp/connect-gallery-mdns-main-restarted.png`已目视，设备列表固定首屏／浅色黑主动作／紫色小元素和玻璃导航可见，随后detach。仍有两条FRB旧isolate投递告警；这是普通入口检查，不代表完整视觉或性能。相册范围面板的短内容空白／灰色材质层次已记为实际视觉待改。

普通main部署覆盖同路径APK，第一次留存副本缺armv7，独立ELF校验明确拒绝，未记为三架构产物。detach后以同一源码另建三ABI APK，44.9秒通过，`/tmp/connect-gallery-three-abis-retained.log`；立即复制并独立核对六个Flutter／Rust ELF。有效保留物`/tmp/connect-gallery-verified-apk-bo5dw7zs/app-debug.apk`，250013986字节，SHA-256 `2df5e735d8e5027139f250e6526ad1f7f62a7238e4c0d40e21c7e00a94118a7d`；回执`/tmp/connect-gallery-apk-receipt.json`。这是临时调试包，不是发布签名／其余宿主产物，不进Git。

## 渐进交付：活动页独立停止设备声音（A23，2026-10-18）

公开Runtime双设备ADB协议fixture验证精确音源活动、停止保留B、旧sourceId不误停替代源；它不替代真实Android。Flutter活动页确认／精确activityId与既有PortableAudioOutputs共23项通过；新增中文播放状态断言先红后绿。相关5文件严格分析无问题。

当时真实运行：在仓库根目录执行`env PATH=<toolchain> ANDROID_HOME=/home/xiankq/Android/Sdk CARGO_BUILD_JOBS=2 CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/audio-activities-r3 flutter drive -d emulator-5554 --no-pub --driver=tool/driver/audio_activities.dart --target=integration_test/audio_activities_test.dart --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=15556`。第三轮9秒通过，构建10.3秒／安装856ms，日志`/tmp/connect-audio-activities-r3.log`。严格driver要求8个结果全部true及3张截图；回执`/tmp/connect-e2e/audio-activities-r3/result.json`满足。实际PCM、fvp准备／播放与时钟前进后，活动页确认停止，Core源及精确本地输出消失，连接／观察及基线媒体保留，finally清理完整。播放／确认／停止后截图已目视。

首轮在observation.start返回starting时错误要求终态；改只读轮询后继续。第二轮MissingPluginException发生于截图：先前普通main的自动GeneratedPluginRegistrant排除了dev测试插件，而--no-pub没有重新生成；执行离线flutter pub get恢复自动注册后第三轮通过。没有手改注册器或生产Kotlin，没有把失败计通过。

本批按用户要求只跑对应窄检查与这一条实际链路，前批完整门禁／三ABI APK不可冒称A23的门禁或产物。物理音频输出、真实多源同时播放后只停一台、后台／进程恢复及通话仍独立待验。

## 渐进验收：入站PNG固定接收设备（2026-10-18）

当时在仓库根目录，以明确独立controller／target／secondTarget环境运行`flutter drive -d emulator-5554 --no-pub --driver=tool/driver/incoming_share_target.dart --target=integration_test/incoming_share_target_test.dart --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 --dart-define=CONNECT_E2E_PORT=15556 --dart-define=CONNECT_E2E_SECOND_PORT=15558`（完整环境与fixture构建见[内容交付](content-delivery.md#外部入站内容的固定目标)）。首轮14秒通过、构建52秒／安装745ms，`/tmp/connect-incoming-share-target-r1.log`、`/tmp/connect-e2e/incoming-share-target/result.json`。

三AVD互异名称＋两端独占marker同时由host和公开files.list核对映射，外部非导出provider凭真实grant向产品提交PNG。页面明确选A后调用公开focusDevice(B)，仍只向A上传；host独立读取68字节与SHA256 `ce01132c640469ef7fb497e7496b12f5046d633b588f397e5c45a6c3efc85037`一致、B无同路径文件、消费后两次刷新不新增传输，精确清理全true。目标确认截图已目视；两台同型号默认同名的选项仍需可辨识线索，不以此声称完整视觉完成。窄分析通过；不沿用上一批全门禁。

运行准备期间宿主发生重启（uptime证据），先后出现磁盘不足及KVM权限暂不可用；只清理本仓可重建Rust增量缓存，KVM恢复后重新启动隔离AVD。两条占约20GB的编辑器只读文件扫描已结束，无配置修改。此前/tmp日志／预览随主机重启消失属临时证据生命周期；本轮通过证据写入新/tmp目录，不伪造恢复测试。该事件不是产品进程或网络恢复通过。

## 渐进输入／通话UI接续与视觉边界（2026-10-18）

最终公开页面43项通过，`/tmp/connect-ime-calls-widget-final.log`；最终6文件严格分析无问题。IME组合结束／文字不变漏提交和入口不自动聚焦两处分别先红后绿；前者仅onChanged，后者外层Focus先抢焦点，需要明确requestFocus。

真实IME第七轮30秒通过（2.64秒构建／555ms安装），`/tmp/connect-remote-ime-r7.log`、`/tmp/connect-e2e/remote-ime-r7/result.json`：真实decoder／公开键盘工具、实际scrcpy touch与系统Settings六个独立XML checkpoint，原文你好🙂一次、组合无泄漏、延迟不重复及查询恢复，inspectionError=null。[完整命令和失败](mobile-ime.md)。第1–4轮ANR／异步工具加载／真实焦点缺陷／XML实体读取失败不计通过；第5轮功能通过但主控ANR遮盖截图，第6轮因通话测试旧ENDCALL清理导致目标Asleep失败，已改精确取消自有模拟号码并显式唤醒。

**A59视觉未通过**：第7轮目标截图显示新文本，主控截图仍为空查询。这里只证实捕获时差异，尚未对齐实际绘制／媒体PTS，不据此断言永久停帧；首帧snapshot不证明持续画面更新。保留原图／回执，回填07／08／20，后续限定时窗验证新像素。

通话当前UI接续真实Runtime最终9.94秒／构建1.28秒通过，`/tmp/connect-call-system-ui-r2.log`。先让Settings前台，再calls.open并独立dumpsys确认真实InCallActivity前台，modem仍ringing；旧操作不能结束替代call。夹具只取消自己的两个模拟号码，不再全局ENDCALL。该证据不替正式CallsPage→全屏像素E2E，不代表具体callId控制或双向音频。[命令与JAR摘要](current-call-ui.md)。本批未跑新的完整门禁／三ABI留存或其他宿主整包。

普通lib/main.dart当前源码实际构建27.7秒／安装555ms，CLI R热重启1,763ms，`/tmp/connect-ime-call-main.log`；设备列表空态截图`/tmp/connect-ime-call-main-restarted.png`已目视后detach。两条FRB旧isolate投递告警和启动跳帧仍有，该首页不代替A59或完整动态视觉。

## Dart 工具与主机测试目录迁移（2026-10-19）

该阶段根目录保留 `test/` 与 `integration_test/`；主机驱动及基准分别迁至 `tool/driver/`、`tool/benchmark/`。35 个仓库自有 Python 文件已由 Dart 实现取代，覆盖生成、签名／打包、服务端构建、原生 JVM 回归、夹具构建与性能证据分析。官方 DESIGN.md Node 工具和受控来源归档保留。

根应用323项通过，`/tmp/connect-dart-migration-flutter.jsonl`；工具49项通过，`/tmp/connect-dart-migration-tools.jsonl`，包含原分析器回归、协议生成精确字节、FRB隔离、APK本地与中央目录CRC、ELF、Windows bundle、Apple归档权限与链接、manifest失败门禁。Windows及Apple打包测试使用主机夹具，不代表对应宿主整包构建。最终静态分析、311个Dart文件格式、Rust格式、129条协议与完整token／FRB／builder生成一致性检查通过，生成日志为`/tmp/connect-dart-migration-generate.log`。

三类服务端产物检查、companion临时重建逐字节比较、四组Java兼容回归及ZIP／DEX／摘要漂移负例通过；Java源、运行JAR、四ABI ELF和对应源码归档字节未改。六种独立测试APK均在本机Linux／SDK36实编译、签名并验签，随后清理临时输出；本轮未重新执行设备端采集或其他宿主构建。

JVM ownership／音频、实际snapshot接缝、三个CMake用例、驱动验收契约、截图解析和故障代理通过。既有x64 debug交付APK由新Dart工具复核ZIP、签名、16KB对齐及ELF，摘要仍为`7369a0ab259df8f0f78f3bbdda08088f50b53f90eebb72a9ca21f55b0f4f8211`，回执为`/tmp/connect-dart-migration-apk.json`；未新建三ABI APK。现有应用热重载成功，运行时错误查询为空，随后detach。

## 切回社区原版 fvp 0.39.1（2026-10-19）

应用实际解析为 pub.dev hosted `fvp 0.39.1`，不再使用本地源码副本或 path override。原版 `callbacks.cpp` SHA-256 为 `d31142aa65b299a0a471caabae7bdb3f20b902e9239e88beb5babca3d1ca623e`；本次 Android CMake 的 `CMAKE_HOME_DIRECTORY` 指向 pub cache 内该包，`FVP_DEPS_URL` 与 `FVP_DEPS_SHA256` 均为空。构建复用 MDK 0.39.0 缓存，stamp 为 `70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`；这不是一次新下载，也不证明四端 MDK 已固定。原版 snapshot 空结果未判空的已知限制仍按[工具链契约](repository-tooling.md#社区原版-fvp-0391)保留。

当时在根目录执行 `flutter test --no-pub test tool/test tool/e2e/tests`，371 个非 hidden 项全部 success、无 skip，日志为[根应用与工具 JSONL](/tmp/connect-community-fvp-tests.jsonl)。桥接层131项全部 success、无 skip，日志为[桥接层 JSONL](/tmp/connect-community-fvp-bridge.jsonl)。`flutter analyze --no-pub --fatal-infos` 在19.4秒通过；`dart tool/generate.dart --check` 完整通过，日志为[生成检查](/tmp/connect-community-fvp-generate.log)。这些结果不包含已移除的本地 fvp 补丁与 MDK 固定回归。

普通 `lib/main.dart` 入口的 Android x64 debug APK 实际构建138.1秒通过，[构建日志](/tmp/connect-community-fvp-build.log)。产物为 `build/app/outputs/flutter-apk/app-debug.apk`，125,062,865字节，SHA-256 `ab5fcf9b9d796d53297c3e290573de132c489cae87f1cf06474b03a0ae853967`。独立 ZIP 完整性、签名、x64 Flutter/Rust ELF 及16KB对齐检查通过，[产物回执](/tmp/connect-community-fvp-apk.json)；这是 x64 调试产物，不是三ABI或发行签名产物。

本次编译命令中的 `callbacks.cpp` 路径指向 hosted 包源码。APK 内 `lib/x86_64/libfvp.so` 与本次插件输出的 SHA-256 一致，均为 `b0650287e507a00f5dc4d5db567732254d5ce8df9e18f265c302d3570edaf9e4`。

该普通包覆盖安装到 `emulator-5554` 后启动，观察到 pid21411 与 Impeller OpenGLES。Dart MCP 热重启成功，运行时错误查询为空；热重启期间仍有两条 FRB failpost 旧 isolate 投递警告，保留该观察，不记为零告警启动。

本次未重跑远控、媒体 E2E 或其他宿主构建／运行；此前本地补丁版的首帧、snapshot、GPU 和业务通过不继承为社区原版通过。此处只记录已执行的测试、静态分析、生成一致性、Android x64 打包与普通入口启动范围。

调试结束已 detach，保留既有模拟器及其应用。清理26项构建中间目录、测试资产与重复 APK，共2,031,439,569字节；`build` 仅保留上述普通入口 APK，复用的共享原生、Rust、Gradle 和 pub 缓存保留，[清理回执](/tmp/connect-community-fvp-cleanup.json)。删除源码副本前，两份未提交文件已备份至 `/tmp/connect-fvp-uncommitted-ZhtXcw`。

## 社区原版下的内存输入实验（2026-10-19）

独立分支 `codex/mdk-memory-input` 已用 Rust → MDK appendBuffer 跑通实际解码和Texture像素核验。Android-x64 profile包在同一AVD交错8轮，扣除两轮预热后，与HTTP按相同PTS比较，未见明显延迟或CPU收益。生产 `dev` 未合入实验适配器；完整方法、输入身份、逐轮结果、早期失败及尚未验证的契约见[专项记录](../research/mdk-memory-input-experiment.md)。该实验没有覆盖实际ADB全链路或其他平台。

实验结束恢复上述普通debug APK，摘要未变；实际安装启动、MCP热重启成功，运行时错误查询为空，随后detach。清理本次夹具、重复APK和过期中间输出，净1,417,018,559字节；保留原始输入、测量回执及复用缓存。

### 后续解码后端定位

同日继续完成18轮单变量输入对照：明确Cluster长度、direct、noparse及若干AMediaCodec选项均未消除该AVD约一帧等待；保持HTTP/容器不变，仅改FFmpeg slice后输入到onVideo降至约1.6ms。最后4轮软件后端HTTP/append对照均通过20ms诊断门槛、像素与清理核验。完整方法、逐轮结果和未确定的SDK内部边界见上述专项记录；[官方客户端研究](../research/scrcpy-client-latency-path.md)解释参考路径。这不宣称所有Android都应软件解码，也不冒充完整首屏、物理设备或生产修复通过。

诊断工具保留在 `codex/mdk-latency-diagnosis`（最终工具提交 `1cd5d1b`），生产未合入。4个相关Dart工具分析通过；恢复普通APK、热重启及runtime error查询通过，pid24365，随后detach。再次清理该阶段过期构建输出和夹具1,305,212,943字节；普通APK摘要及共享编译缓存保留。

## Flutter 主应用迁入 app（2026-10-19）

从 `e549f5f` 的根目录应用迁至 `app/`，直接承载源码、应用测试和五个平台 runner。根目录保留 workspace 与仓库工具依赖，依赖版本及内容摘要未变，锁文件仅调整根包依赖的分类。当前目录与命令职责见[工具链契约](repository-tooling.md#应用与-workspace-职责)。

根目录和 `app/` 的离线锁定依赖解析均通过。应用323项、工具49项、设计系统11项、桥接层131项测试全部通过；对应日志为 `/tmp/connect-app-tests.log`、`/tmp/connect-app-tools-tests.log`、`/tmp/connect-app-design-system-tests.log`、`/tmp/connect-app-bridge-tests.log`。全仓严格分析无问题，309个Dart文件格式检查无变化；Riverpod插件故意违规检查、driver验收契约和四组原生JVM契约均通过。完整token／FRB／builder生成一致性检查通过，官方DESIGN.md检查仍有63条警告，未计为零警告；日志为 `/tmp/connect-app-generate.log`。

从仓库根运行 `dart tool/android.dart build --mode debug --abi universal --no-pub`，工具在 `app/` 构建普通 `app/lib/main.dart` 入口，实际耗时170.39秒。三ABI为 `armeabi-v7a`、`arm64-v8a`、`x86_64`，ZIP完整性、签名、Flutter／Rust ELF和16KB ZIP对齐均通过。产物位于 `app/build/app/outputs/flutter-apk/app-debug.apk`，262,755,323字节，SHA-256 `24197483b81f62914e23712491a8990d2bd7820aa37d7c5f5f65930efc4b53a4`；日志为 `/tmp/connect-app-build.log`。这是debug包，不是发行包。

覆盖安装到原有API36/x86_64主控 `emulator-5554`，从 `app/` 使用上述APK启动。MCP热重启成功，CLI记录1404ms，运行时错误查询为空；inspector确认 `ConnectApp`、`HomePage`、`DevicesPage` 与“设备”标题。热重启期间有两条FRB向旧isolate投递失败警告，未登记为零告警。detach后pid25107仍在，回执为 `/tmp/connect-app-runtime.json`。本轮没有重跑远端设备业务、延迟实验、Apple或Windows整包构建。

结束后删除旧根目录APK、重复APK、测试资产和过期Flutter构建输出，28项共3,594,319,772字节，保留上述唯一普通APK以及共享native hooks、Rust、Gradle与pub缓存；清理后APK摘要未变，回执为 `/tmp/connect-app-cleanup.json`。另已删除迁移前生成的iOS／桌面平台临时配置，后续由对应平台构建重新生成。既有主控模拟器与应用数据保留。
