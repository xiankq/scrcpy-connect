# scrcpy 服务端与媒体协议依据

核查基线：scrcpy 5.0.1，提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。本项目来源与产物摘要由[vendor](../../servers/vendor/README.md)维护；当前媒体路径见[ADR 0007](../adr/0007-capability-packages-and-native-media.md)。

## 服务、窗口与恢复

| 已核实事实 | 对本项目的含义 | 固定来源 |
| --- | --- | --- |
| server 可通过 shell `app_process` 临时运行，控制消息是固定枚举 | 独立 companion 可扩展 RPC；未知 option 或额外 JAR 不会自动扩展原捕获协议 | [develop.md](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/develop.md)、[ControlMessageReader](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/ControlMessageReader.java) |
| SCID 区分 socket；虚拟显示仍使用真实 Android 任务 | SCID 不隔离剪贴板、电源、声音，也不赋予应用多实例能力 | [DesktopConnection](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/device/DesktopConnection.java)、[虚拟显示](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/virtual-display.md) |
| 捕获支持 H.264/H.265/AV1/VP8/VP9，编码器有尺寸与资源约束 | 选择被控编码与主控解码能力交集；枚举成功不保证 configure 或持续运行 | [VideoCodec](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/VideoCodec.java)、[SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java) |
| 静态画面可无新帧；`RESET_VIDEO` 重启捕获编码，不是单独 IDR 请求 | 无新像素不直接判断连；恢复可能产生中断和新配置 | [SurfaceEncoder](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java)、[CaptureControl](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/video/CaptureControl.java) |
| 编码输出同步写流后才释放 buffer | 慢消费者能反压编码端；最新帧覆盖只可直接用于解码后帧 | [IO](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/util/IO.java)、[frame_buffer.c](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c) |

部署、EOF 监督、PID 身份和 JAR 清理是本项目自己的资源协议，不能由 scrcpy 进程启动成功推导；现行边界见[被控兼容](../implementation/android-target-compatibility.md#服务端与资源回收)。

## 声音的边界

- 音频捕获要求被控 Android11+；Android11另有启动解锁条件。默认 Opus，亦支持 AAC/FLAC/PCM；默认音频缓冲与视频尽快呈现是不同策略。[音频文档](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/doc/audio.md)
- 设备 output、playback 与 mic 是被控端来源。官方 socket 是 server→client，没有主控音频回传控制消息；`audio-source=mic` 不表示主控麦克风注入。[Server](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/Server.java)、[ControlMessage](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/control/ControlMessage.java)
- 多个虚拟显示不自动生成独立应用音轨。设备播放、受保护内容和通话捕获受来源模式、版本及系统策略限制。[AudioPlaybackCapture](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioPlaybackCapture.java)
- 设备 PTS 与主控单调时钟不同源；两个播放器都低缓冲也不保证声画同步。[AudioRecordReader](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/server/src/main/java/com/genymobile/scrcpy/audio/AudioRecordReader.java)

协议字段和应用状态分别由[协议源](../../protocol/README.md)与[架构](../implementation/architecture.md)维护；本报告不再保留已替换的 fvp/MDK 接入方案及录制路线。
