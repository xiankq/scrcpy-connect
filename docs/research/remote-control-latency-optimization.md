# 远控延迟：参考实现与队列放大

2026-10-21。参考 scrcpy 5.0.1 `a60891aea193d92e7e5c3942700eca63f9d19a5f`、scrcpy-mobile `cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09`、EasyControlNext v1.1.2 `aeda9901ebf53350491f5454a41269e791918662`。旧播放器诊断和已完成改造步骤不再维护；现行输入与恢复边界见[连接健康](../implementation/connection-health.md)。

## 有效结论

逐事件等待 ADB ACK 会把 RTT 变成本地处理速率上限：RTT=30ms 时约33个事件/秒，RTT=100ms 时约10个。60/120Hz 的 move 若依次等待，就会持续累积并在网络恢复后回放旧轨迹。这解释了“稍有网络延迟就追不上手势”的一种机制，不表示每个慢场景都属于它。

独立发送、有限录取、合并未发送 move 和完整消息批写可消除这种放大；down/up/cancel 必须保序。控制优先只能调度仍在用户态的帧，不能越过已经进入 TCP 的视频字节。burst 改变逐流信用与 ACK 时序，需要双方协商，不能替代全链路拥塞控制。

压缩参考链与显示队列分别处理：已解码 pending frame 可覆盖为最新帧；压缩队列丢弃必须保留可解码参考链，或恢复到新关键帧/编码段。主控停止读取会向 socket、ADB 和目标编码器传播背压；将播放器缓冲设零不能清除上游已有帧龄。

## 一手实现对照

| 对象 | 源码机制 | 适用边界 |
| --- | --- | --- |
| scrcpy | 60项有界 controller 队列、独立发送/接收；默认 `video_buffer=0`，最新已解码帧覆盖 | 仍共享 ADB 与 USB/TCP 带宽，没有通用 ABR |
| scrcpy-mobile | 复用 scrcpy 核心，iOS VideoToolbox→AVSampleBufferDisplayLayer，设置 DisplayImmediately | 显示层忙时丢当前帧；持续停顿才 flush/reset，不是新媒体拥塞协议 |
| EasyControlNext | 优先独立控制/视频 TCP；MediaCodec→Surface；HandlerThread 异步发送触摸 | 可靠有序 TCP 仍可积压；固定快照没有 ABR、FEC 或帧龄闭环 |

scrcpy 依据：[controller.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c)、[frame_buffer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c)、[SurfaceEncoder.java](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)。编码器 priority、latency 和重复帧参数是请求，不是最终帧延迟保证。

scrcpy-mobile 依据：[decoder-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/decoder-porting.c)、[texture-porting.c](https://github.com/wsvn53/scrcpy-mobile/blob/cdbc6ac7d9d2eca1d1cada5281a8f46d800d5b09/porting/src/texture-porting.c)。该快照是 iOS 主控，不是 Android/Flutter 性能基准。

EasyControlNext 依据：[ClientStream.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/tools/ClientStream.java)、[VideoDecode.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/decode/VideoDecode.java)、[ClientController.java](https://github.com/shiyunjin/EasyControlNext/blob/aeda9901ebf53350491f5454a41269e791918662/easycontrolnext/app/src/main/java/com/shiyunjin/easycontrolnext/app/client/tools/ClientController.java)。

## 测量判据

用同一输入身份关联派发、注入、目标绘制、编码、接收、解码和呈现；PTS 不直接跨设备相减。分别改变 RTT、带宽、丢包或后端，观察输入尾延迟与帧龄，而非只看平均解码耗时。当前测量入口见[视频性能](../implementation/video-performance.md)；官方35–70ms的来源条件见[移动端延迟一手来源](scrcpy-mobile-latency-primary-sources.md)。
