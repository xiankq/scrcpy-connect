# ADB 应用失活检测与恢复

> 本文按问题保留连接恢复的实现说明与 2026-10-18 历史实验。各段“当前”指该段验证阶段，旧 SDK 摘要及故障夹具命令只用于复现实验；当前受控依赖见 [工具链契约](repository-tooling.md)。用户可见的恢复行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准。

## Companion 断线回收（2026-10-18）

实现6fb5c33。原helper进程退出后的删除命令使用同一Client；传输已经断开时，
进程虽消失，远端临时JAR仍会残留。新增实际Android回归直接启动原companion，
保留独立检查连接，关闭其真实ADB Client，不发送media.shutdown或主动disconnect。
原实现6.88秒失败：`process_exited=true automatic_jar_cleanup=false`；测试随后仅
补清自己的精确路径。最早red.log是按Java类名查进程的错误夹具，不算有效复现。

现在由Rust生成远端shell launcher，不修改companion或scrcpy JAR。后台子进程
使用exec成为真实app_process；launcher保留自身job，正常结束或HUP／INT／TERM时
终止并等待该job，之后才删除唯一部署路径。正常退出码、stdout READY、RPC认证
保留；不信号保存的裸PID，不按文件glob删除。host原有精确路径删除作为兜底保留。

