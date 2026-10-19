# Android 模拟器 HEVC 编码尺寸降级

研究日期：2026-10-17。范围：被控设备 `emulator-5556`（Android 16、`sdk_gphone64_x86_64`），原生五格式验收截图与独立 Rust 控制会话。固定源码：scrcpy `v5.0.1`、AOSP `android-16.0.0_r1`。本次没有安装或操作主控设备，没有改变被控设备 UI、设置或用户文件；只部署并清理自己会话的临时官方 server JAR、捕获公开屏幕码流。项目仅新增本文档。

## 结论

本次 H265 模糊来自被控设备编码端的实际尺寸降级：请求 `maxSize=1280`、`maxFps=60`、`videoBitRate=8000000`，默认 `c2.android.hevc.encoder` 配置失败，scrcpy 应用该编码器声明的尺寸约束后实际输出 **230×512**。同参数 H264 输出 **576×1280**。独立主机 FFmpeg 解码 H265 原始码流已经低清，无需经过主控设备的 goldfish decoder、Texture 或 Flutter 截图即可复现。

只将 H265 的请求上限改为 `1080`，实际输出达到 **486×1080**，首帧明显清晰。这是同一目标、同一 codec、同一帧率与码率下的单变量验证，不能推广为所有 Android HEVC 编码器的上限。原五格式测试证明五种格式能渲染和退出；H265 的视觉质量不能因此判为通过。

## 一手源码链

