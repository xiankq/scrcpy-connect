# 入编码前 buffer 驻留与可控边界

2026-10-18。针对当前高动态延迟继续分段。本次重新分析已有目标追踪并检查固定
一手源码，没有改变生产参数或重建JAR；随后补采当前默认入口trace如下。

## 已有实际追踪的新证据

输入为`/tmp/connect-raw-drain-fbf1db6ec385/capture.perfetto-trace`，SHA-256
`1b0c76da1b5f11074fe6b2794bab8d070a2001f0231f4bc757c80f00c7fcf5c5`。
该记录对应先前隔离的H264 1280／60／8Mbps、实际576×1280快速排空实验；原始
PTS／CCodec关联及假设见[目标完成边界](../implementation/video-performance.md#目标ccodec完成边界与源年龄2026-10-18)。
它不是最新普通Driver／异步解码的再次测量，不能将下列数值当生产收益。

后台只读分析后，根代理独立复跑slot查询，确认trace data-loss为0，唯一进程
`interop.rawdrain.fbf1db6ec385`（pid14802）。保存SQL、完整事件、完整生命周期及
摘要到`/tmp/connect-source-slot-analysis.json`：

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

使用既有官方`/tmp/connect-trace-processor query <trace> '<SQL>'`离线执行，无设备
操作。slot acquired数是BufferQueue consumer持有数，不是精确Codec2 work队列长度，
也不是所有Surface／应用帧数量。本次根代理没有复跑后台代理的HIDL/map顺序关联，
因此这里只用已独立复核的slot结果支持下一动作。

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

## 下一项实验与重建条件

当前入口验证已取得，见下节。输入驻留仍在，可继续受控候选；没有据此宣称全部
延迟都来自输入槽，也没有跳过实际解码／窗口验证。

若当前仍成立，可在scrcpy已有`OpenGLRunner`接缝做隔离候选：保留最新尚未提交的
源帧，限制1–2帧实际入编码，按真实输出PTS归还许可。不能按任意输出包数归还，
CONFIG／EOS／重复帧需区分；没有后续frameAvailable时，唯一静态终帧仍须被提交。
暂停／停止不得阻塞GL handler等待许可，旋转和Surface重建要撤销旧代待提交工作。
一帧输入不保证所有encoder都会立即输出，需先限定并验证候选codec。

固定scrcpy v5.0.1源码中，`ScreenCapture`无filter时直接将encoder Surface交给显示，
`OpenGLRunner`当前对frameAvailable直接render，`SurfaceEncoder`处理实际编码输出；
仓库版本及受控来源见[捕获服务说明](../../servers/scrcpy/README.md)。
这种方案改变被控端实际执行的采集／提交逻辑，必须构建有独立摘要的候选JAR，
不能只改`.build`或把已有产物重新打包冒充修复。应先支持独立候选输出，保留当前
两份产物不变。用户“不无故重建”的要求不排除确有服务端源码变化时的必要构建。

候选先验证动态→唯一终值→完全静止、静态冷启、暂停恢复、旋转和停止清理，再做
同1280／60／8Mbps请求的普通Driver A/B/A及实际窗口。只有输入年龄下降且终帧、
生命周期、实际输出和严格预算均有证据，才考虑落入生产；降低默认画质或增加AVD
资源不算该修复。真实ARM硬编、热／功耗和无线吞吐仍须单独验收。

## 当前默认入口复核

普通Driver、默认AMediaCodec async=1、H2641280／60／8Mbps、实际576×1280，两端
2vCPU AVD。一次8秒／32MB的gfx／video／hal／sched／sync追踪，实际完整进程名为
`interop.scrcpy:1c2a1e04:/data/local/tmp/interop-scrcpy-f397fede-9e83-4b75-8b3d-5c2d9c06d565.jar`，
pid4886。原件 `/tmp/connect-e2e/current-source-slots-r3/capture.perfetto-trace`，
SHA-256 `1debad089e480b0c26f30024910eb58b76440573af1a7ce96271ff241039b0e3`。

严格分析器保存全部事件与周期到同目录`capture-slots.json`：data-loss0、精确进程唯一，
735事件、87 acquire／87 release、71完整周期；末墙钟1/3有99.951971%时间同时持有
16个，后段28个完整周期中位1318.763ms、范围1079.972–1470.559ms。18个被观察到的
slot编号不等于同时在途18个。已有推断规则不变，未闭合生命周期不人为补时长。

同次真实输入8次P50／P95=1929／2405ms、首像素2349ms，10张实际窗口计数吻合；
暂停恢复／停止／App与fixture清理完成。诊断期限15秒、硬窗口3秒和性能门槛均保留，
整体exit1、videoPerformanceComplete=false。trace有观测开销，不是无追踪性能A/B。
首次运行完成8次输入1859／2090ms但外围trace定位失败，第二次一次性入口未重启被
setup拒绝，原件均保留，不以第三次覆盖前两次。Android ps NAME只展示路径末尾，
因此实际按精确会话JAR定位PID，再从/proc读取完整nice-name，不猜测PID或匹配截断值。

```sh
rtk proxy python3 -B tool/e2e/video_fixture/analyze_capture_slots.py \
  --trace-processor /tmp/connect-trace-processor \
  --trace /tmp/connect-e2e/current-source-slots-r3/capture.perfetto-trace \
  --process-name 'interop.scrcpy:1c2a1e04:/data/local/tmp/interop-scrcpy-f397fede-9e83-4b75-8b3d-5c2d9c06d565.jar' \
  --output /tmp/connect-e2e/current-source-slots-r3/capture-slots-replay.json
rtk proxy python3 -B -m unittest discover -s tool/e2e/video_fixture \
  -p test_analyze_capture_slots.py -v
```

九条离线测试通过；CLI拒绝覆盖原始证据。分析器拒绝data-loss、进程歧义、未闭合或
越出父slice、重复／逆序acquire、无来源release及slot状态冲突；按墙钟间隔加权，
不使用PTS或跨时钟相减。源侧隔离候选需要下一轮实际验证，不能将本次测量当修复。
