# bounded-input 隔离候选

此目录是被控手机上 scrcpy Java 捕获服务的实验补丁。它改变被控端真实的
SurfaceTexture／GL／MediaCodec 输入路径；没有增加主控 Android 媒体实现。
候选尚不能据此宣称性能改善或替换生产 JAR。

`candidate.patch` 以 scrcpy 5.0.1 **已应用**
`../../patches/0001-cooperative-capture-pause.patch` 后的受控源码为基线，使用
`patch --fuzz=0 -p1` 应用。补丁只包含 Java 源码，不包含编译产物。原生产两份
JAR／摘要不覆盖；构建工具应使用独立候选输出目录并记录两份补丁的摘要。

仅接受 API36、主屏、无 crop／orientation／angle GL filter、H264、实际编码器
`c2.android.avc.encoder`。默认选择编码器后也核对实际名字；每次重建再次核对。
不支持的组合明确退出，不静默退回直接 Surface 输入、扩大输入窗口、降画质或
隐式重试。候选请求的码率、videoSize 和最大帧率保持原请求值。

## 输入与生命周期

- `SurfaceCapture.createEncoderInputFlow()` 默认返回 `EncoderInputFlow.NONE`。
  `ScreenCapture` 候选创建独立 `BoundedInputFlow`；无 filter 时插入 identity
  `OpenGLRunner`，源纹理和输出都使用现有 `videoSize`。
- 保持 `capture.start()` 先于 `codec.start()`；只有 `codec.start()` 成功才激活
  输入流。激活前仍可取得最新源纹理，但不执行编码 Surface swap。
- `LatestInputWindow` 无 Android 依赖，ledger／pending／credit／调度均由单一
  GL handler 操作。每次 frameAvailable 都 updateTexImage，最新源可覆盖 pending；
  缺少 credit 时不等待。最多两条实际输入 reservation，swap 前登记精确 PTS。
- 新源按原 SurfaceTexture timestamp 建立媒体 PTS；重复帧和 PTS 碰撞使用严格
  单调的新编码 PTS。每项 reservation 同时保存原始 `sourceTimestampNs`、实际
  `presentationTimeUs`、`repeat` 和提交时刻。重复绘制不会刷新源 timestamp。
- 原 `repeat-previous-frame-after` 与 `max-fps-to-encoder` 在自定义 codecOptions
  全部应用后读取并移除，避免 GBS 自行重复／丢弃已登记的输入。GL 模块按照读取
  的间隔执行重复和限帧：SurfaceEncoder 未覆盖时重复为 100000µs，当前 Core
  传入的 33334µs 会覆盖它。0 关闭重复；非法负数／非有限帧率明确拒绝。
- 静态首帧尚无输出时，重复期限到达可以使用第二个 credit。只要有在途输入，
  最老 reservation 3 秒未完成即失败；GL timer 和 encode 的 100ms 轮询快照均
  可检查。空 ledger 的正常静止不会失败，不增加窗口来绕开 codec 不输出。
- 只有完整 packet 写入 Streamer 且 releaseOutputBuffer 成功才按精确媒体 PTS
  归还一项 credit。CONFIG／空 EOS 不归还，媒体数据附带 EOS 可以归还精确一项；
  duplicate／unknown PTS 撤销整代并报错，partial 在写 packet 前拒绝。不会用最大
  输出 PTS 释放所有更早项。output credit 主动安排 drain，终值不依赖后续源事件。
- close 立即撤销跨线程 output／pre-swap guard，再在所属 GL handler 上取消 timer
  并清空整代状态。SurfaceEncoder 的 finally 首先 close flow，再执行原 capture、
  codec、Surface 清理；原暂停 ACK 仍在清理后的 gate。旧 output／timer 不触及新代。
  GL 异常保存给 encode 退出，handler 不因候选绘制异常死亡；GL 清理无论异常与否
  都释放同步等待，清理完成前不会因 interrupt 提前报告完成。

## 离线验证

`LatestInputWindowTest.java` 是独立纯 Java 行为测试，编译时只需要补丁中的
`LatestInputWindow.java`。它覆盖六组场景：两项占满后只保留最新 pending 和无新事件
终帧、激活窗口与限帧、静态重复与有界 stall、CONFIG／EOS／精确乱序输出／重复／
未知／partial、早于 swap 返回的同步 output 和 swap 失败、close 穿越 reservation
以及旧 timer／output 的代际隔离。测试使用可控时钟和单任务 scheduler，断言真实
提交帧／PTS／pending 行为，没有复制模块的状态转移算法。

现有 `CapturePauseTest` 继续使用 `encode(MediaCodec, Streamer)` 原反射签名。
其 JVM MediaCodec stand-in 需包含真实 BufferInfo 的 `presentationTimeUs` 字段。
候选编译和测试由仓库构建／测试入口在独立目录统一运行；本目录不提供第二套构建器。

## 设备验收边界

纯 Java 测试不能证明实际 codec PTS、GL 开销、槽位驻留或用户可见性能。真实编码
接缝应另测 packet 完整写入、releaseOutputBuffer 失败、100ms failure poll 和暂停
退出。设备先验证静态冷启、动态→唯一终值→完全静止、暂停恢复、旋转和 stop 清理，
再以相同 1280／60／8Mbps 普通 Driver 路径运行 A/B/A、实际窗口和 slot trace。
必须确认候选 JAR／SHA 真正嵌入隔离主控 APK 的正式路径；单独 push JAR 不算证明。
ARM 硬编、热／功耗和无线吞吐需另验，本候选会明确拒绝这些未限定 codec。

3 秒 stall 能让 encode 发现停止推进的输入；无法在 Java 层抢占永久卡死的驱动 EGL
调用。底层 swap 卡死时仍需等待原生清理，不能提前 ACK 假称资源已释放。此边界不能
用扩大窗口或隐式回退掩盖。