1. AOSP 软件 HEVC 编码器 XML 声明最大 `512×512`、alignment `2×2`、block-count 最大 `4096`（8×8 blocks）、码率上限 10 Mbps。它是框架查询到的声明约束。[media_codecs_sw.xml，Android 16 固定 tag](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-16.0.0_r1/media/libstagefright/data/media_codecs_sw.xml#375)
2. 同版本 `C2SoftHevcEnc` 的 picture-size 字段实现允许 width `2..1920`、height `2..1088`，步长均为 2。声明约束与实现边界并不相同；竖屏请求高度 1280 超出该实现的 height 字段边界。这里是源码与实测相符的原因解释，日志只直接证明 `IllegalArgumentException`，没有提供字段级异常信息。[C2SoftHevcEnc.cpp，Android 16 固定 tag](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-16.0.0_r1/media/codec2/components/hevc/C2SoftHevcEnc.cpp#122)
3. scrcpy 5.0.1 创建平台默认编码器，先只使用 alignment，不在首次编码前应用声明 capabilities。配置/编码抛出异常后，`prepareRetry()` 先将 capabilities 应用于 capture，之后才尝试常规 max-size fallback。因此本例直接被声明的 512 尺寸约束压低，而没有先尝试 1080。[创建编码器与首次约束](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L65)、[失败与重试](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L138)、[优先应用 capabilities](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L173)
4. scrcpy 将实际 capture 尺寸写入 session metadata；该尺寸应与请求的上限分别呈现。其重复上一帧间隔为 100 ms，代码明确用于静态屏幕的首帧显示与质量恢复；但本例首帧至数秒后的尺寸始终为 230×512，等待不能恢复丢失的空间分辨率。[实际 session metadata](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L105)、[repeat-frame 配置](https://github.com/Genymobile/scrcpy/blob/v5.0.1/server/src/main/java/com/genymobile/scrcpy/video/SurfaceEncoder.java#L282)

## 实测与可证伪检查

独立主机连接 `127.0.0.1:15556`，使用现有 Rust Runtime、随机会话标识和官方固定 JAR，取得自己的 loopback 视频端口并完成 token 认证。捕获原 scrcpy session header、codec config、媒体包，去掉每包 12-byte framing 后交给独立 FFmpeg 软件解码。未使用主控设备的 Android 解码器。

| codec | 请求 maxSize / fps / bps | 实际 session header | FFmpeg 码流尺寸 | 结果 |
| --- | --- | --- | --- | --- |
| H264 | 1280 / 60 / 8000000 | 576×1280 | 576×1280 | 清晰 |
| H265 | 1280 / 60 / 8000000 | 230×512 | 230×512 | 明显低清 |
| H265 | 1280 / 30 / 8000000 | 230×512 | 230×512 | 降 fps 未消除降级 |
| H265 | 1080 / 60 / 8000000 | 486×1080 | 486×1080 | 明显改善 |

直接启动相同官方 JAR、开启 debug 日志的独立会话得到以下事件顺序：默认编码器 `c2.android.hevc.encoder`；配置抛出 `IllegalArgumentException`；随后 `Applying video encoder constraints`；首个实际视频 session header 为 230×512。该会话的服务端控制/视频套接字关闭后正常退出并清理。

原五格式截图采用同一静态内容区域 `crop=960:1900:60:420`，对 H264 的 SSIM 为 H265 **0.925464**、AV1 **0.996102**、VP8 **0.998723**、VP9 **0.997782**。这只是稳定复现该组截图中单独 H265 异常的反馈信号，不是通用视觉验收标准。时间、浮层与非静态内容不能用于跨截图质量比较。

独立 H265 1280 请求的首帧与约 1 秒后最后一个编码画面，在各自编码尺寸下对同一会话开始前的 `screencap` 参考图进行缩放、裁除状态栏后的 SSIM 为 **0.917546 → 0.917550**；1080 请求为 **0.993669 → 0.993849**。采集窗口分别为 5 秒与 4 秒，静态屏幕实际包时间范围约 1 秒，所以这里不声称最后一帧恰好来自采集窗口末尾。该对照同时支持“首帧时机不是主要原因”和“尺寸降级导致低清”；SSIM 在不同分辨率之间不能作为绝对质量排名。

先前从原生日志归到 H265 的 576×1280 未保存完整对应关系，操作者已确认可能来自相邻 decoder。本记录撤回该尺寸作为 H265 证据；不据此推断 goldfish 进行过放大。原生设备是否另外存在解码/Texture 缺陷仍需独立证据，本次没有发现使本例必须归因于它们的证据。

## 最小复现与临时证据

在同一被控设备已连接、屏幕已有公开测试页面时，通过 Runtime 调用 `session.start`，分别传以下参数；每次创建并停止独立会话，不改变设备 UI：

```json
{"deviceId":"<已连接设备>","videoCodec":"h265","videoEncoder":null,"maxSize":1280,"maxFps":60,"videoBitRate":8000000}
```

1. 连接返回的 `videoPort`，先发送 `videoToken + "\n"`，不记录 token。
2. 对原始 12-byte session header 读取后 8 byte 的 width/height；对媒体包读取 `ptsFlags:u64 + length:u32`，将 config 与 access unit payload 按顺序写入 `.hevc`。包长度与总捕获量必须设上限。
3. 用 FFmpeg 解码，确认其码流尺寸也为 230×512。
4. 只将上述 `maxSize` 改为 1080，重复后应为 486×1080。以 H264、maxSize1280 作对照应为 576×1280。

本机诊断入口和输出均在临时目录 `/tmp/interop-h265-diagnostic/`，不属于可分发产品或仓库测试 fixture；目录清理后不会保留：

```sh
/tmp/interop-h265-diagnostic/capture h265 1280 8000000 5 default 60
/tmp/interop-h265-diagnostic/capture h265 1080 8000000 4 default 60
/tmp/interop-h265-diagnostic/capture h264 1280 8000000 3 default 60
/tmp/interop-test-tools/imageio_ffmpeg/binaries/ffmpeg-linux-x86_64-v7.0.2 -i /tmp/interop-h265-diagnostic/h265-1280-8000000-fps60.hevc -frames:v 1 /tmp/interop-h265-first.png
```

关键证据：`direct-hevc.log`、`direct-hevc.hevc`、`h265-1280-8000000-fps60.{json,hevc}`、`h265-1080-8000000-fps60.{json,hevc}`、`h264-1280-8000000-fps60.{json,h264}`。对应 `*-first.png`、`*-last.png`、`*-reference-before.png` 可原生查看。JSON 记录请求 quality、实际 session dimensions 与每包 flags/length/PTS，不含 token。

## 后续产品与验收建议

- 将“请求的尺寸上限/帧率上限/码率”与“实际编码尺寸、主控 decoder 输出尺寸”分开。实际尺寸来自最新 scrcpy session metadata，decoder 输出来自明确绑定同一 session 的回执；不得仅凭输出 texture 大小推断码流分辨率。
- 当实际长边明显低于请求上限且原设备尺寸足够大时，提示“设备实际输出 230×512；请求上限 1280”，如取得服务端失败及约束事件再明确标注“编码器降级”。仅有尺寸差不能自动证明发生错误回退。
- 保留所选 codec，提供用户可理解的实际结果。可将 1080 作为此设备已验证的选项；不要将该值硬编码为全部设备的 HEVC 策略，也不要静默替用户切换 H264。
- 五格式验收应记录完整请求 quality、目标实际 encoder（未知则明确未知）、最新码流尺寸、decoder 名称/输出尺寸、截图时 frame count/PTS。首帧成功与视觉质量是独立结论。增加稳定公开测试页的实际尺寸及截图对照检查，避免只检查 decode exit 0、首帧和 session.streaming。

本次没有修改编码、解码或 UI 实现；后续由主代理实施真实尺寸回执与质量提示。
