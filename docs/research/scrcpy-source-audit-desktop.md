# scrcpy 固定源码对照：Windows / Linux 视频链路

研究日期：2026-10-23。对照对象是当前工作区（包含尚未提交的新媒体实现），不是旧 fvp。只读检查生产源码，未实施修复、未运行设备性能实验。

上游基线为 scrcpy 5.0.1，提交 `a60891aea193d92e7e5c3942700eca63f9d19a5f`。归档已由主代理校验。FFmpeg 基线为本项目固定提交 `2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e`。本机 Flutter SDK 3.47.7，框架提交 `abaf9c523780a608bd46686fd5e53740a07077f8`；引擎缓存标记 `deb287481e3ce9468f3434937ced4240a70539ca`。Flutter 引擎源码用于解释外部纹理契约，不据此声称每个交付环境的驱动行为相同。

“确认”表示源码条件能够推出结果；“风险”表示缺少特定设备/驱动触发证据；“开销”不等于已测得特定毫秒的回退。本报告不将所有缺失能力都认定为产品缺陷。

## 1. 基线校正：上游也不是无条件零拷贝

- Windows 上游直接取 SDL 的 D3D11 device，交给 FFmpeg，并打开多线程保护；导入时把解码器 texture array 的 slice **GPU copy** 到 SDL 的 NV12 纹理，再由 SDL 绘制。这是没有 CPU 像素往返的路径，不是物理上完全无 copy。[hwdec.c:20-70](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L20)、[interop_d3d11va.c:80-144](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_d3d11va.c#L80)。
- Linux 上游 VAAPI 路径把 NV12 DMA-BUF 两 plane 接到 SDL 已有 Y/UV GL texture 上，最终 SDL draw 时做 YUV 转换和窗口缩放；保留当前映射帧到下一次替换。没有项目当前这样的独立 RGBA 中间面。[interop_vaapi.c:165-269](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L165)、[screen.c:260-343](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L260)。
- 上游软解仍上传三平面 YUV420P 到 SDL，并在 GPU 绘制阶段做转换；不是先在 CPU 统一变 RGBA。[interop_software.c:115-149](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_software.c#L115)。
- 上游也有解码线程、压缩包队列和“只保留最新待呈现 decoded frame”的缓冲。不能把“存在解码线程”或“覆盖旧 decoded frame”单独记为本项目退步。[decoder.c:285-332](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L285)、[frame_buffer.c:47-70](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L47)。

## 2. 逐跳数据路径

| 路径 | 当前实现 | 对照上游的新增工作 |
| --- | --- | --- |
| Windows D3D11 同 GPU | FFmpeg D3D11 NV12/P010 surface → VideoProcessorBlt → 独立 BGRA shared texture → ANGLE 跨 device 导入 → Flutter scene 采样、缩放、present | 独立 RGB 中间面、video processor、跨 D3D device 共享和 Flush；上游有一次 NV12 GPU copy，但与 renderer 共用 device |
| Windows 两个不同 GPU | 硬解 GPU surface → staging/readback → CPU YUV→RGBA → CPU RGBA→BGRA → Flutter GPU upload → shared handle → Flutter scene | GPU→CPU→GPU 全帧往返及两段 CPU 像素处理；原版通过复用 renderer device 避开此拓扑 |
| Windows 真软解 | CPU YUV → swscale RGBA → CPU BGRA 重排 → GPU upload → Flutter scene | 上游 CPU YUV 直接上传 YV12；本项目每帧 CPU 转色、临时 RGBA 分配、BGRA 遍历，上传量通常 4B/pixel 对约 1.5B/pixel |
| Linux VAAPI 可导入 | VAAPI → DRM PRIME/DMA-BUF → 两个 EGLImage/临时 GL texture → NV12 shader → 全分辨率 RGBA FBO → glFinish → Flutter scene 再采样、缩放、present | 一次全分辨率 GPU RGB 写入及后续读；raster 线程同步等 GPU；额外 GL texture/FBO/VAO 对象 churn |
| Linux VAAPI 导入失败 / P010 / BT2020 | HW surface → av_hwframe_transfer_data → CPU swscale RGBA → glTexImage2D 上传 → Flutter scene | GPU→CPU→GPU；还可能先执行一次失败的 import/render |
| Linux CUDA/NVDEC | CUDA decoded surface → CPU readback → swscale RGBA → GL upload → Flutter scene | 当前没有 CUDA-GL interop；“hardwareAccelerated=true”只证明解码硬件帧，不能推出纹理路径无 CPU 往返 |
| Linux 真软解 | CPU YUV → swscale RGBA → glTexImage2D → Flutter scene | CPU 转色、每帧 RGBA 分配和完整 GL texture storage 定义；上游直接 SDL_UpdateYUVTexture |

本地入口：[Windows GpuTexture](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:154)、[Linux populate](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:30)、[Linux DMA-BUF render](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:76)、[共有 readback](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:919)。表中 GPU/CPU 传输是 API 逻辑边界，统一内存硬件未必发生独立显存总线复制，实际带宽成本需测量。

## 3. 确认的正确性问题与可观测性缺口

### D01：硬解回退 / 截图丢失 color metadata（确认，颜色正确性）

`mc_copy_rgba_scaled` 新建 software AVFrame，调用 `av_hwframe_transfer_data`，随后取 software frame 的 `colorspace/color_range` 决定 swscale；没有 `av_frame_copy_props`。固定 FFmpeg 的 transfer 通用层只安排格式、buffer 和尺寸，VAAPI/D3D11/CUDA transfer 只复制像素，不保留这些属性。因此硬件原帧的 full range、BT709/BT2020 metadata 会变成新 AVFrame 默认 unspecified range/space。当前启发式“高度 >576 按709，否则601”不能恢复原信息，full-range 确定按 limited 处理。Windows/Linux 主动将 BT2020 拒出 GPU 路径时尤其明显：回退意图是正确转换，实际又丢了原 BT2020 矩阵。

本地：[lib.rs:934-950](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:934)、[lib.rs:986-1001](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:986)。FFmpeg：[hwcontext.c:448-491](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavutil/hwcontext.c#L448)、[hwcontext_vaapi.c:971-999](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavutil/hwcontext_vaapi.c#L971)、[hwcontext_d3d11va.c:431-503](https://github.com/FFmpeg/FFmpeg/blob/2668cb6e31f4ef3cd59ffe2cf143c9c535141c6e/libavutil/hwcontext_d3d11va.c#L431)。上游直接读原 AVFrame 给 SDL colorspace：[interop.c:86-109](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop.c#L86)。

### D02：GPU 路径 unspecified colorspace 默认601，软回退与上游默认709（确认，颜色不一致）

Windows `YCbCr_Matrix = colorspace == BT709`、Linux `bt709 = colorspace == BT709` 将 unspecified 归601；共有 software conversion 对高于576行的 unspecified 归709；上游把 unspecified 归709。这意味着同一无色彩标记码流因 GPU import 是否成功，可能换色。此项独立于 D01，即使修复 transfer props，GPU 端 fallback 规则仍不统一。

本地：[Windows:318-322](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:318)、[Linux:219-235](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:219)、[lib.rs:986-990](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:986)。上游：[interop.c:91-105](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop.c#L91)。

### D03：解码成功不等于显示成功，render 失败没有状态回流（确认，生产排障缺口）

Rust 在 decoded frame publish 时置 `native_ready=1` 并增加 `frame_count`。Windows texture callback 在 GPU conversion 与 CPU upload 都失败时只返回 nullptr；Linux 在失败时返回 FALSE，或者保留 `self->image` 旧 CPU 画面并把新计数记为已呈现。没有给 Rust error/status 回传。FFI 诊断可持续显示硬解成功、frames 增长，实际纹理黑屏/冻结。生产启动的 `_verifyFrame` 读取的是解码帧 snapshot，也绕过真正的 GL/DXGI/Flutter 呈现，因此不能发现这类问题。上游 import 失败至少在 screen 更新链路显式打印错误；它也不等价于物理 scanout 验收。

本地：[publish:405-438](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:405)、[Windows:158-178](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:158)、[Linux:71-105](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:71)、[verifyFrame:425-430](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/portable_video.dart:425)。上游：[screen.c:985-991](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L985)、[screen.c:1192-1196](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L1192)。

### D04：Linux 外部纹理宽高与所取帧不是原子快照（确认竞态，低概率旋转/瞬时尺寸错误）

`populate` 先 `mc_get_status`，再 `mc_acquire_frame`，两个调用分别锁 shared state。中间 decoder 可发布新尺寸帧。GPU render 按拿到的新 frame 造纹理，返回宽高却取旧 status；`rendered_frame` 也记旧 count。可能声明错误尺寸，随后重复转换。没有下一帧 mark 时，错误可保留到下一次触发 populate。Windows 的尺寸直接取 frame/image，免于这一特定尺寸错误，但也会按旧 count 记账、额外重复转换。

本地：[Linux:44-63](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:44)、[Windows:158-178](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:158)、[acquire frame:899-908](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:899)。上游把 frame 自身尺寸用于 texture/geometry：[screen.c:947-985](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L947)。本轮未构造竞态实测。

### D05：Linux GPU/CPU 回退交替时 output texture storage 缓存失配（确认条件缺陷，触发组合未测）

`McLinuxGpuTexture::width_/height_` 只由 GPU 路径更新；同一个 output GL texture 在 CPU fallback 中可被 `glTexImage2D` 重定义。例如 GPU 成功尺寸A → CPU fallback尺寸B → GPU恢复尺寸A，GPU 缓存仍是A而跳过 storage 分配，此时实际纹理storage是B，viewport及向Flutter申报尺寸却是A。可能裁切、FBO错误或显示尺寸不符。此路径可以在尺寸/像素格式变化、临时EGL导入失败等组合下产生，不表示普通持续VAAPI已出现此问题。

本地：[gpu_texture.cc:191-196](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:191)、[media_codec_plugin.cc:92-94](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:92)。上游 SDL 管理 texture，并在尺寸变化时reset重建，未让互不知情的两套缓存重定义同一 output：[texture.c:86-104](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/texture.c#L86)、[interop_vaapi.c:179-195](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L179)。

### D06：Linux 映射 AVFrame 分配失败会空指针解引用（确认，内存压力）

`av_frame_alloc()` 后立刻写 `mapped->format`，没有空检查；上游同一位置有OOM检查和错误返回。常态成本不是问题，但大分辨率/多路/内存压力时错误恢复不完整。

本地：[gpu_texture.cc:89-90](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:89)。上游：[interop_vaapi.c:197-201](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L197)。

## 4. 平台选择及额外开销

### D07：解码器选择没有由 renderer 设备反推（确认设计差异，高优先性能）

Windows 插件仅把 Flutter adapter 给输出纹理，FFmpeg `av_hwdevice_ctx_create` 仍以 null device 参数在默认适配器建 device。两者 LUID 不同即 CPU fallback。Linux 更没有从当前EGL查询render node；VAAPI默认设备可以与Flutter显示GPU不同。上游 Windows直接使用SDLdevice，Linux `sc_egl_get_drm_render_node` 指定渲染GPU。当前“双显卡开了硬解但性能很差”可由此拓扑解释；没有测量不能断言全部双显卡机器一定不同GPU。

本地：[Windows:436-438](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:436)、[Windows:198-215](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:198)、[Windows:262-266](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:262)、[lib.rs:358-369](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:358)。上游：[hwdec.c:20-70](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L20)、[interop_vaapi.c:341-344](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L341)、[egl.c:98-121](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/egl.c#L98)。

### D08：Linux 正常 VAAPI 每帧额外RGBA pass和glFinish（确认开销，高优先）

当前独立shader把NV12先写全分辨率RGBA，再让Flutter缩放采样RGBA。`glFinish` 在Flutter raster线程等待所有之前的GL工作完成，目的为安全释放映射帧，但打断CPU/GPU重叠；它甚至可能等待该上下文此前与远控无关的UI工作。上游将planes直接接最终SDL纹理并保留映射帧，自己不做这次中间RGBA draw和Finish。不能据此断言上游驱动绝无隐式同步。

本地：[gpu_texture.cc:191-251](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:191)。上游：[interop_vaapi.c:239-267](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L239)、[screen.c:306-343](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L306)。

### D09：Linux NVIDIA硬解固定走CPU readback（确认开销；上游无CUDA路径，不算上游同配置优胜）

构建启用CUDA/NVDEC，默认候选含CUDA，但GPU importer只接收VAAPI。CUDA帧必走 `mc_copy_rgba` 下载、CPU转RGBA、GL上传。当前支持NVDEC解码是额外兼容性，不能拿“NVDEC已启用”宣传整条链路无CPU像素拷贝。scrcpy该固定版本只有VAAPI/D3D11VA/VT interop，没有CUDA interop，故此处应定性为本项目潜力未释放，不是它已实现的同等能力。

本地：[lib.rs:337-341](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:337)、[gpu_texture.cc:80-83](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:80)、[build_ffmpeg.py:212](/home/xiankq/git/scrcpy-connect/packages/media_codec/tool/build_ffmpeg.py:212)。上游候选：[interop.c:18-76](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop.c#L18)。

### D10：软解与不支持GPU import的分支额外CPU转色和更大上传（确认开销）

共有 swscale 为每帧新分配RGBA；Linux `glTexImage2D` 每帧重新指定storage并上传；Windows再逐像素RGBA/BGRA交换并UpdateSubresource。相较上传8bitYUV420，RGBA4B/pixel对YUV约1.5B/pixel，逻辑上传字节约2.67倍；不是总系统带宽或延迟必然2.67倍。1920×1080×60时单段RGBA逻辑写入/上传约497.7MB/s，YUV约186.6MB/s，尚未计各段读取。上游SDL_UpdateYUVTexture保留YUV并在GPU转色。

本地：[lib.rs:963-978](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:963)、[Linux:71-98](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:71)、[Windows:354-364](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:354)。上游：[interop_software.c:138-149](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_software.c#L138)。

### D11：Windows正常硬解多一道全分辨率BGRA中间面和跨device边界（确认开销，公平比较）

当前 `VideoProcessorBlt` 把YUV变BGRA输出，再给ANGLE/Flutter采样；上游先做NV12 CopySubresourceRegion再SDL直接把NV12渲染到窗口。两者都有GPU工作；区别是当前中间面4B/pixel，且独立device、额外RGB pass与Flutter scene复合。不能简单记为“本项目多一次copy”而忽略上游NV12copy。Flutter内嵌UI的收益是产品需求，应优化中间路径而非把Flutter存在本身当bug。

本地：[Windows:232-242](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:232)、[Windows:326-329](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:326)。上游：[interop_d3d11va.c:140-144](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_d3d11va.c#L140)。

### D12：启动/恢复的“32×32验证”先下载整帧（确认固定开销）

启动和恢复调用 `_verifyFrame`，要求32×32像素；共有snapshot却先全分辨率hwframe_transfer再在CPU缩小。会触发一次GPU完成等待、全帧readback、CPU缩放、MethodChannel像素传输。最终传Dart只有4096B不代表前面只读4096B。上游正常首帧呈现没有强制这一额外CPU验证。业务验证有目的，但应该与实际纹理呈现证据分开。

本地：[portable_video.dart:164-177](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/portable_video.dart:164)、[portable_video.dart:398-430](/home/xiankq/git/scrcpy-connect/packages/scrcpy_client/lib/src/portable_video.dart:398)、[lib.rs:934-1017](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:934)。上游：[screen.c:985-990](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L985)。

### D13：帧对象/driver对象和通知 churn（确认小开销，需测后排序）

- 本项目每帧 `av_frame_free + av_frame_clone` 更新latest，呈现时又clone，外加每个packet分配AVPacket、每次decode分配临时AVFrame。上游decoder复用AVFrame，frame_buffer复用tmp/pending并ref/move。两者引用像素buffer均不等于复制像素。
- Linux每帧新建并删除2个GL纹理、FBO、VAO；原版EGLImages也每帧新建，**这部分不是我们独有**，但原版复用SDL的plane纹理，没有临时RGB FBO/VAO。uniform locations每帧查询，许多glGet状态查询，是可削减driver调用。
- Windows每帧新建input/output processor views并释放；output view在相同尺寸/输出纹理时具备缓存机会。每帧Flush是跨device设计要求之一，Microsoft说明它有显著提交开销；不能直接删Flush。
- 本项目每个decoded frame都mark texture，即使尚有待处理的新帧标记；上游发现pending frame未消费时只替换frame、记skipped计数，不重复发SDL事件。Flutter引擎可能合并标记，故这里确认额外调用次数，不推断必排队N个Flutter帧。

本地：[lib.rs:405-407](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:405)、[lib.rs:446-490](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:446)、[Linux:180-218](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:180)、[Linux:255-262](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:255)、[Windows:297-329](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:297)。上游：[decoder.c:223-265](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L223)、[frame_buffer.c:47-70](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/frame_buffer.c#L47)、[screen.c:480-504](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L480)。[Microsoft Flush契约](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-flush)。

## 5. 兼容性与边缘条件

### D14：H.264缺少上游的ALLOW_PROFILE_MISMATCH（确认兼容分支缺失，触发设备未测）

上游仅对H.264启用该flag，专门兼容只报告Constrained Baseline而未报告plain Baseline的后端；本项目没有设置hwaccel_flags。这类硬件明明能解的流可能被FFmpeg拒绝硬件profile、退软件。不能对HEVC盲目启用同flag，上游明确说明可能误选Main10。本地：[lib.rs:276-290](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:276)。上游：[hwdec.c:205-210](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L205)。

### D15：Linux拒绝上游接受的RG88双plane布局（确认，兼容/回退开销）

本项目NV12判定仅接受一个NV12层，或R8+GR88双层；上游接受R8+(GR88或RG88)，并按实际layer format导入。本项目遇到RG88会整帧CPU fallback。它对单层NV12反而比上游宽，不能泛称所有布局都更少。两者都主要面向8bitNV12，不应声称上游P010已无损支持。

本地：[gpu_texture.cc:111-119](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:111)。上游：[interop_vaapi.c:60-85](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L60)。

### D16：Linux GPU shader最低GL版本较高、扩展检查不完整（确认前提差异，旧环境风险）

当前要求desktopGL3.3或GLES3.0，shader自身分别写GLSL130/300es；不满足便CPU fallback。原版借SDL shader和GL_OES_EGL_image interop检查，不在该文件强制同样3.3门槛。项目只检查DMA-BUF import扩展，直接调用eglCreateImageKHR/glEGLImageTargetTexture2DOES；未像上游分别检查EGL_KHR_image_base与GL_OES_EGL_image。极端扩展组合可能触发epoxy unsupported dispatch，需验证而不能直接说必崩溃。

本地：[gpu_texture.cc:28-45](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:28)、[gpu_texture.cc:80-85](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:80)、[gpu_texture.cc:151](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:151)。上游：[interop_vaapi.c:275-297](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L275)。

### D17：Linux GL状态和错误隔离有条件缺口（确认代码条件，实际Flutter触发未测）

- 保存`GL_FRAMEBUFFER_BINDING`一个值，再用`glBindFramebuffer(GL_FRAMEBUFFER, oldFbo)`恢复，会把read和draw两个binding都设为旧draw；调用前若read≠draw则改变宿主状态。应该分别考虑READ/DRAW，不能把此项说成已证明Flutter每帧受损。
- `glTexImage2D`未隔离GL_PIXEL_UNPACK_BUFFER绑定；如果宿主保留PBO，nullptr/CPU指针会被解释为PBOoffset。GPU输出分配和CPU上传两路都受影响。
- shader draw前没有清空既有GL error，结尾只取一次glGetError；上游明确清空再检查。宿主遗留错误会把一次成功转换误判失败，导致glFinish后又额外CPU readback。也没有render错误诊断。
- 未隔离GL_RASTERIZER_DISCARD等少见宿主状态。前述不是让插件保存所有GL状态的泛化建议，而是已能说明具体错误条件的几个边界；本轮没有证据表明Flutter当前必保留这些状态。

本地：[gpu_texture.cc:158-179](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:158)、[gpu_texture.cc:191-196](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:191)、[gpu_texture.cc:247-263](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:247)、[Linux CPU upload:87-97](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:87)。上游：[interop_vaapi.c:239-258](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop_vaapi.c#L239)。

### D18：Windows共享纹理同步契约待实证，Flush不能证明GPU完成（风险，不能按已复现撕裂记账）

输出是单个`D3D11_RESOURCE_MISC_SHARED`纹理，每次回调覆盖；仅Flush，没有keyed mutex/fence/consumer完成回执。Flutter当前Windows引擎在handle不变时不重新release/rebind EGL surface，release_callback只在导入调用结束时释放AddRef，不能当作GPU采样完成。Microsoft明确Flush异步且可能在GPU完成前返回。能确认的是项目没有显式跨device读写完成协议；是否ANGLE/驱动隐式同步已保证一致、是否有撕裂/上一帧内容、以及改成双缓冲是否实际更快，需要GPU trace/压力测试。不能仅因为没有keyed mutex就判定确定黑屏。

本地：[Windows:180-194](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:180)、[Windows:232-242](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:232)、[Windows:329](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:329)。Flutter：[external_texture_d3d.cc:63-116](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/windows/external_texture_d3d.cc#L63)。上游共device路径：[hwdec.c:20-70](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L20)。[Microsoft Flush异步契约](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-flush)、[OpenSharedResource要求更新后Flush](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-opensharedresource)。

### D19：Windows VideoProcessor选项/色域缺乏明确契约（风险/设计缺口）

固定processor index0、输入输出帧率60、Usage PLAYBACK_NORMAL；只设置输入旧式color space，没有设置output color space或显式关闭自动画质处理。多数SDR驱动默认可工作，但高刷新、驱动画质增强、full-range RGB、HDR/BT2020路径没有明确且被验证的配置。颜色D01/D02是确认问题，此处不重复宣称所有画面都错误。上游使用SDL标记色彩空间并在GPU shader最后采样阶段转换，避免独立video processor默认策略。当前BGRA8888输出、LinuxRGBA8输出也没有保存HDR transfer/primaries或tone mapping，应把HDR视为未完成能力，不能以矩阵支持BT2020等同HDR正确显示。

本地：[Windows:281-322](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:281)、[Linux:34-45](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:34)、[view:46](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/view.dart:46)。上游：[interop.c:86-109](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop.c#L86)。本轮亦未证明scrcpy该版本有完整HDR显示能力；不能把HDR缺口只归本项目。

### D20：GPU能力判断只关心decode，interop失败不会重选最合适路径（确认策略差异）

候选先创建硬件context，命中即停止；不在创建时验证与Flutter的互通。VAAPI建成功但EGL import每帧失败，会一直VAAPI+CPU readback；WindowsD3Ddevice与renderer不同也一样。开解码器失败会直接open software，不继续尝试另一硬件候选。原版先挑可用renderer interop，再初始化对应decoder。当前可选择更快CPU解码或另一个GPU，但没有基于端到端路径的成本策略。本项不等于“软件必然比readback硬解快”，需要实测。

本地：[lib.rs:328-388](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:328)、[Windows:169-176](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:169)、[Linux:56-75](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:56)。上游：[texture.c:48-54](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/texture.c#L48)、[interop.c:18-76](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/interop/interop.c#L18)。

### D21：Windows DXVA2、Linux Vulkan候选不等于实际启用能力（确认配置差异，轻微无效探测）

Rust列了Windows DXVA2、Linux Vulkan候选，但本项目FFmpeg精简profile只开启WindowsD3D11VA与LinuxVAAPI/NVDEC，没有启用相应DXVA2/Vulkan hwaccels。`avcodec_get_hw_config`找不到时跳过，所以一般不会尝试实际创建这些设备。它不是额外真实可用后备，也不应把这个候选列表当平台支持清单。

本地：[lib.rs:332-341](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:332)、[build profile:191-237](/home/xiankq/git/scrcpy-connect/packages/media_codec/tool/build_ffmpeg.py:191)。上游同样按编译能力提供有限后端：[hwdec.c:82-127](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L82)。

### D22：软解吞吐/延迟取舍改变（确认参数差异，不直接判性能倒退）

本项目除dav1d外强制`thread_count=1`、`FF_THREAD_SLICE`；上游只置LOW_DELAY，保留FFmpeg线程默认策略。补充核对：本项目固定FFmpeg的`options_table.h:220`默认threads本身就是1，`pthread.c:49-63`也会在LOW_DELAY下排除frame threading，因此不能把单线程认定为相对同版本上游的确定退步。高分辨率软解可研究slice并行，但须以相同码流结构、CPU和FFmpeg版本比较吞吐及延迟。

本地：[lib.rs:282-290](/home/xiankq/git/scrcpy-connect/packages/media_codec/rust/src/lib.rs:282)。上游：[decoder.c:15-38](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/decoder.c#L15)。

### D23：呈现状态少了路径和计数，难定位究竟多了哪一轮（确认监测缺口）

当前`mc_status`有decoded frame count、decoder/hardware flag，缺少presented/uploaded/import_failed/readback_count/GPU adapter/render node以及每阶段耗时。上层50ms轮询尺寸/decoder不在每帧像素路径，但状态传播延后至下一轮询；不应把50ms轮询误算成每帧显示必加50ms。上游有renderer/interop/VA设备日志，screen skipped frame计数；项目还缺GPU import退CPU原因日志及计数。

本地：[media_codec.h:42-54](/home/xiankq/git/scrcpy-connect/packages/media_codec/native/media_codec.h:42)、[controller.dart:132-175](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/controller.dart:132)。上游：[texture.c:13-54](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/texture.c#L13)、[hwdec.c:89-97](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/hwdec.c#L89)、[screen.c:494-500](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L494)。

### D24：Flutter vs SDL呈现阶段不同，不能把vblank时延当语言成本（设计差异，未定量）

本项目native mark后由Flutter external texture在raster时采样，并与场景、其他UI、桌面compositor合成。上游SDL事件消费最新frame立即RenderPresent；这也可能受驱动、窗口compositor、VSync影响。额外线程调度/等待、Flutter帧截止错过后的下一个刷新周期是实际可能开销，但本轮没有present timestamps / GPU trace，不能给“固定一帧/16.7ms/Flutter必比SDL慢”的结论。当前低filterQuality/ClipRect/FittedBox也不自动等价软件渲染或离屏saveLayer；只按代码外观不能重复计GPU pass。

本地：[MediaCodecView:39-46](/home/xiankq/git/scrcpy-connect/packages/media_codec/lib/src/view.dart:39)、[Windows frame callback:461-464](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:461)、[Linux ready:292-296](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:292)。上游：[screen.c:480-504](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L480)、[screen.c:985-990](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L985)。

## 6. 生命周期核对与不应重复报告的问题

- Windows output AddRef + descriptor release_callback 保护share handle所属texture到Flutter导入；`UnregisterTexture(...,[output]{})`保留Output直到unregister回调。现有代码已针对对象提前销毁做了处理，不能再把旧“裸D3D纹理指针跨device”报告为现状。[Windows:187-193](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:187)、[Windows:416-420](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:416)。
- Windows硬件VideoProcessor在FFmpeg D3D context lock内提交，输入AVFrame持有到该函数返回。这解决同一个FFmpeg device immediate context的CPU并发；D18讨论的是另一个consumer device，不应混为一个问题。[Windows:267-333](/home/xiankq/git/scrcpy-connect/packages/media_codec/windows/media_codec_plugin.cpp:267)。
- Linux解码帧render后glFinish才释放映射帧，具有显式GPU完成保障。不能同时说“它glFinish太慢”又认定“它立即free导致解码surface必被覆盖”；性能开销源于当前正确性保障方式。[gpu_texture.cc:249-287](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/gpu_texture.cc:249)。
- Linux关闭时先在texture mutex内置decoder=null，再mc_destroy停止worker，然后unregister/unref。GL资源用同display的独立GDK cleanup context删除。若window已destroyed或cleanupcontext创建失败，删除会跳过，是依赖最终context teardown的条件边界；没有证据则不记为已发生长期泄漏。[Linux:107-138](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:107)、[Linux:241-249](/home/xiankq/git/scrcpy-connect/packages/media_codec/linux/media_codec_plugin.cc:241)。
- 上游暂停同样继续解码，保存最新resume frame，因此“暂停仍解码”本身不是相对上游的缺陷。项目与上游在控制RESET_VIDEO/恢复snapshot等额外动作上的差异交由主报告运输/业务链路分析。[screen.c:995-1041](https://github.com/Genymobile/scrcpy/blob/a60891aea193d92e7e5c3942700eca63f9d19a5f/app/src/screen.c#L995)。

## 7. 优先顺序与验证边界

1. 先修复确定正确性：D01 metadata、D02默认色彩、D03呈现失败观测、D04帧/尺寸原子快照、D05共享纹理storage缓存、D06 OOM。
2. 再选择端到端renderer设备：D07/D20，优先避免已有硬解却每帧readback；补D14/D15兼容分支。
3. 正常低延迟路径重点优化D08 Linux glFinish/RGBA中间面，及D11 Windows RGB中间面/跨device；必须同时设计纹理所有权和GPU完成同步，不能单独删等待。
4. CPUfallback保留YUV、减少CPU转色/分配和大上传（D10），优化一次性启动readback（D12）。
5. D13小对象优化和D17/D18驱动边界，以真实GPU trace、颜色测试图、双GPU/resize/device-loss压力用例验证后排序。没有在本轮重新运行AVD/实体设备，不将静态缺口冒充已复现。

可比较指标应包含：compressed packet ingress→decode start/end→frame ready→GPU import/convert start/end→Flutter latch/present→屏幕采样；同时记录decoded/presented/skipped/readback帧数和decode/render adapter身份。单看`hardwareAccelerated=true`或`frameCount`不能证明已达到低延迟GPU呈现。
