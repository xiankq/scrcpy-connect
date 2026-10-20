# 入编码前 buffer 驻留与可控边界

2026-10-18。固定Android16源码与API36双AVD的隔离实验：H264、`c2.android.avc.encoder`、请求1280/60/8Mbps、实际576×1280，两端2vCPU、SwiftShader。bounded-input及steady-one捕获补丁均未采用，现行服务端使用[vendor官方产物](../../servers/vendor/README.md)。本报告保留队列机制、负向性能结果和归因限制；当前复现入口见[视频性能记录](../implementation/video-performance.md)。

## 槽位观测方法

Perfetto中把GraphicBufferSource slot切片与父操作关联。trace必须data-loss=0且精确进程唯一；首事件为release的slot只能推断起始前已被acquire，不补造起点。完整周期拒绝重复acquire、无来源release、越出父slice和逆序事件。后段按slot事件墙钟跨度的最后1/3划分，占用按相邻事件时长加权，不是按样本数截取。

快速排空raw实验追踪SHA-256 `1b0c76da1b5f11074fe6b2794bab8d070a2001f0231f4bc757c80f00c7fcf5c5`，结果如下：

| slot事件统计 | 结果 |
| --- | --- |
| acquire／release | 309／303 |
| 完整acquire→release对 | 293 |
| 同时acquired数量范围 | 10–16 |
| 最后墙钟1/3同时持有16个的时间占比 | 99.913% |
| 后段完整持有周期中位 | 583.259ms |
| 后段完整持有范围 | 503.514–678.189ms |

slot首次事件若是release，推断它在trace开始前已经acquired；这些没有已知起点的
周期不计入完整持有时长。所有后续事件须满足不重复acquire、没有无来源release。
末段按slot事件的墙钟跨度最后1/3切分，占用按相邻事件间隔加权，不能与旧文档按
样本数量最后1/3的590.659ms混成相同集合。查询如下：

```sql
SELECT s.ts, s.name, par.name op
FROM slice s
JOIN slice par ON par.id=s.parent_id
JOIN thread_track tt ON tt.id=s.track_id
JOIN thread t ON t.utid=tt.utid
JOIN process p ON p.upid=t.upid
WHERE p.name='interop.rawdrain.fbf1db6ec385'
  AND s.name GLOB 'GraphicBufferSource: *'
  AND par.name IN ('acquireBuffer','releaseBuffer','queueBuffer','dequeueBuffer')
ORDER BY s.ts
```

slot acquired数表示BufferQueue consumer持有数，不是精确Codec2 work队列长度或全部Surface帧数。SQL的进程名应替换为本次完整nice-name，不能使用ps截断名或猜测PID。

## 为什么普通codec参数不足以控制它

固定Android16源码的因果链如下；源码不等于已证明AVD二进制逐字相同：

