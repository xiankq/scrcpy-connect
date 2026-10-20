# 冷启动往返与首次原生绘制

本文保留2026-10-18冷启动实验的独有方法与结论。历史环境为双API36/x64 AVD、SwiftShader、Flutter3.47.6 debug、当时的fvp/固定MDK及协作捕获JAR；该后端已被替换，结果不继承为当前原版性能通过。全链路指标与基准入口见[视频性能](video-performance.md)。

## 冷启动编排

冷编码器枚举和正常JAR清理曾使用两个shell往返；合并为一次后仍保留原退出码及失败/取消的owned fallback。A/B/A校验中位354→269→311ms，有样本重叠，不承诺固定收益。完整首帧仍有1142/1064/1000ms，不能用局部往返减少宣称完整预算通过。

共享 `EncoderCatalog` 只按精确Client复用成功结果，不按设备ID或地址复用。`peek`不创建探测、不等待进行中的初始化，失败/取消保持unknown。有效参数仍是默认主屏/H264/无named encoder，且目录未知时，可直接尝试实际捕获；已知不支持仍拒绝。其他codec、named encoder、独立应用和显式质量选项继续真实枚举。

休眠检查、资源/应用账本、服务端wire/尺寸/关键帧和本机像素核验均保留。未知能力不改为available，独立应用未知启动不能借重试重放。

## 真实对照与失败

| 独立验证 | 结果与限制 |
| --- | --- |
| 协议/实际shell接缝 | 旧默认路径首先上传encoder查询JAR的断言失败；改后默认先捕获。异常退出、截断、取消、丢弃仍清理所拥有部署 |
| 同参数直启→枚举→直启 | 首帧1102/927/782→1044/1041/1070→896/935/941ms；首组1102ms失败保留，不挑最快样本 |
| 旧正式default静态复跑 | 无trace、60输入，首帧903/877/875ms、输入P50/P95147/225ms；仅为旧依赖、双AVD/debug样本 |
| 正式RemotePage五编码 | 实际像素、Texture、截图、退出及清理功能通过；非五编码性能或物理ARM证据 |

真实app-launch/unknown设备用例另外核对排队关闭、主屏回执丢失及独立应用关键帧前后不重放。早期像素超时和切换构建模式后测试插件未注册均未算通过；插件问题按[打包契约](android-packaging.md#测试插件注册)处理，没有移除像素断言。

## 首次输出的原生CPU观测

在同一Perfetto系统时钟中，按PID、traceToken/PTS关联onVideo与对应 `JNISurfaceTexture` renderer线程。CPU窗口从对应onVideo到之后第一笔eglSwapBuffers开始；邻帧对照改从对应`MediaCodec::renderOutputBufferAndRelease#native`开始。对`thread_state`的Running区间与窗口取交集求和，不累加嵌套slice，也不是取线程生命期第一笔swap；simpleperf的MONOTONIC时间先经`clock_snapshot`映射到Perfetto BOOTTIME。三个renderer首个输出窗口CPU约131–135ms，紧邻后续输出约1–3ms；runnable和sleep另算。部分窗口在onVideo后约0.3/0.7ms已acquireBuffer，随后仍有CPU成本，不支持全部归因于等待Texture挂载或下一解码帧。

调用栈采样在首窗27样本中观察到GL程序链接状态/整数查询及QemuPipe同步读写。部分MDK符号只有地址，样本不足以分配各GL调用百分比，也不能把模拟器代理调用称为宿主shader编译或真机瓶颈。该证据缩小了排查范围，未交付对应原生播放优化。

## 复现与当前边界

当前源码接缝在 `crates/interop_core/src/encoder_catalog.rs`、`scrcpy.rs` 及其 `cold_*`/catalog测试；运行 `cargo test -p interop-core --lib cold_` 和 `cargo test -p interop-core --lib encoder_catalog`。它们是主机行为回归，设备首像素按[普通Driver基准](video-performance.md#普通调度基准与解码路径对照)另测。系统trace采集及分析见[异步解码](android-decoder-async.md#可复现的边界观测)。

服务端输入未变的主控编排调整不需要重建JAR；来源校验与APK组装分别执行。历史ARM64 release构建/签名通过不证明ARM运行，旧JAR哈希不作为现行输入。高动态、原生snapshot限制、真实无线与当前原版复验仍见[性能边界](video-performance.md#未完成边界)。
