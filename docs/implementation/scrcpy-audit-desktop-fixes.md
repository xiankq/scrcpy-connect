# scrcpy 桌面链路整改验收

2026-10-23 工作区结果；上游机制见[固定源码研究](../research/scrcpy-source-audit.md)。公共 C/S 项归[总表](scrcpy-audit-fixes.md)，本页只保留桌面实现差异。

## D01–D24 对应结果

| 项 | 实施与保留边界 |
| --- | --- |
| D01–D02 | 下载硬件帧复制颜色属性；fallback 转换同一帧；unspecified 矩阵默认 BT709。Intel VAAPI/CPU 参考及 GL unspecified 对照像素通过。 |
| D03–D04 | `mc_report_present` 回流转换/上传失败，原子取得 frame/sequence 与尺寸。准备计数只到平台 callback 消费；Flutter ANGLE 导入失败没有完整公开回执。 |
| D05–D06 | CPU 重定义 storage 使 importer 尺寸缓存失效，稳定尺寸用 subimage；检查分配及 DRM object/offset/pitch。真实 A→CPU 小尺寸→A 和像素测试通过，未做系统级 OOM。 |
| D07 | Windows 按 Flutter adapter LUID 选择 `d3d11va:N`；Linux 可查询 EGL 设备时选 render node，否则默认并显式 fallback。双 GPU 未实测。 |
| D08 | VAAPI draw 后 GL fence 保留源映射、EGL image/plane texture，最多四帧；Intel 十二帧真实 DMA-BUF import 通过。Flutter RGB 纹理仍需 YUV→RGBA pass。 |
| D09 | 动态 CUDA/GL interop 将 NV12 设备到设备复制到 planes，fence 保留资源；不链接 CUDA SDK。本机无 NVIDIA，正常 CUDA 路径未运行，错误路径可 CPU fallback。 |
| D10–D11 | Linux 软件 NV12/YUV420 planes 复用 storage、GPU 转色；Windows swscale 直出 BGRA，GPU VideoProcessor 输出经共享 RGB 纹理。跨适配器仍可 CPU 回读上传。 |
| D12–D13 | 正常启动移除强制 snapshot；Windows 缓存 output view，Linux 缓存 plane storage。Linux FBO/VAO 属上下文局部对象，关闭可能在另一共享上下文，仍逐次创建销毁。 |
| D14–D16 | H.264 单独允许 profile mismatch；DRM 按实际 R8+GR88/RG88 导入；检查 EGL/GL 能力，desktop GL3.0+sync、GLES3.0 为门槛。Intel 格式通过，其他驱动 RG88 未强制构造。 |
| D17 | 保护 READ/DRAW FBO、PBO、unpack、rasterizer discard 等宿主状态并隔离旧 GL error；真实污染状态夹具通过。 |
| D18 | 保留 shared-handle/Flush 与资源引用。Flutter 未提供 consumer GPU 完成 fence，descriptor release 不代表采样完成；尚无驱动级撕裂复现，也无足够契约安全增补 keyed mutex/双缓冲。需 Windows GPU trace/压力验证。 |
| D19–D20 | VideoProcessor 禁自动画质处理、选 OPTIMAL_SPEED、明确 full-range RGB；区分 direct interop、readback、软件上传。没有新增 HDR tone mapping 或未经测量的自动成本选型。 |
| D21–D24 | 候选解码器按固定 FFmpeg 能力选择；slice/tile 保持 LOW_DELAY；分开记录解码、平台准备、Flutter 合成。VSync/scanout 仍须独立取证。 |

真实硬件测试同时修复 FFmpeg 未启用 libdrm 导致 DRM map ENOSYS 的构建缺口；最终依赖身份见[总表受控依赖](scrcpy-audit-fixes.md#受控依赖)。

## 音频 S01–S11 桌面部分

WASAPI event 等待替代 1ms 轮询；ALSA 非阻塞写及 5ms 有界 wait。单次等待限 80ms，返回实际接受前缀，Rust worker 保留尾部并串行暂停、flush、关闭。WASAPI service 在创建 worker 线程释放；shared event 初始化 duration/period 均为 0，见[Initialize](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-initialize)及[同线程 Release](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iaudiorenderclient)。

IAudioClock/padding、ALSA delay 提供 played/queued 与 generation；默认 endpoint 每秒核对、失效可重建，ALSA 不可 recover 时重开。设备缓冲由系统决定，实体热插拔/长期漂移未验。共享音源、公共增益和调节器由总表维护。

## 可重复验证

- Linux：`packages/media_codec/linux/tests/`，CMake `MEDIA_CODEC_BUILD_TESTS=ON`；CTest 的 GL、ALSA null PCM、core lifecycle 通过。GPU test `--vaapi` 在 Intel RKL GT1、实际 EGL/DRM PRIME、指定 iHD 驱动下十二帧通过。null PCM 无可闻证据。
- Windows：`packages/media_codec/windows/tests/`，MSVC `/W4 /WX` 及 CTest 的 WASAPI/core lifecycle 通过；真实 AV1 软件回退三次 Texture 成像，完整 H.264 D3D11VA/PCM 组装通过。需已登录交互会话；SSH Session 0 的 raster 未消费纹理不能充作成像证据。
- 完整组装：`app/integration_test/media_runtime_lifecycle_test.dart`；普通入口使用 `tool/build_host.dart`。环境与最终包见 [Windows 验收](windows-native-media-validation.md)及[原生验收](native-media-validation.md)。

私有 ADB 关闭失败重试与真正普通 bootstrap 曾暴露两个独立缺口，现有真实退出、canonical 缓存/junction 及普通窗口回归覆盖，详见 [Windows 启动修复](windows-native-media-validation.md#普通启动-error_invalid_function-修复)。不再保留被替换候选包摘要或中间失败流水。
