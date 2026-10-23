# scrcpy 桌面链路整改验收

2026-10-23，针对当前未提交的工作区，逐项对应[固定源码桌面审计](../research/scrcpy-source-audit-desktop.md)和[总审计音频项](../research/scrcpy-source-audit.md)。本文是本轮结果，不替代架构或平台支持规格。

## 实施与证据边界

Linux 使用本机 Mesa Intel Graphics RKL GT1，真实 EGL、VAAPI、DRM PRIME 和系统 ALSA；C++ 插件完整链接实际 Rust 媒体核心，使用 `-Wall -Wextra -Werror`。新增 GL 测试运行生产 importer，ALSA 测试使用真实 `libasound.so.2` 的 null PCM，不向扬声器发声。

Windows 在 `192.168.1.101` 的独立目录真实完成 MSVC `/W4 /WX` 插件编译、profile 3 固定依赖重建与正常 `main` Release 整包构建。生产 WASAPI sink 和 core lifecycle CTest 两项全通过。Session 1 的真实 Flutter AV1 回放连续三次创建/释放均读取到 23,229 色，实际后端为 libdav1d、纹理路径为 `cpu/dxgi`。最新全量源码的 DeviceRuntime 组装也通过：实际 `h264/d3d11va`、NVIDIA GTX 1650，纹理子树 1966 色，WASAPI 接受 8192 字节并确认播放时钟前进。被控仅为 API 36 x86_64 AVD；这些结果不证明实体 Android、AV1 硬解、双 GPU、实体热插拔或扬声器可闻。详见 [Windows 验收](windows-native-media-validation.md)。

新状态 `presented_frame_count` / `presented_sequence` 记录的是**平台纹理准备和回调消费**。Windows 回调之后 Flutter 才调用 ANGLE 导入，公开 descriptor release callback 即使导入失败也可能调用，没有携带成功标志；这些计数不是 Flutter 合成、GPU present 或面板发光证据。Linux 也需要实际 Flutter 纹理子树读回验证最终组装。

## D01–D24 对应结果

