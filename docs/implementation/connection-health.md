# ADB 应用失活检测与恢复

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