- [MediaFormat.java](https://android.googlesource.com/platform/frameworks/base/+/99b01a65cc4c104933788b3143285ab6bae65827/media/java/android/media/MediaFormat.java#1787)
  中`num-slots`是codec输出信息，应用设置会被忽略；`max-input-size`是输入字节大小。
  不能凭这些参数名宣称降低了输入在途数量。
- [CCodec.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/CCodec.cpp#288)
  从wrapper取`nBufferCountActual`，
  [C2OMXNode.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2OMXNode.cpp#88)
  转到`getInputBufferParams`。
- [C2NodeImpl.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/codec2/sfplugin/C2NodeImpl.cpp#224)
  在当前尺寸路径给出16；超过4096×2340才走另一计数分支。
  [GraphicBufferSource.cpp](https://android.googlesource.com/platform/frameworks/av/+/4b2111885ff934799e70eddae2527a9848c3be29/media/module/bqhelper/GraphicBufferSource.cpp#1170)
  将其用于consumer的`setMaxAcquiredBufferCount()`。只减少producer缓冲数不能撤销
  consumer已经取得的16帧。

## 同期默认入口复核

普通Driver、AMediaCodec async=1、同画质的8秒追踪，data-loss=0，87 acquire/87 release、71完整周期。末段99.952%的时间持有16个，28个完整周期中位1318.763ms、范围1079.972–1470.559ms。观察到18个不同slot编号不等于同时在途18个。

同次8输入P50/P95为1929/2405ms，首像素2349ms，实际窗口匹配、生命周期清理通过，但严格性能失败。trace有观测开销；它与快速raw排空不是相同负载，不能把583ms→1319ms解释为代码回退。

严格分析器与离线回归保留在[分析工具](../../tool/e2e/video_fixture/analyze_capture_slots.dart)和[测试](../../tool/e2e/tests/analyze_capture_slots_test.dart)。CLI拒绝覆盖原件，测量不使用媒体PTS跨时钟相减。

## 隔离候选：最多两项输入

候选强制主屏经过identity GL桥，不改变请求质量与videoSize。GL handler持续updateTexImage并只保留最新pending，绝不阻塞等待credit；没有后续frameAvailable时，credit归还也会主动drain，保证唯一静态终帧有机会提交。[SurfaceTexture生命周期](https://source.android.com/docs/core/graphics/arch-st)是这一接缝的来源依据。

每代最多两项ledger，在swap前登记精确编码PTS，成功交付完整媒体包且releaseOutputBuffer后归还credit；CONFIG、EOS、未知或重复PTS不误还。codec.start成功前不swap，旧代timer/output无效。关闭GBS原生repeat与限帧，由同一模块生成受credit约束的重复输入；ledger另存源纹理时间，不能把新编码PTS冒充新像素年龄。静态bootstrap可用第二项，满窗无输出则有界失败，不扩大窗口或降质量。

暂停/旋转/停止先撤销该代输入，再释放capture/codec/Surface。GL不等credit，并不意味着底层未清理即可确认暂停。该状态设计也解释了为什么“只把producer buffer改少”不足以限制consumer在途。

候选JAR SHA-256 `34294a6a21ef57f0ecdb74b8ed418bdd2e05198eea553446c7b5c7e44911fc6b`。目标端真实H264包经FFmpeg7.0.2离线解码，静态冷启、一次变化、动态后唯一终值、暂停变化恢复与旋转均取得正确计数和尺寸；暂停后媒体停止增长，退出清理通过。这证明限定服务端路径可工作，不证明实时Flutter性能。

## 普通Driver A/B/A与候选slot复核

三组均先结束构建，核对APK native库实际嵌入对应完整JAR；同画质、默认async=1、每组3轮共24输入：

| 顺序 | 输入P50/P95 ms | 首像素3次 ms | 窗口匹配/迟到 |
| --- | --- | --- | --- |
| 原JAR A1 | 1722/1984 | 3124/2419/2218 | 30/25 |
| 双项候选 B | 666/927 | 2780/2544/2399 | 30/13 |
| 原JAR A2 | 1700/2080 | 1879/1992/2297 | 30/21 |

候选输入改善，但仍超过200/300ms预算；首帧无稳定收益，全部严格失败。15秒诊断收集期限没有放宽3秒窗口及成功判定。返回基线的一次热重启丢失预编译Dart defines，样本配置不匹配而被排除；最终重装同一基线APK并显式传参后才纳入A2。

独立候选trace为95 acquire/94 release、93完整周期，同时持有0–2项，末段两项79.213%、一项20.737%；34个完整周期中位128.621ms、范围55.524–244.493ms。该次宿主外围脚本中断，未继续输入/窗口循环，因此不能与默认1318.763ms作为同负载定量对照。手动恢复清理另有确认，不冒充自动finally成功。

另一个身份探针曾错误要求运行JAR路径仍存在；官方CleanUp.unlinkSelf会提前删除自身路径，路径缺席不能证明进程已经退出。

## 双项启动、单项稳定输入

steady-one变体在首个有效媒体output后把窗口从2收至1，等两项启动credit都归还才准入后续输入；保留静态终帧drain与3秒stall。状态用例在旧实现失败、新实现通过；目标软件codec在唯一变化后静止3.5秒仍持续输出并保留终值，暂停/旋转/停止通过。

同Driver/画质的双项→单项→双项A/B/A，输入P50/P95为691/852→581/810→686/925ms；窗口迟到16→9→15。首帧无稳定收益，严格预算仍失败。drawEnd→raw条件区间也重叠：中位下/上界311/390→291/367→328/401ms，不能把约15–16%输入改善外推至真机硬编、其他codec或无线长期运行。

## 完整编码序列核查选择偏差

先前raw时间来自snapshot选中的新计数帧，未必是最早新计数包。完整raw ledger→生产Matroska→逐帧解码后，宿主直连实验308包与308帧精确对应；8输入到最早新计数raw中位156.400ms，drawEnd→raw条件下/上界113.375/161.004ms，时钟区间47.629ms。主控AVD在该实验中空闲，不能拿156ms与普通Driver581ms相减归因。

同一实际Rust/Flutter/HTTP路径随后限量保留完整编码前缀：默认关闭、全进程单份、32MiB/8192包，计时内不写磁盘或增加消费者。381包与381帧精确PTS全序列匹配；8输入中7项snapshot选中最早帧，1项选中后一帧、raw晚123.745ms。

同路径input→firstRaw中位335.226ms，drawEnd→firstRaw条件下/上界248.652/317.501ms，firstRaw→onVideo133.274ms，onVideo→snapshot126.461ms。各段中位不能相加替代总体分位数，也不能把draw后区间全称编码CPU或GL时间。实际10.527包/秒、平均1.592Mbps不是请求60fps/8Mbps的实现保证。

这组首像素3522ms、输入P50/P95为642/855ms，窗口与生命周期正确但严格性能失败。两种候选都只证明限定环境中的局部机制与剩余等待，未取得可推广的完整性能资格。