| 项 | 本轮结果 | 验证或保留边界 |
| --- | --- | --- |
| D01 | 公共核心下载硬件帧后复制 frame properties，再做颜色转换；平台 fallback 持有并转换同一帧 | 公共核心测试与总验收负责完整色卡；本机 VAAPI/CPU 参考像素匹配 |
| D02 | Windows、Linux GPU unspecified colorspace 统一默认 BT709，与公共 swscale 和 scrcpy 一致 | GL 实测 unspecified 与显式 BT709 像素相同 |
| D03 | Windows 转换/上传失败和 Linux GL 上传失败经 `mc_report_present` 回流；CPU fallback 路径显式区分 readback | 能观察插件失败及回退；公开 Flutter API 不能反馈全部 ANGLE 导入失败 |
| D04 | `mc_acquire_frame_snapshot` 原子取得 frame 和 sequence；尺寸直接读取该 frame | Linux 不再把先前 status 的尺寸用于下一帧 |
| D05 | CPU 重新定义 GL output storage 时使 importer 尺寸缓存失效；稳定尺寸 CPU 上传使用 subimage | EGL 测试实际执行 A → CPU 小尺寸 storage → A，像素与尺寸正确 |
| D06 | 映射帧分配失败先返回；验证 DRM object index、offset 和 pitch 范围 | 真实 GL 路径通过；未执行系统级 OOM 注入 |
| D07 | Windows 将 Flutter adapter LUID 匹配为 DXGI ordinal，指定 `d3d11va:N`；Linux EGL 设备可查询时指定 `vaapi:/dev/dri/renderD*` | EGL/DRM 不可查询时保留默认选择和显式 fallback；Windows 双 GPU 未实测 |
| D08 | 正常 VAAPI draw 后用 GL fence 保留源映射、EGL image 和 plane texture；保留队列最多四帧，只有 GPU 落后或异常才等待 | Intel 连续十二帧真实 DMA-BUF import 与源帧保活通过。单一 RGB 输出是 Flutter GL 外部纹理 API 的必要边界，仍需 YUV→RGBA pass |
| D09 | 新增动态 CUDA/GL interop，NV12 用 `cuMemcpy2DAsync` 设备到设备复制 R8/RG8 planes；GL fence 保留源帧及 CUDA registration | 无 CUDA SDK 链接依赖；本机没有 NVIDIA，CUDA 正常设备路径未运行，错误/不兼容路径保留 CPU fallback |
| D10 | Linux 软件 NV12/YUV420 直接上传 YUV planes 并由 GPU 转色，重用 plane storage；Windows swscale 直接产出 BGRA，删除第二遍 CPU 通道交换 | Linux 实际 YUV/NV12 像素通过；不支持的格式仍经公共 CPU 转换 |
| D11 | 选择同一 renderer adapter 避免常见跨卡回读；保留 GPU VideoProcessor→BGRA→Flutter scene | Flutter Windows descriptor 只接受 RGB 表面，不能把保留 UI 合成的现有 API 伪称为 SDL NV12 直采样 |
| D12 | 公共呈现层移除正常启动/恢复的强制 snapshot 读回；显式 snapshot 仍可用 | 打开确认解码和输出绑定；不能在组件挂载前等待 texture populate，否则产生启动死锁 |
| D13 | Windows 缓存相同输出 texture 的 processor output view；Linux 缓存软件 plane textures/storage | Linux FBO/VAO 仍逐次创建并销毁：它们属于上下文局部对象，当前 GDK 关闭路径在另一共享上下文清理，不能错误跨上下文删除这些对象 |
| D14 | 公共核心仅 H264 启用 ALLOW_PROFILE_MISMATCH | HEVC 不套用该兼容标志；特定 OEM profile 设备仍需实测 |
| D15 | Linux 接受 R8 + GR88/RG88，并按 descriptor 实际 fourcc 导入 | Intel 实际导出格式已通过；其他驱动 RG88 分支未强制构造 |
| D16 | 检查 EGL image base、DMA-BUF import、GL OES EGL image；desktop 门槛降至 GL3.0 + sync 支持，GLES 为 3.0 | 不满足条件走明确 fallback，不调用不支持的 EGL/GL dispatch |
| D17 | 分别恢复 READ/DRAW FBO、PBO、unpack alignment/row length/offset、rasterizer discard 等；清除并隔离宿主旧 GL error | 真实 EGL 测试制造这些状态和旧错误，像素正确且宿主状态未改变 |
| D18 | 保留已有 shared-handle/Flush 契约与资源引用，不将未证实风险包装为已修复 | Flutter 未提供 consumer GPU 完成 fence；descriptor release 不是采样完成。当前没有驱动级撕裂复现，也没有足够契约安全地只加 keyed mutex 或重用双缓冲。跨 device 显式同步风险仍须 Windows GPU trace/压力验收 |
| D19 | Windows 关闭 processor 自动画质处理，选择 OPTIMAL_SPEED，显式 full-range RGB output color space | SDR 矩阵明确；这不等于新增 HDR tone mapping，也没有宣称 scrcpy 有完整 HDR 能力 |
| D20 | 先匹配 renderer GPU，并通过状态区分 direct interop / CPU readback / 软件上传 | 未基于未经测量的成本模型自动改选 CPU/GPU；持续 import 失败会被看见，但没有承诺任意驱动下最佳后端 |
| D21 | 公共核心候选列表与固定 FFmpeg 构建能力核对，实际选择依赖 hw config | 不把未编入的候选算作已支持；由公共核心与构建回执记录 |
| D22 | 公共核心使用 slice/tile 并行且保持 LOW_DELAY，不引入 frame-thread 缓冲 | 它是吞吐参数选择；没有将旧单线程认定为上游性能退步，也没有虚构延迟改善数值 |
| D23 | 新增平台准备计数、sequence、路径、失败及音频真实 played/queued 状态 | 不把 `hardwareAccelerated` 或 decoded count 作为端到端无回读、物理硬解或最终显示证明 |
| D24 | 保持 Flutter 场景集成；区分解码、平台纹理准备、实际 Flutter 合成和 scanout 证据 | 不承诺“固定省一帧”或把 VSync 差异归于 Rust/Dart 语言 |

