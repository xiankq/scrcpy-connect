# 实施与真实验收记录

目标入口为 [.scratch/interop/goal.md](../../.scratch/interop/goal.md)。下列结果区分协议单测、真实被控 adbd 和 Android 主控界面；未列通过的能力不推定已完成。

## 当前环境

Ubuntu 24.04 x86_64；Rust 1.99.1；Flutter 3.47.6 / Dart 3.13.5；Java 21；Android SDK 36，NDK 28.2.13676358。两个独立 API36 x86_64 Google APIs AVD，经 KVM 加速无头运行：controller emulator-5554、target emulator-5556。官方 adb 仅部署/对照，产品仅经 Rust 直连。主控测试部署调试不构成产品使用条件。

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
| Flutter UI | 43项widget tests通过；实际资产浅/深/不透明/平板截图；新增测试后继续回归 | `flutter test` |
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
- Android实际Texture首帧、全屏点击、拖动收起、展开退出与HOME后台恢复已通过。native_audio_test完整通过AudioTrack首次write、同设备去重、音量/静音/停止；实际音频暂停/焦点尚待补齐，完整分享入站与故障矩阵继续验证。
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
- Android本机下载改为私有暂存，传输持久`destinationScope:privateCache`；“取回”与“保存到系统位置”分开。系统SAF流式导入/导出尚在实施，不以cache复制冒充保存完成。
- 新ADB真实验收：reverse完整双向TCP并发、JDWP、单路径LST2及Brotli/LZ4/Zstd压缩双向互操作通过；ABI交叉check Android两ABI/iOS/macOS/Windows通过。`81e3bd2`记录本批。
- 一次dev:服务探索对不可epoll文件触发官方adbd abort（API36指纹BE2A.250530.026.F3，错误epoll EPERM），系统重启丢失host转发；已移除泛化文件API/测试，未改权限或重启adbd，恢复测试端口后真实回归通过。文件传输继续只走sync。
- 免视频剪贴板companion真实2项通过：Unicode往返、独立companion写入触发Binder事件与启动中断开。默认校验1项及原通知实时回归通过；主控自动同步协调仍在实施。
- 显式隔离休眠用例通过：`INTEROP_ALLOW_DEVICE_SLEEP_TEST=1 INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 cargo test -p interop-core --test device_lifecycle sleeping_target_requires_explicit_wake -- --ignored`。目标Asleep/Dozing时`session.start`返回`device_asleep`且不创建会话，用户明确`devices.wake`后实际回到Awake；没有声称该用例验证了密码锁或生物认证。
- 取消连接回归改为分别核验网络和持久化：新attempt socket必须2秒内真实EOF，旧attempt取消不得关闭它；磁盘fsync另给20秒期限，避免繁忙宿主把持久化慢误报网络取消失败。默认5项通过。
