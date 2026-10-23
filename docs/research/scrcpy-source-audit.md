# 原生媒体与 scrcpy 的机制差异

2026-10-23，比较 scrcpy 5.0.1（`a60891aea193d92e7e5c3942700eca63f9d19a5f`）与本项目原生媒体迁移工作区。逐项缺陷与整改合并在[公共核心](../implementation/scrcpy-audit-fixes.md)、[桌面](../implementation/scrcpy-audit-desktop-fixes.md)、[移动与 Apple](../implementation/scrcpy-audit-mobile-apple-fixes.md)和[传输控制](../implementation/scrcpy-audit-transport-fixes.md)记录；本文只保留仍影响设计判断的上游依据。

## 数据与所有权

- scrcpy 直接把协议包读入 AVPacket，配置包合并仍会复制；AVPacket/AVFrame 引用计数不等于像素复制。本项目 source ABI v2 的包所有权交接解决入口复制，但不证明后续 GPU 导入和 Flutter 合成无复制。[demuxer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/demuxer.c)、[packet_merger.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/packet_merger.c)
- 上游复用解码帧和最新待显示帧；默认 `video_buffer=0`，可选 regulator 才按 PTS 平滑。最新帧覆盖适用于已解码帧，不能任意删除仍被后续压缩帧引用的包。[decoder.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c)、[frame_buffer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c)、[video_regulator.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/video_regulator.c)
- 解码完成、平台纹理导入、Flutter 消费和物理显示是不同阶段。Flutter 桌面纹理要求 RGB，SDL 可直接消费部分 YUV 格式；额外转色应按实际格式和 GPU 路径计量，不能归因于 Rust 或 Flutter 名称。

## 解码与恢复

上游包含 H.264 硬解 profile mismatch 兼容和 AV1 新编码 session 重开处理；硬解初始化失败、坏包、EAGAIN、Surface 变化是不同恢复条件。GOP 保留可帮助重开，却带来独立内存与重播成本。[hwdec.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c)、[decoder.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c)

源码存在硬解候选不表示实际选中硬件。颜色矩阵、范围与帧属性必须跨硬件回读和软件回退保留；平台设备选取与 GPU 互操作需一起核验。具体未关闭的跨设备同步、驱动、热插拔及轮询成本以相应整改记录为准。

## 音频与控制

scrcpy 默认 Opus，音频 regulator 依据播放水位补偿采样漂移；视频默认尽快呈现，不是严格 audio-master 播放器。本项目 PCM 的有效负载为 `48000×2×2=192000 B/s`，约1.536Mbps。省编码不等于端到端更低延迟；队列容量也不能相加当作实测延迟。[options.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/options.c)、[audio_regulator.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/audio_regulator.c)

上游 controller 以独立发送线程接纳输入，receiver 独立接收；本地录取、ADB ACK 与被控注入完成是不同回执。多窗口产品还需额外核验 capture 代际及设备级声音、剪贴板、屏幕资源所有权。[controller.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/controller.c)、[receiver.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/receiver.c)

普通 Release 的 JNI/R8 故障说明 Debug 媒体通过不能代替发布构建；根因摘要见[JNI 回调保留](android-release-media-crash.md)。端到端指标和当前入口见[视频性能测量](../implementation/video-performance.md)，源码操作次数不直接推算毫秒收益。