真实硬件测试还发现审计未指出的构建阻断：旧 Linux 回执 `CONFIG_LIBDRM=0`，导致 VAAPI→DRM PRIME map 直接返回 ENOSYS，所有所谓 GPU import 都回退 CPU。本轮为固定裁剪 FFmpeg 增加 `--enable-libdrm` 和链接配置，重新构建 profile 3，最终补丁 SHA-256 `1437ad9aacede31e6b501f6e789564786f76ce0bdecdd86d61166b1613767bc0`，新回执 `CONFIG_LIBDRM=1`。同一 `--vaapi` 测试由 map 失败变为连续十二帧通过。

## 音频 S01–S11 桌面部分

| 项 | 桌面实施及边界 |
| --- | --- |
| S01 | Rust 正常暂停同步交给 PCM worker；WASAPI Stop/Reset/Start、ALSA drop/prepare 与写入串行。worker 退出时 `audio_close` 在同线程释放 WASAPI service interfaces 和系统资源。 |
| S02 | 平台返回实际接受前缀，错误发生在部分提交后仍保留该前缀；公共核心保存并重试未写尾部。 |
| S03 | WASAPI IAudioClock + padding、ALSA delay 提供真实已播/排队水位和 generation，交给公共 regulator；设备重开或丢队列使 generation 变化。长期漂移仍须 soak。 |
| S04 | 由系统 played/queued frames 报告播放进度，不再仅凭提交 PTS 推断；null PCM 不证明扬声器可闻。 |
| S05 | 桌面不增加 Java 数组桥；压缩包/PCM 所有权由公共 ABI2 负责，平台 callback 期间直接访问借用 bytes。 |
| S06 | ALSA 保留 20ms 请求；WASAPI 采用 shared event 模式，由引擎选择缓冲，公共 regulator 管理目标水位；容量不当成固定延迟。 |
| S07 | WASAPI 改为 event handle 等待可用空间，删除 1ms Sleep 轮询；ALSA 保留非阻塞写及 5ms 有界 wait。80ms 单次 deadline 保证暂停/销毁等待有界，未写尾部不丢。 |
| S08 | Windows 每秒核对默认 endpoint，切换时重开；WASAPI invalidation 后允许重建。ALSA 无法 recover 的设备错误重开 default PCM。未验证实体热插拔；ALSA default 路由后端仍由系统决定。 |
| S09 | 保留桌面混音策略，不把应用租约宣称为平台系统音频焦点；没有新增不适用的独占焦点。 |
| S10 | 公共增益实现负责静音/音量优化；桌面没有为微小运算未经测量引入新平台依赖。 |
| S11 | 每设备共享音源所有权继续保留；是否合并 scrcpy 进程是传输/活动编排职责，不在桌面插件复制抓音服务。 |

WASAPI event 模式的 buffer duration/period 均为 0，符合[官方 Initialize 契约](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudioclient-initialize)。service 释放跟随 worker，符合[IAudioRenderClient 同线程 Release 契约](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-iaudiorenderclient)。

## 可重复验证

构建使用现有临时 Linux 插件检查工程（导入当前 Flutter Linux SDK），启用 `MEDIA_CODEC_BUILD_TESTS=ON`；新增测试在 Release 也显式启用 assert。验证命令为：

```sh
cmake --build /tmp/media-codec-linux-plugin-check/build -j4
ctest --test-dir /tmp/media-codec-linux-plugin-check/build/plugin --output-on-failure
LIBVA_DRIVERS_PATH="$MC_LOCAL_DEV_SYSROOT/usr/lib/x86_64-linux-gnu/dri" \
  /tmp/media-codec-linux-plugin-check/build/plugin/media_codec_gpu_texture_test --vaapi
```

最终完整插件链接通过，CTest 三项全部通过（GL、ALSA、公共 core lifecycle）；真实 Intel VAAPI 十二帧回归也通过。最初旧 core lifecycle 夹具因“零写入后允许丢包”的旧预期超时，公共核心修正夹具为保留并排空尾部，最终重编复跑通过。临时原始日志为 `/tmp/media-codec-desktop-final-build.log`、`/tmp/media-codec-desktop-final-ctest.log` 和 `/tmp/media-codec-desktop-final-vaapi.log`；测试源码和运行入口保留在 `packages/media_codec/linux/tests/`。

Windows 普通 Release 使用 `tool/build_host.dart windows`，首次隔离目录含依赖重建用时 512.4 秒；后续重新同步完整最终业务代码、关闭修复与生产诊断再增量构建。最终媒体插件为 7,561,728 字节，回执 profile 3 和上述最终补丁 SHA 一致。新增 Windows 原生测试入口位于 `packages/media_codec/windows/tests/`，不打入归档。最终包数值见 Windows 验收的最后记录。

