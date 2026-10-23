# scrcpy 35–70ms 数字的来源

2026-10-21，核查scrcpy 5.0.1固定提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。其[README](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/README.md)的35–70ms链接到[PR #646](https://github.com/Genymobile/scrcpy/pull/646)，不是移动主控或触控往返指标。

PR在Android设备播放30fps计数视频，在桌面窗口观察对应数字。直接按设备提供的包边界解码后，作者报告：

| 尺寸 | 修改前 | 修改后 | 收包到渲染平均值 |
| --- | --- | --- | --- |
| 1080×1920 | 约3帧/100ms | 约2帧/67ms | 12ms |
| 448×800 | 约2帧/67ms | 约1帧/33ms | 8ms |

渲染测量使用关闭跳帧的 `--render-expired-frames`。公开记录没有样本分布、设备/网络完整配置或v5.0.1复验；PR的2026年编辑也明确这些测量很旧。它证明当时减少了一帧边界等待，不能保证当前手机、Flutter、Wi-Fi或输入往返低于70ms。

官方v5.0.1主控是Linux/Windows/macOS程序，Android是被控端。[开发文档](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md)说明client使用SDL/FFmpeg，server负责采集编码与输入注入。第三方scrcpy-mobile的移动宿主机制另见[参考实现对照](remote-control-latency-optimization.md)，不能反向变成官方Android客户端指标。

默认无额外视频buffer只排除该层主动等待；编码、网络、解码和合成仍耗时。100ms静态重复帧请求也不是首帧上限。[视频选项](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/video.md)、[SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)

本项目使用同事件/PTS与明确起止点测量，分别报告可读像素、Flutter合成和物理扫描；指标、时钟与复现入口由[视频性能](../implementation/video-performance.md)维护，不从上述历史数字推导产品SLO。