[adbd shell_v2](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/shell_service.cpp#579)
在协议FD结束时向shell发送HUP，而不是遍历子进程。不能只把Java放后台后假设它
也会收到信号。[mksh jobs.c](https://android.googlesource.com/platform/external/mksh/+/android-16.0.0_r1/src/jobs.c)
的builtin jobs先移除已完成job，再以%1发TERM／CONT，保存的child只用于builtin wait，
不用于生产信号发送。等待完成前不启动清理用外部程序，避免新job占位。

额外STOP用例曾暴露先`exit 129`再依赖EXIT trap的失败路径：
[mksh exit](https://android.googlesource.com/platform/external/mksh/+/android-16.0.0_r1/src/funcs.c#2156)
会先检查stopped jobs并输出警告；stderr已断开时可能SIGPIPE终止，尚未执行EXIT。
SIGPIPE是源码支持的解释，不是本次内核信号实测。最终signal trap直接调用cleanup，
忽略进一步信号，TERM后CONT恢复停止的job，再wait；wait的stderr丢弃以避免断管。
没有采用等待前台child的no-op HUP，或向整个进程组发信号的候选。

```sh
INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:25556 rtk proxy cargo test -p interop-core \
  --lib companion::deployment_tests -- --ignored --nocapture --test-threads=1
rtk proxy cargo test -p interop-core --lib --test application_liveness \
  --test device_lifecycle --test tls_connection_policy --test state_snapshot -- --nocapture
rtk proxy cargo clippy -p interop-core --all-targets -- -D warnings
```

设备端须是隔离且已授权的Android，25556为本机到adbd的明确forward。两项实际
设备用例最终4.18秒通过，覆盖原Java服务的真实传输丢失，以及实际mksh的exit0、
exit7、普通断线、STOP后断线。退出trap在child结束前确认JAR仍在，自动删除后检查
标记；成功场景没有fallback。测试失败兜底逐次验证PID starttime与唯一fixture argv，
归属消失才删精确jar／marker／pid；check和signal仍非原子，不作为生产身份承诺。
99项相关回归通过、10项条件忽略，设备用例另行显式通过；严格clippy及Core三宿主
交叉check通过，不代表iOS／macOS／Windows的Flutter整包链接或运行验收。
日志／回执前缀`/tmp/connect-companion-exit-`，早期候选失败原件保留。

正式Flutter RemotePage在双API36／2vCPU SwiftShader AVD真实EOF恢复14秒完整通过，
1483ms得到新session、实际像素0→1、主动停止不重建；proxy接受2／切断1、fault
errors空、fixture卸载及缺席／Settings恢复／driver与proxy关闭均确认。恢复后全屏
VIDEO1及悬浮退出已目视。原件`/tmp/connect-e2e/companion-launcher-recovery/`，
实测APK`/tmp/connect-artifacts/companion-launcher-recovery-debug.apk`，SHA256
`3c457ebc5e54f332a45c581e552405b4b37c9811fd60e86b05f93e470e8fefa4`，
构建70.5秒／安装629ms。实际x86_64桥接库完整含原生产捕获／companion JAR；
三份生产JAR摘要不变，没有重建，也没有改变视频质量／解码参数。

结束时本批helper／launcher／捕获JAR和进程缺席，成功场景无需人工补清。两份已在
上一轮回执中的音频fixture JAR和历史文件目录保留；不宣称远端临时目录完全空。
Gradle停止、两个精确forward清除、自有AVD核名关闭且PID消失；删除两份与实测包
摘要相同的APK副本共230.3MiB，空闲32.67GiB，保留有效缓存和可复用中间输出。

覆盖范围是launcher已启动后的收尾。上传中断、wrapper SIGKILL、断电与跨重连的
待清理账本仍开放。已有MediaCodec／BufferQueue／GL停止告警原样保留；本次不关闭
MDK snapshot崩溃、首帧／动态预算、物理无线或小时级长稳，也没有声称延迟改善。

## 旧连接清理与恢复后新会话的顺序（2026-10-18）

旧monitor在connections锁下移除closed Client，随后释放锁、按deviceId写offline并
异步停止活动。手动重连可在此期间发布新Client，旧清理会覆盖新状态或通过
resource_admission.cancel_device取消新视频启动。真实Client／Duplex transport与
真实资源准入的回归，用现有observations锁固定交错，原行为3.84秒失败，明确记录
“old teardown cancelled video admitted on the replacement Client”。没有模拟一套
新的连接状态机，也没有把该测试称作完整实际编码器竞态复现。

现在每台设备独立串行化连接发布、旧连接清理及显式disconnect；全局gate表仅短暂
访问，不持它等待设备锁。monitor在同设备约束下，以store→connections锁顺序
重新核对closed状态、撤下旧连接并更新offline，再完成原活动清理和持久化；陈旧
扫描不能处理健康替代Client。attach也在发布前补完已关闭连接的清理，避免手动
重连抢在下一次monitor之前。显式disconnect先原子撤下Client，阻止清理期间仍通过
旧连接准入新活动；
DetachedConnection guard保留精确旧传输，供已有媒体owner确认shutdown并删除临时
文件。正常、失败或caller取消退出时，均先关闭该旧Client，再释放同设备gate；
主动停止的现有语义保留。

初版仅串行化仍不够：caller超时可在旧Client已移除、活动尚未清理时丢弃future，
后一连接便误以为无旧工作。新增取消回归2.27秒再红。最终以cleanup_pending保留
未完成收尾，直到活动清理及持久化成功才清除；新attach先补清理，monitor也继续
没有调用者的遗留清理。空闲且完成的gate在后续访问中移除，等待者或未完成项保留。
不在取消时安排可能晚到而越权清理新活动的无约束任务。

五组回归覆盖：旧monitor清理与新视频启动、显式断开期间同设备等待／
另一设备可发布、手动替换提前清理／过期扫描、新caller接续取消清理、monitor在
无新caller时继续收尾，以及disconnect caller取消仍关闭精确旧传输。定向全部通过；
最终Core lib85 passed／6 ignored，应用失活3、设备生命周期5／2 ignored、state snapshot2、TLS策略4通过，总99 passed／
8 ignored；条件忽略不作设备通过。严格all-target clippy通过，只读review未发现
新确定缺陷。第一次filter_map布尔then风格检查失败已按建议修正。

```sh
rtk proxy cargo test -p interop-core --lib connection_cleanup_tests -- --nocapture
rtk proxy cargo test -p interop-core --lib --test application_liveness \
 --test device_lifecycle --test tls_connection_policy --test state_snapshot -- --nocapture
rtk proxy cargo clippy -p interop-core --all-targets -- -D warnings
```

红绿与最终检查日志前缀`/tmp/connect-connection-cleanup-{red,green,cancel-red,transport-unit,
final2-regression,transport-clippy}.log`。Core对aarch64-apple-ios、x86_64-apple-darwin、
x86_64-pc-windows-msvc交叉check2.307／2.431／2.330秒通过；非三宿主Flutter链接。

最终双API36／2vCPU／2048MB SwiftShader AVD，正式RemotePage+Rust+真实adbd的
EOF恢复14秒完整exit0：host故障ack后1722ms获得新session，实际Flutter图案0→1，
主动stop后不再捕获；proxy接受2／切断1、fault errors空，fixture卸载／缺席、
Settings恢复、driver／proxy退出均确认。恢复后的VIDEO1全屏及悬浮退出已目视。
命令沿用下文默认EOF测试，目录换为`/tmp/connect-e2e/connection-cleanup-recovery-final`；
构建58.6秒／安装1749ms，实测APK
`/tmp/connect-artifacts/connection-cleanup-recovery-final-debug.apk`，SHA256
`2c99f6ecacdbfd15400f976ed888a5770e15b124494ed8a6884bbb23ae523ee9`。
核对native库完整嵌入原生产捕获JAR、有限重复候选缺席，没有重建JAR。

关闭时机修正前的中间E2E也通过（1476ms恢复，ed6dbb35…），原件保留在
`connection-cleanup-recovery`。收尾发现当时有两个helper JAR残留，逐一核验后手工
删除；不能把该次driver通过当成辅助媒体正常退出与文件清理通过。最终源码只
剩一份mtime早于故障6.011秒的helper JAR，无活进程，核验摘要后手工精确清除；
恢复后的正常断开没有留下第二份。异常断网后的JAR自动回收仍需任务06补齐，
不能把fixture卸载或无进程当作已无远端文件。

普通main最终构建8.6秒／安装636ms，APK26c5a915…完整含原生产JAR；MCP热重载
成功、无Dart错误、设备首页及最终恢复画面已目视。启动Skipped32frames、
SurfaceSync1000ms和1436ms帧告警保留。DTD／CLI断开、Gradle停止，五个精确
forward清除、自有两AVD核名关闭且PID消失。远端本轮产物最终缺席（包含上述手工
补清），11项debug重复副本1463.3MiB清除、空闲33.69GiB，保留实测APK、证据、
release及有效缓存。回执前缀`/tmp/connect-connection-cleanup-`见当前完成度。

这是可控EOF兼容和真实新像素证据，不是物理Wi-Fi漫游或小时级长稳证明。停止时
EGL_BAD_SURFACE、BufferQueue abandoned及MediaCodec状态日志仍保留，不以该次
通过关闭既有MDK snapshot原生崩溃。首帧、高动态低延迟等继续沿[性能任务](video-performance.md)
推进；本批没有改变质量或解码默认值，也没有声称端到端延迟改善。

2026-10-18，代码`8c55b84`。TCP仍确认数据而adbd不再处理ADB消息时，原监控只查
`Client::is_closed()`，连接不会关闭，既有自动重连也无法开始。真实TCP/TLS夹具保留
首个socket并持续消费TLS字节、停止回复ADB，40秒恢复门槛实际失败；整项44.84秒。
这与此前丢TCP ACK的内核黑洞不同，不改已有keepalive或TCP_USER_TIMEOUT策略。

## 当前行为

Core的私有`ConnectionHealth`由现有连接监控拥有，每两秒核对实际Client身份和
入站活动。约10秒没有入站读取进展，才异步OPEN标准`sync:`服务并立即关闭，不发
sync命令、不读写文件、不启动shell／进程／JAR。每个实际连接最多一个探针，单次
3秒；连续两次超时且各次均没有任何入站进展，才关闭精确Client，交既有offline与
自动重连处理。第一次超时后可在下一监控tick重试，不再等一个完整空闲周期。
这些值是探测策略，不是任意设备／调度条件下的绝对恢复时限。

OKAY接受、CLSE拒绝或其它服务的入站流量都证明有响应；本机stream上限等错误不算
失活。繁忙视频和文件流会更新活动并取消探针，避免把某个服务慢当整台手机失联。
库本身不新增自动探针，仅提供`inbound_activity()`不透明快照，Core承担产品策略。

活动按每个非空header／payload读取批次递增，不按完整帧计数、不逐字节做原子操作，
不读时钟、不进入Dart、不额外复制payload。它包含未完成帧的进展，不代表协议校验
成功；magic、length、checksum等验证独立保留。持续部分数据不在这里判成失活，
服务请求和已有视频半包／消费者期限仍各自负责，不能用健康检查替代它们。

探针不持Runtime，任务只回报结果，不查设备ID再关连接。应用结果前，在connections
锁下核对Client身份；移除／替换会取消旧probe，迟到结果不会影响新连接。manager
Drop取消并abort任务，pending OPEN沿原AdbStream Drop移除route并发送CLSE。
显式Client close立即唤醒等待；map变更及Runtime释放由下一监控tick清理，通常两秒
内，原监控被其它操作延迟时不承诺严格两秒。用户主动断开仍关闭自动重连。

## 先红后绿与复核

首版完整帧计数经独立review发现会误断合法慢帧：1MiB WRTE以32KiB/s接收需要32秒，
OPEN响应也只能排在当前帧后面，约18–22秒便可能被健康检查关闭。真实duplex合法
分段WRTE回归在首版0.36秒的加速时序中实际失败；改为读取批次进展后通过，另加
每次2字节的慢header回归。完整payload和最终OKAY均验证，未仅检查字段变化。
`/tmp/connect-slow-frame-health-{red,green}.log`保留原始失败及修复证据。

模块8项wire行为测试覆盖两次无响应、正常接受／拒绝、活跃流量取消probe及抑制
新探针、旧第二次超时不能关闭替换Client、移除／Drop的真实CLSE、128条stream本机
资源耗尽、慢header和慢1MiB payload。既有read_trace2项及协议验证通过；只读复核
确认读取循环保留EOF、短读、错误传播及trace时钟边界，原误断问题闭合。

公开Runtime的3项真实TLS测试在宿主36.35秒、Android API36 x64普通shell30.97秒
通过：应用失活后offline→同ID新TLS连接、健康拒绝保持连接、阻塞probe期间主动
替换后新连接仍存活；包含显式disconnect的真实EOF及无后续accept检查。
不需要SO_ATTACH_FILTER、root或目标测试APK。这是协议端夹具，不是实际adbd挂起、
真实Wi-Fi切网、视频活动恢复或小时级长稳证明。

```sh
cargo test -p interop-core --lib connection_health -- --nocapture
cargo test -p interop-core --test application_liveness -- --nocapture
cargo test -p interop-adb --test read_trace -- --nocapture
```

红结果`/tmp/connect-application-health-red.log`，最终宿主及Android结果
`/tmp/connect-application-health-final-{host,android}.log`。Android从本次Cargo JSON
`compiler-artifact.executable`取路径，NDK28.2的`x86_64-linux-android26-clang`链接，
推到专用AVD的`/data/local/tmp/connect-application-health-test`，普通shell以
`env TMPDIR=/data/local/tmp RUST_MIN_STACK=8388608 <binary> --nocapture --test-threads=3`
运行后已删除。无需更改系统过滤器或关闭SELinux。

完整ADB72 passed／13 ignored、Core169 passed／49 ignored，12／38 suites；忽略项
不当设备通过。两包all-target clippy -D warnings、fmt及Core iOS／macOS／Windows
MSVC交叉check通过，非三宿主Flutter链接或运行。日志前缀
`/tmp/connect-application-health-{adb-regression,core-regression,clippy,check-*}`。

最终普通main构建74.5秒／安装1514ms，热重载133ms成功，无Dart错误。实际表单
连接专用AVD、全屏Settings、远端触控进入Network页、悬浮退出和移除本轮设备记录
均已操作与目视。普通页有伴随活动，不能把它称作纯空闲探针测试；上面的TLS用例
另已关闭伴随轮询。代表图`/tmp/connect-health-{remote-settings,remote-after-input,
target-after-input,main-final}.png`。启动SurfaceSync与HWUI长帧告警保留，不记流畅度
或严格首帧达标。平台播放持续延迟仍沿[视频性能任务](video-performance.md)继续。

两个scrcpy JAR摘要未变，未重建；两个诊断会话及普通会话无捕获JAR／进程残留，
fixture／自带LLDB与Android测试程序已移除。停止Gradle、正常关闭两AVD，清理408.9MiB
LLDB模块缓存，另按精确清单删除472项debug输出／26个非视频测试程序及incremental，
11871.9MiB，空闲52.35GiB。保留release、有效Flutter／Rust依赖、视频／health测试、
Gradle／CMake／SDK缓存及/tmp原始证据。清理清单
`/tmp/connect-{decoder-tool-cleanup,health-target-final-cleanup,application-health-cleanup}.json`。


## 实际adbd与可见视频的应用停转故障（2026-10-18）

`test_driver/video_recovery.dart` 新增 `CONNECT_E2E_RECOVERY_FAULT=blackhole`，默认
EOF模式保留。测试proxy提取到support：只对故障注入时的唯一旧连接保持读取并
丢弃双向数据，不主动destroy或注入EOF，不保存ADB内容；新连接正常转发。
每次转发flush保留背压，注入唤醒旧flush等待后继续排空，最多遗留已排队的那个chunk。
这是应用层停转，不是内核丢TCP ACK、真实无线漫游、adbd内部挂起或所有半开场景。

真实TCP自测四场景通过（独立Dart，不启动Flutter/native hooks）：双向字节丢弃且
旧两端保持打开、新连接正常；controller先EOF后再建立新连接；默认EOF仍关闭旧
pair；两秒内关闭黑洞与释放监听端口。另验证cleanup生成的EOF不能满足验收。
`/tmp/connect-blackhole-proxy-root.log`。复现：

```sh
rtk proxy /home/xiankq/flutter/bin/dart \
 test_driver/support/adb_fault_proxy_tcp_test.dart
```

Driver在清理前保存故障回执并要求两个方向实际drop均大于0，注入关闭计数0，两个
读取方向仍活动；旧连接必须由controller方向首先EOF结束，当时尚未accept新连接，
再要求新连接真正连到上游。cleanup不能补足这些证据。原正式RemotePage测试保留
30秒恢复期限、真实新session／首像素、Flutter计数0→1、主动停止后不重建等断言。

首轮实际adbd试验在19440ms恢复新会话并完成像素0→1，但静态源没有新视频输出，
只有controller108字节被丢弃，upstream0；严格driver正确拒绝，整体exit1保留。
原件 `/tmp/connect-e2e/video-application-stall/`。此后仅在黑洞注入后通过独立实验ADB
改变本轮独占fixture计数，等待实际视频字节进入旧连接的discard，再重发同fixture
Intent还原计数0；不靠降低双向drop要求来取得通过。该动作仅属于测试夹具，产品
不会安装fixture或依赖外部分发adb。带挑战的首次复验32秒完整exit0：19850ms恢复新session、实际Flutter图案0→1；
旧连接controller108／upstream6724字节实际丢弃，注入关闭操作0，controller先EOF，
当时accept仍1，其后socket2连接真实adbd，errors为空。实际入站drop等待52ms。
主动停止后没有再捕获，fixture卸载／缺席、设置恢复、代理退出均确认。
`/tmp/connect-e2e/video-application-stall-frames/`，日志
`/tmp/connect-blackhole-recovery-frames.log`。该recoveryMs从host故障ack后开始，
故障注入／夹具挑战时刻另存proxy-events，不能把两个起点混用。最后补fixture挑战
完成门禁后正复跑最终代码与默认EOF模式；尚非物理Wi-Fi或长期稳定性通过。


最终源码再次完整通过：19082ms出现新session及真实图案0→1，drop108／6659字节，
实际入站drop等待53ms；挑战完成、EOF方向、关闭计数与accept次序均满足，fault
errors为空，所有清理true。故障注入至旧controllerEOF17768ms、至新adbd连接
17784ms另存，不混用host ack后的首像素计时。默认EOF对照14秒完整通过，恢复
1603ms，同样保留新会话／新像素及清理；说明提取proxy后原断线能力仍可用。
原件 `/tmp/connect-e2e/video-application-stall-{verified,eof-control}/`，日志
`/tmp/connect-blackhole-{recovery-verified,eof-control}.log`。

```sh
# 在仓库根目录，先按video-performance.md准备双AVD/fixture和25556转发。
rtk proxy env CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
 CONNECT_E2E_DEVICE=emulator-5554 CONNECT_E2E_TARGET=emulator-5556 \
 CONNECT_E2E_VIDEO_FIXTURE=/tmp/connect-video-fixture/video-fixture.apk \
 CONNECT_E2E_RECOVERY_FAULT=blackhole \
 CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/video-application-stall-new \
 FVP_DEPS_SHA256=70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012 \
 /home/xiankq/flutter/bin/flutter drive -d emulator-5554 \
 --driver=test_driver/video_recovery.dart --target=integration_test/video_recovery_test.dart
```

去掉FAULT环境变量并换新证据目录即默认EOF控制。本轮三个driver文件Dart分析无问题，
真实TCP四场景完整通过。没有生产代码或JAR变化，不重打同一release；既有完整目标、
高动态预算、物理无线漫游／应用任务恢复／小时级长稳和MDK内部截图崩溃仍开放。


代码提交 `3771d44`。只读review未发现新增可证缺陷。普通main最终构建7.5秒、安装
540ms、MCP热重载130ms成功，无Dart错误，空设备首页和实际恢复VIDEO1均目视。
Skipped31frames／SurfaceSync1000ms／1404ms启动帧告警仍保留，不计启动流畅通过。
本批capture／encoder临时JAR和被控捕获进程扫描为空，fixture缺席；核对名称后关闭
两AVD、移除forward、停止Gradle。精确清理394项debug输出1486.0MiB，空闲42.0GiB，
保留release／有效缓存／原始证据和五项原有未跟踪文件。回执为
`/tmp/connect-application-stall-{target-cleanup,avd-stop,debug-cleanup}.json`。


## 单个控制流失活，设备连接仍健康（2026-10-18）

活动视频或文件查询会持续保活Client，因此连接健康探针不能发现某条控制WRTE
永远不回OKAY。旧实现先等待64项控制队列，再开始6秒reply期限；actor实际write
没有短期限，超时旧输入在ACK终于恢复后仍可能被送出。真实Frame/Duplex回归在
旧实现中确认队列满超过6.5秒、调用超时后actor不退出。

ControlReply现在携带一个绝对6秒期限，覆盖入队、实际写入及调用等回执；出队拒绝
已过期或调用者已撤销的请求。实际write在会话取消或此期限到达时结束，关闭精确
控制route并取消本会话，保留共享Client和其他设备活动。中止后的晚到OKAY不能复活
route，输入不会重放。应用启动继续遵守LaunchPermit单次提交和unknown账本；恢复
主屏后，打开应用需要新的明确操作，不重放旧排队意图。

该期限不是“任何协议无回复都断远控”。Set/Capture的协议ACK按sequence关联，调用
超时只返回错误；旧sequence不能满足新请求，actor不因等待应用层回复关闭健康视频。
原因之一是[官方GET_CLIPBOARD](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/control/Controller.java)
在无可读文本时可以合法不回消息，且没有request ID；取消后删除旧FIFO槽会把旧文本
分配给新读取。故clipboard.get统一复用现有companion的带编号RPC，返回明确的
hasText／权限状态；不引入新的服务端源码，不重建scrcpy或companion JAR。

读取仍尊重allowStart：Bridge完成状态核验后默认false，不因后台刷新新建helper；
剪贴板页的主动获取显式true。无helper时自动同步可能limited，主动获取后可使用
现有helper；自动协调器仍需后续内容事件、前后台切换或重新开关才能再次核验，
不能把这个产品行为说成自动恢复已完整。通知／通话观察不因剪贴板读取被开启。

真实Android选择性故障只丢控制OKAY，其他frame继续转发；这与旧hold_key代理
阻塞整个toward_host循环不同。最终验证：Core lib80 passed/6 ignored、5项control真实Frame定向、严格all-target
clippy及改动Rust格式通过。Android4项应用打开与未知结果59.29秒、2项无会话
剪贴板与断线11.39秒均通过；新增控制故障最终11.85秒通过，实际1个key、三次
files.list均在控制route关闭前成功，视频17378→70158字节，CLSE后共享Client
仍可用。主动helper启动／false门禁／两次跨通道剪贴板新文本及通知通话观察停止
也实测通过。初次新增测试未关闭默认观察，helper提前启动使false门禁断言失败；
保留该红日志，补observation.stop后单独复跑最终新增测试通过，不隐藏失败。

```sh
rtk proxy cargo test -p interop-core --lib
rtk proxy cargo test -p interop-core control_ --lib -- --nocapture
rtk proxy cargo clippy -p interop-core --all-targets -- -D warnings
rtk proxy env INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=25556 \
 INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:25556 cargo test -p interop-core \
 --test app_launch_android --test companion_clipboard --test control_stall_android \
 -- --ignored --nocapture --test-threads=1
```

最终host日志`/tmp/connect-control-deadline-verified-lib.log`与
`/tmp/connect-control-deadline-clippy.log`；Android前六项及夹具红在
`/tmp/connect-control-deadline-verified-android.log`，修正夹具后的最终第七项在
`/tmp/connect-control-deadline-verified-stall-android.log`。这些是API36 AVD与真实
adbd/生产Runtime协议证据，不替代物理Wi-Fi/ARM/小时级稳定性或视频延迟预算。


最终普通main构建69.9秒，APK`/tmp/connect-artifacts/control-deadline-main-debug.apk`，
SHA256 `89527f9ad91e5a9c536f7067039f13ca76b8c123b1ce0580e29c0b00296b5eb2`。
原生产捕获JAR完整在库中，隔离候选缺席，vendor／capture／companion三个JAR摘要
未变、未重建。MCP实际热重载成功、无Dart错误；从手动TCP表单进入全屏Settings，
主控触摸进入Network & internet、悬浮退出并移除测试设备，主控画面和目标
Settings.SubSettings顶层任务均观察到。代表图前缀
`/tmp/connect-control-deadline-main-{remote-ready,after-input,final}.png`；最初过渡图
保留但不当ready证据，目标uiautomator的null root不算成功层级断言。
Skipped34frames／SurfaceSync1000ms／1297ms长帧警告不计性能通过。

清理发现74份不同于当前摘要的历史辅助JAR；自有target核实无进程后逐一精确清除，
为完成旧文件清理另一次启动后也已关闭。捕获进程、JAR、fixture及forward均缺席；
DTD断开、CLI detach、Gradle停止，两自有AVD及清理专用target PID全部消失。
22项大debug副本2680.3MiB删除，空闲37.91GiB，保留实测APK/raw、release与有效缓存。
回执`/tmp/connect-control-deadline-{target-cleanup,avd-stop,debug-cleanup}.json`。
本批不声称改善冷首帧或高负载画面延迟；普通Driver提前挂载A/B/A见
[视频性能](video-performance.md#普通driver提前挂载纹理的单变量复验2026-10-18)。

控制修复及真实Android回归提交`1356a0c`；基准默认解码优先级修正`1421374`。