最初直接从 SSH 的 Session 0 启动 Flutter 回放时，原生已成功回退 libdav1d 并解码 24 帧、错误为零，但 raster 尚未消费外部纹理，`RepaintBoundary.toImage` 返回 `operation failed`。同一生产代码改在已登录用户 Session 1 的临时 InteractiveToken 计划任务运行即通过；该任务已删除。FFmpeg 的 AV1 硬件初始化拒绝日志是该机器的正常软件回退过程，不能据此判为回退失败。Windows 原始证据下载于 `/tmp/media-codec-desktop-windows-evidence/`，最终结果不依赖其永久保留。


## 私有 ADB 生命周期补充

真实 Windows 组装退出检查发现独立 ADB server 残留。源码确认两个关闭状态缺陷：native owner 在 close 成功前被清空且异常被吞掉，应用 shutdown 永久缓存失败 Future。现仅在 close 成功后释放 owner，失败向上传播并允许重试；关闭过程中不接受重新初始化。FlutterAdb 优先向自己持有的 server 发送 `kill-server` 并确认退出，才以有界 Process.kill/SIGKILL 兜底；不操作系统默认 5037 或其他应用的 server。

整改后 Windows 再跑完整 A/V runtime，`shutdownNativeAdb` 真正执行并返回成功，退出后该测试进程消失、独立端口拒绝连接，无需手动 kill。只测试裸 FlutterAdb 时旧实现也能正常退出，因而不能把此前全部残留武断归因为 Windows Process.kill 本身。失败重试、并发去重、成功后幂等，以及真实独立 server 端口关闭且无关 listener 保留，均有回归；Linux 和 Windows 最终均为 20 项通过、1 项需要设备授权夹具而跳过，相关生产和测试静态分析无问题。Windows 原始记录为 `desktop-adb-tests.log`。


上轮 Windows 普通 main Release 已包含生产诊断、关闭重试及核心分配失败修复，最后增量 12.7 秒，构建检查通过；随后 Windows native CTest 2/2 通过（WASAPI 0.71 秒、core 0.42 秒）。该历史 ZIP 为 **33,244,358 字节**，SHA-256 `f6d7717cf51ef54ea2521eb3412dcf4fe543f1d797af2343ff346d16fa1cf5af`，81 项 CRC 全通过，没有 test/replay 产物。远端与下载副本 SHA 一致，之前候选均已被替换。测试对应的私有 server、计划任务和反向隧道均已清理；保留源码、真实构建日志、依赖输入与复用缓存。


## 后续普通 Windows 启动缺口

用户随后报告普通启动的“函数不正确。 (os error 1)”，真实最小回归确认：Runtime 已初始化，普通 bootstrap 的媒体缓存登记失败。旧 A/V 组装用例绕过这段入口，不能作为完整普通启动验收。根因是缓存安全检查误把 Windows canonical 路径的 Prefix 分量当成完整目录查询；修复只延后到 RootDir 完成后查询，继续检查每个真实组件和符号链接，不吞 I/O 错误。精确红绿、普通 main 集成截图及替换交付记录见 [Windows 启动修复](windows-native-media-validation.md#普通启动-error_invalid_function-修复)。


启动修复最终 Windows 原生回归 2/2 通过（正常 canonical 缓存与 Windows junction 拒绝，0.20 秒）；真正 application.main 的 Profile 回归 17 秒通过并保留无凭据设备首页截图。最终普通 Release 从新 ZIP 独立解压后实际显示应用界面，生产日志 `bootstrap.ready`，正常窗口关闭 exit 0、私有 ADB 无残留；含配对二维码的普通窗口截图已删除，不公开交付。一次后续重复被控制台中断，不算通过，相关自有 ADB 已清理。最终归档 **33,248,331 字节**，SHA-256 `accc16ed20b906cbd38b5507604777ad21fdc2528623671983ac02f7e9d2b31e`，81 项 CRC 通过，替代上轮 f6d7717c… 归档。此次是普通启动缺口及最后业务终止原因修复后的重新构建，不重复声称执行了此前媒体/GPU、长时间漂移或硬件故障注入。
