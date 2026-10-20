# 设计稿与 Flutter 对照（2026-10-19，玻璃覆盖优化）

本轮完成透明页头与真实滚动背景、悬浮控制和弹层的材料统一，以及可中断的按压反馈。生产依赖保持 `liquid_glass_widgets 1.13.0`。41个主要画布、13个状态板及60个局部状态的归属不变；当前40个页面配对已重新比较，**比较完成不等于像素等效或原生动画认证**。

2026-10-20 的现成控件接入见[当前接入核查](glass-components-2026-10-20.md)；本文旧回执不覆盖该次新实现。

设备工作台与后台应用的后续合并、源稿和本轮验证边界见[工作台重设计记录](workspace-redesign-2026-10-20.md)；本文独立设备详情的旧截图配对不再代表当前页面。

添加设备的后续统一表单、上方发现入口与模式切换见[添加页调整记录](add-device-2026-10-20.md)；下方连接页配对表和旧截图保留本次验收时的版本身份，不再表示当前页面结构。

视觉数值由[视觉规范](../../designs/design.md)负责，产品行为见[产品规格](../../designs/prod/README.md)，状态ID见[流程索引](../../designs/prod/user-flows.md)。[逐画布表](canvas-audit-2026-10-19.md)记录发现、实现及局部状态证据；本文件记录验收，不新增另一套规范。

## 有限验收清单

| 项 | 实现／检查范围 | 当前证据 | 结果 |
| --- | --- | --- | --- |
| A 主页面 | 36个普通手机页的透明页头与滚动避让、两个大屏阅读列；3个沉浸页保留各自控制结构 | 当前100PNG／94布局全部哈希匹配，40 compared／40 associated、80个输入哈希一致；100图逐张复看 | 路径被页头遮住、窄屏滚动叠字及短横屏首卡遮挡均已修复并重捕 |
| B 局部状态 | 确认／编辑对话框、抽屉、菜单、Tooltip、浮动反馈与远控恢复面板 | 当前70张local-actions、20张local-recovery、12张state-boards；41主帧与13板及材料板重新导出 | 共享玻璃弹窗及真实状态已同步；设备名称说明可换行，归属语义保留 |
| C 约束与偏好 | 280×620／620×280二倍字、安全区54／34、键盘及宽阅读列 | PageFrame 7项、浮层／布局18项回归通过；横屏两张捕获字体单独修复并复看 | 短横屏使用保留三目的地文字的紧凑侧栏，首卡完整可见且三入口可进入 |
| D 生产材料 | 所有主控悬浮控制与弹层接入widgets；内容卡保留普通材料 | Android API36 x86_64模拟器，Impeller OpenGLES，经Zink使用宿主Intel GPU；本轮32场景无Lite或blur回退 | 原生shader运行；菜单及Tooltip已隔离OverlayPortal采样平面 |
| E 本轮成像 | 真实JPEG滚到页头后；明暗、降低透明度、减少动态下的弹窗／抽屉／菜单／提示／反馈 | gpu-final的32PNG、场景标记、设备／主机／落盘SHA严格匹配；最终逐图复核另记下文 | 初次reduced-menu失字已定位修复；不能用树断言代替GPU画面 |
| F 本轮动态 | 按下、移动、取消、重按与恢复；弹层显示及减少动态 | 37个连续按压样本、60个弹层矩阵样本；取消不触发，恢复原边界，减少动态无位移 | 有限功能断言通过；不据静态PNG声称Apple原生手感等效 |
| G 性能缺口 | 本轮有限捕获不测帧时序；保留此前诊断背景的压力测试结论 | 历史regular33.582／clear16.999／blend29.739／reduced3.842ms，预算16.6666656ms | **仍未关闭**：前三项历史超预算；本轮成像通过不覆盖该缺口 |
| H 集成与清理 | 应用、设计系统、分析、token、普通main及调试资源 | 应用373项、设计系统28项、生成器4项通过；分析无问题；token check／lint 0error、68warning | 普通main热重启、运行错误查询、ZIP／x64 ELF／签名通过；累计清理1418.43MiB，保留应用与复用缓存 |

当前证据根为 `/tmp/connect-glass-coverage/`。主捕获时间 `2026-10-19T13:20:48.118446Z`，100PNG／94布局；横屏两图随后单独刷新。材料后端明确为 `widget-test-fallback`，只替换捕获字体，不更改生产几何。40对报告时间 `2026-10-19T13:24:42.865769Z`，SHA-256 `5233c6ea540a7e5fbc95bed33a86e9ab3d59911f9ea758b11043a992fc096bc0`；40个布局关联与80个输入哈希均经独立复核。Pencil源稿通过对象API保存，未按文本读写。

普通 `lib/main.dart` Android-x64 debug APK为84,005,683字节，SHA-256 `d39601e37c9dc8d85c397de314363cb569bc0454ce27212c2660014b900dccb7`。已安装启动、DTD热重启及查询运行错误为空，正常断开调试后PID11086仍在，adb shell UID2000。`ordinary-main.json`保留ZIP、7份x64 ELF及签名回执。`cleanup.json`记录本轮145次删除、累计1,487,336,553字节（1418.43MiB）清理，含补测重建后再次移除的路径：结束的profile中间产物、专属测试hash、重复APK及测试资产；设备两份夹具与九项调试转发已移除。普通debug、既有release、共享缓存及受控输入保留。此前v4的APK、清理数和捕获仍只属于历史。

本轮按实现、静态截图、GPU成像和运行验证分别记账。G性能缺口保持开放；不声明完整原生等效、所有宿主或真实设备业务均已通过。

## 配对与捕获契约

[配置](../../tool/visual_parity/pages.json)当前包含以下40对。画质配完整页面 `XPceX`，不把局部状态 `FkCjb`拉成整页；失败诊断配 `diagnostics_failed`，选定会话工具配 `selected_session_tools`，不混用成功诊断或未选会话的夹具。

| 比较case | Pencil Frame | Flutter文件 |
| --- | --- | --- |
| `devices` | `lUDPa` | `devices-light.png` |
| `device_workspace` | `nqQEb` | `device_workspace-light.png` |
| `connection_form` | `YvzMk` | `connection_form-light.png` |
| `settings` | `w6WUAT` | `settings-light.png` |
| `transfers` | `W6enLf` | `transfers-light.png` |
| `appearance` | `PLzIA` | `appearance-light.png` |
| `add_device` | `W3GRn` | `add_device-light.png` |
| `discovery` | `yMlVd` | `discovery-light.png` |
| `device_details` | `TMxVJ` | `device_details-light.png` |
| `device_connection_preferences` | `q3bM72` | `device_connection_preferences-light.png` |
| `quality` | `XPceX` | `quality-light.png` |
| `capabilities` | `NVEMy` | `capabilities-light.png` |
| `diagnostics_failed` | `eWu3m` | `diagnostics_failed-light.png` |
| `wireless_guide` | `c0wxY` | `wireless_guide-light.png` |
| `usb_guide` | `OxUaB` | `usb_guide-light.png` |
| `legacy_tcp` | `OpFKk` | `legacy_tcp-light.png` |
| `pairing_form` | `XQZRD` | `pairing_form-light.png` |
| `qr_pair` | `G4CpTk` | `qr_pair-light.png` |
| `apps` | `tbWkA` | `apps-light.png` |
| `sessions` | `iEvoR` | `sessions-light.png` |
| `selected_session_tools` | `XvviW` | `selected_session_tools-light.png` |
| `files` | `MaHXL` | `files-light.png` |
| `file_search` | `lm0us` | `file_search-light.png` |
| `gallery` | `RqDYL` | `gallery-light.png` |
| `media_preview` | `sepTa` | `media_preview-light.png` |
| `remote` | `DtZbX` | `remote-light.png` |
| `notifications` | `a7A57` | `notifications-light.png` |
| `notification_reply` | `mVNnf` | `notification_reply-light.png` |
| `calls` | `a05tWj` | `calls-light.png` |
| `background` | `DtBNP` | `background-light.png` |
| `activities` | `mDL3I` | `activities-light.png` |
| `media_cache` | `Q2ZaRT` | `media_cache-light.png` |
| `transfer_details` | `R759qi` | `transfer_details-light.png` |
| `receive_content` | `ERONu` | `receive_content-light.png` |
| `data_preferences` | `XABsw` | `data_preferences-light.png` |
| `document_import` | `MIxzU` | `document_import-light.png` |
| `file_details` | `Z5rvv` | `file_details-light.png` |
| `share_directory_picker` | `FeFSp` | `share_directory_picker-light.png` |
| `devices-tablet` | `H0TFx` | `devices-tablet-light.png` |
| `device_workspace-desktop` | `zLBrM` | `device_workspace-desktop-light.png` |

设备、传输、设置根目的地，以及工作台、手动连接表单通过真实 `ConnectApp`／生产路由捕获；两个大屏case也使用生产路由；其余33项是隔离native依赖的页面夹具，存在对应界面不等于真实设备业务已通过。

手机参考视口为402×874、DPR1、正常文字缩放；`padding`与`viewPadding`均为top54、bottom34。普通主控页以源坐标 `[0,54,402,786]`比较。照片预览与paused远控保留全屏 `[0,0,402,874]`，不套普通安全区裁剪而漏掉边缘控制；系统栏归属单列；remote配对实际paused黑底、暂停卡、退出和导航，不伪造native纹理。手机两侧声明相同38圆角轮廓遮罩。平板1194×834与桌面1440×960采用各自完整视口、圆角遮罩0；当前合同已将安全区设0，并通过真实router仅替换捕获字体，两个大屏布局身份均为production-router，主代理已重看源图；大屏亦纳入本轮40对人工复核，不能沿用手机54／34安全区。源图必须1×导出，不拉伸、补边或自动对齐。

捕获输出包含：

- `capture-contract.json`：视口、安全区、字体、测试渲染后端、设备身份、生产路由范围和逐页场景参数。
- `layout-contract.json`：共享组件与主要控件的实际全局 `[x,y,width,height]`，文字段落边界、行框、字号、字重、行高、字距与溢出；每条关联PNG的SHA-256。
- 明暗页面PNG，以及独立的窄屏／横屏2倍文字变体。响应变体没有对应源Frame时，不纳入正常视口像素比较。

几何来自已完成布局的Element／RenderObject读取，不改变生产控件约束；排除Offstage与非当前路由子树。坐标是裁剪前的源图逻辑像素，文字行框是段落局部坐标。滚动内容边界可能超出视口，`intersectsViewport`不证明实际可见、未遮挡或末项可达。

`fixtureContentDifferences`声明夹具内容差异；源稿同步后应更新已经消除的条目，不将旧说明当作永久豁免。本轮已将相册真实湖边照片、单条通知与回复、画质1920px和三项能力对齐；来电整页也已同步为通话控制可用／主控双向语音受限。最终配置已清除消失的旧元数据、缓存、呼叫和照片差异，仍保留实际后端与夹具限制。不得继续把这些已消除的旧差异列成待修。其余设备元数据、场景参数仍以合同逐项核对。传输详情现在明确使用部分失败且可从头重传的任务，原文件准备保留运行中取消能力。差异会改变行数、内容高度和操作集合，不能把文字不同当作可忽略像素，也不能为了匹配截图伪造状态。未纳入配对的夹具及原因列在配置的 `unmatchedCaptures`，仍须与逐画布表核对；有完整源Frame但尚未配对，与没有源Frame是两种状态。状态板不被伪造成新路由。本次历史捕获中的添加页为无线调试、USB 数据线和 IP 地址连接同卡并列，后续已由统一添加表单替换，见[添加页调整记录](add-device-2026-10-20.md)。`legacy_tcp`仅是保留的捕获 case 标识；实际产品责任见[设备与连接](../../designs/prod/device-connection.md)。

## 可重复操作与报告判读

在`app/`目录捕获：

```sh
rtk proxy env CONNECT_CAPTURE_DIR=/tmp/connect-glass-coverage/flutter \
  flutter test --no-pub test/ios_pages_capture_test.dart
```

通过Pencil对象API将配置中的Frame按 `scale:1`导出到 `/tmp/connect-glass-coverage/pencil/`；禁止按文本解析 `.pen`。同步完成后运行：

```sh
rtk proxy dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-glass-coverage/pencil \
  --flutter-dir /tmp/connect-glass-coverage/flutter \
  --output /tmp/connect-glass-coverage/comparison
```

局部生产分支可在`app/`目录重复捕获，输出不混入40对主页面：

```sh
rtk proxy env CONNECT_CAPTURE_DIR=/tmp/connect-glass-coverage/local-recovery \
  flutter test --no-pub test/local_recovery_capture_test.dart
rtk proxy env CONNECT_CAPTURE_DIR=/tmp/connect-glass-coverage/local-actions \
  flutter test --no-pub test/content_pages_layout_test.dart
rtk proxy env CONNECT_STATE_CAPTURE_DIR=/tmp/connect-glass-coverage/state-boards \
  flutter test --no-pub test/state_boards_capture_test.dart
rtk proxy env CONNECT_CONNECTION_CAPTURE_DIR=/tmp/connect-glass-coverage/connection-states \
  flutter test --no-pub test/connection_states_capture_test.dart
rtk proxy env CONNECT_VIDEO_CAPTURE_DIR=/tmp/connect-glass-coverage/video-controls \
  flutter test --no-pub test/video_preview_test.dart
rtk proxy env CONNECT_CAPTURE_DIR=/tmp/connect-glass-coverage/document-results \
  flutter test --no-pub test/document_results_capture_test.dart
```

工具复用已有Flutter图像codec，生成左Pencil右Flutter的并排图、RGB绝对差图和 `report.json`。缺图、解码失败、源尺寸或比较区域尺寸不匹配均非零退出；已配置case的旧图片先清除。报告记录输入哈希、尺寸、裁剪、内容差异和像素诊断。只有PNG哈希匹配时才附 `flutterLayout`，否则标记 `stale`或 `unavailable`，不冒用旧几何。

扩展工具时的检查点包含当时配置34组同图误差全0、缺图返回1／`missing-input`、尺寸负例返回1／`dimension-mismatch`、陈旧几何标记 `stale`；历史输出身份为 `/tmp/connect-design-v3/tool-selfcheck/result-*`，该临时目录已在本轮清理删除；这些检查只验证工具行为。

`completed=true`只表示所有输入比较完成；`visualAcceptanceComplete`和 `contentAcceptanceComplete`均不自动转为true。平均RGB误差与差异像素比例不设合格阈值，不是还原百分比。人工仍需分别核对边界、对齐、字号、行高、真实内容、安全区、遮挡、滚动终点和主要操作。字体栅格化与光学后端不同不能代替这些检查。

## 本轮透明页头与覆盖层 GPU 证据

`/tmp/connect-glass-coverage/gpu-final/result.json` 的SHA-256为 `111b0a18df1fad9cc49f12e5b553d63c5426954144e7653916ce4682168e7b3b`。Android profile实际运行1分52秒，32场景、37按压样本、60弹层样本及主机严格校验通过。JPEG实际解码为1080×720、201,523字节，SHA-256 `da0c8b0b0daa1510dd18b211451004748781fb0e73b092154cb54b258856efe4`。同一照片随真实滚动位置进入页头背后，标题保护在内容层绘制，不占据固定正文条带。

普通明暗及减少动态下的dialog／sheet／menu／tooltip／feedback使用原生光学路径；降低透明度的对应场景没有Lens、layer或BackdropFilter。初次24图中`menu-reduced-motion`的文字确实缺失，不能因host校验通过登记视觉通过。已通过先红后绿的回归确认：OverlayPortal继承了来源工具组的44px采样范围；菜单与Tooltip现各用独立背景键和本地玻璃平面。32种代表场景已逐张复核；末次实体抽屉下角修复后重新捕获32图，并复看受影响抽屉与提示／反馈。未再见菜单失字、异常裁断或不可读正文；实体与玻璃抽屉均保持上圆角、下直角。工具的 `visualAcceptanceComplete=false` 保持不变。

设备端与主机端场景标记、尺寸及SHA逐项匹配；`gpu-build-receipt.json`核对最终APK生成晚于相关源文件。最后重跑前曾因上一轮测试卸载应用而丢失私有cache照片，该次失败回执保留，未作为视觉证据。重新预装普通debug、复制照片并核对SHA后，使用最终profile包运行。复现时同样先准备私有cache夹具；入口为 `app/integration_test/glass_chrome_test.dart` 与 `tool/driver/glass_chrome.dart`。本轮明确 `performanceMeasured=false`，不重用历史压力测试成绩。

## widgets迁移阶段的运行与性能证据（历史，缺口保留）

此前迁移阶段的GPU根为 `/tmp/connect-glass-widgets-final-private/`，`result.json`的SHA-256为`4fbe04f135bbade8abd8077eb0c8ce36e750093ce1e96b4a46851e5fa335cc74`，记录当时的Android profile、widgets1.13.0、单SDF同材质合成、shader载入及非fallback路径。24张1080×2400截图与两张真实JPEG属于该历史版本，不覆盖本轮PageFrame、覆盖层及按压实现。下文时序和实验均保留原版本身份；其超预算缺口尚未关闭。

独立目视`regular-photo`可见湖景透入并被连续散射，文字清楚；`clear-photo`保留森林照片细节，顶部白控件有生产保护层；`motion-held`显示按压后的圆形控件扩大，`menu-open`显示来自操作区域的菜单及Files选中。另复看clear明／暗可见背景横条沿圆边弯折，白控件处于保护平台内；reduced明／暗均为实体，无背景透入。完整动画的取消、恢复、重按、降低动态效果由同次命令／motionSamples和逐帧场景共同支持，不能只凭这些静态图作时间连续性的推断。runtime已逐张看完同SHA的24图，确认24份图像／bytes／场景marker匹配；59个motion样本与6个导航样本、取消不触发、恢复到原bounds、菜单操作及降低动态效果断言均通过。不将报告布尔值替代人工审阅。

`performance-analysis.log`正式统计如下，预热后的每窗3秒连续诊断Flutter背景，计时内不截图，`nativeSurfaceDuringTiming=true`。这不是远端视频、任意codec或多视频压力测试。

| 场景 | 帧数 | raster p95（ms） | 超16.6666656ms的raster帧 | 结果 |
| --- | --- | --- | --- | --- |
| regular | 148 | 33.582 | 87 | 未通过 |
| clear | 180 | 16.999 | 55 | 未通过 |
| blend | 167 | 29.739 | 118 | 未通过 |
| reduced | 180 | 3.842 | 0 | 通过 |

`performanceAcceptanceComplete=false`保留为本轮已证实的性能缺口；不以更换统计口径、展示24张PNG或降低透明度分支的成绩关闭前三项。

同日继续做了两次未改版本复测和三种独立优化实验，仍使用相同模拟器、premium参数、透镜数量、单SDF与原生表面，每窗3秒且计时内不截图。以下为raster p95，单位ms；原始时序、合同检查及每次报告哈希见 `/tmp/connect-glass-optimize/experiment-summary.json` 和各次 `result.json`。

| 尝试 | regular | clear | blend | reduced |
| --- | --- | --- | --- | --- |
| 未改版本 | 34.242 | 17.162 | 29.345 | 17.216 |
| 未改版本重复 | 35.109 | 17.117 | 29.182 | 3.278 |
| 隔离控件与阴影重绘 | 34.462 | 17.221 | 27.838 | 3.315 |
| 跳过零强度whitening／absorption计算 | 33.063 | 17.354 | 30.561 | 3.715 |
| 保留原SDF／UV的稀疏输出裁剪探针 | 41.158 | 17.233 | 35.071 | 3.385 |

未改版本的实体对照曾出现明显抖动，不能把单次下降当成稳定收益。三种实验均未解决玻璃超预算，稀疏裁剪反而更慢，因此全部撤回，未加入生产或更改视觉规范。着色器和渲染器实验只使用临时依赖副本，不修改全局pub缓存；临时override及副本已删除，锁文件与生产Dart恢复为实验前相同字节，仍使用发布的1.13.0。探针不承担视觉验收，上述24场景证据只对应迁移时版本；不排除其他GPU、后端或更深渲染改造的优化空间。

排查结束后再次构建并恢复普通 `lib/main.dart` debug应用，DTD VM46269热重启成功、运行错误为空；调试进程已detach，应用保留运行。回执为 `/tmp/connect-glass-optimize/ordinary-main.json`。`cleanup.json`记录本次另外回收151,519,824字节（约144.50MiB），删除临时依赖副本、专用编译hash和profile测试包，保留正常应用、五次时序报告及少量探针差异；未重跑未受影响的页面截图或全量测试。

## Pencil静态投影与旧后端历史

v3检查点使用easy5.0.0，其静态shader经文字、细线和照片背景诊断修正；历史输出身份为 `/tmp/connect-design-v3/optics/`，本轮已清理删除；以下路径只保留检查点身份，不作为当前可打开产物。以下记录历史修正，不声明与当前widgets成像相同。当前Glass.optics向新库传入项目厚度、折射、散射与光照参数，映射仍由视觉规范及实现负责。

- 原9点散射在sigma12时产生离散文字重影与重复椭圆；改为确定性的64点Gaussian disk采样。bulk散射强度仍由原token控制，额外采样成本仅是Pencil静态投影成本。
- 原稿把16像素倒角宽度同时当作光线路程。当时分离 `u_refractionWidth`与 `u_opticalDepth`；70像素光线路程镜像easy5.0.0的固定实现，倒角宽度继续只控制边缘带，不声称Flutter可独立配置该值。
- 边缘散射改为连续过渡，着色按相对SDF厚度吸收，中心保留原token着色，边缘显露真实折射背景；没有通过增加白高光、模糊或假阴影制造厚度。

SDF单位、正内侧符号及gb梯度方向已实测符合坐标；背景越界采样在Pencil内镜像，显式LOD-bias第三参数被实际编译器拒绝。相同URL可能继续使用已载入shader缓存；最终诊断用唯一新URL加载与仓库逐字节一致的源码后重拍。`optics/after/A6JKdb.png`、`final-uniform-tint/A6JKdb.png`和 `after-dark/DiWak.png`分别保留最终吸收、同深度但均匀着色、深色投影，不能只以编译成功推断新字节已经成像。

该吸收和散射是静态Pencil投影，Flutter采用当前widgets依赖自身的采样、着色和边缘模型。两侧共享视觉语义和部分光学输入，不因此成为相同后端，更不构成Apple原生等效。

## v3 easy后端GPU历史证据

此前v3在Android运行easy后端harness，物理输出1080×2400、DPR2.625；历史图像路径为 `/tmp/connect-design-v3/gpu/`，该临时目录本轮已清理删除，不证明当前widgets后端。`gpu/result.json`记录shader支持与程序加载，`liteGlassEnabled=false`；regular每景4个Lens、clear每景2个Lens，均无Lite或BackdropFilter Widget。降低透明度三景的Lens／Lite／BackdropFilter均为0。以下结论来自逐张查看PNG，而非仅转述hostValidation。

| 图（`gpu/`） | 实际看到的内容 | 限制／结论 |
| --- | --- | --- |
| `regular-light.png` | 背景黑白格透成连续灰色散射，面板正文、图标和导航可读，轮廓完整 | 折射辨识弱于clear，细边和阴影不单独证明透镜厚度 |
| `regular-light-pressed.png` | 橙色调试指针十字、圆圈和“Close test control”提示可见 | 静态图不能分离并证明按压形变、回弹或动态高光 |
| `regular-light-scrolled.png` | 背景数字已移动，面板／导航位置稳定，Files选中，正文清楚 | 背景具周期性，前后两帧不能独立证明持续逐帧追踪 |
| `regular-dark.png` | 白色正文清楚，背景散射更弱，深色表面较均匀，无异常色块或截断 | 未证明与新Pencil透明边缘的成像一致 |
| `clear-bright.png` | 左上圆形内蓝横条明显重排、收缩与弯曲，提供实际折射证据 | 右侧白图标在浅黄背景上对比偏弱；裸材料夹具不能代替生产媒体页局部保护检查 |
| `clear-dark.png` | 左上蓝条折射与背景透入可见，白色图标清楚 | 右工具组处于均匀背景，单凭该区域难判断折射强度 |
| `reduced-light.png` | 白色实体面、明确边界，无背景透入，正文清楚 | 符合该降低透明度静态分支 |
| `reduced-light-scrolled.png` | 背景滚动后实体面仍不透，文字和控件稳定，无残留玻璃纹理 | 不扩展为所有辅助偏好与所有页面已验收 |
| `reduced-dark.png` | 深色实体面和白字清楚，边界明确，无背景透入或光学残影 | 符合该降低透明度静态分支 |

报告还记录取消不激活、取消后再次点击、工具组、导航选择和滚动后点击等harness交互结果。它们与9张静态图共同提供特定Android材料夹具的运行证据，不能替代真实产品页面、任意远端应用和长时间视频验证。新库的有限光学／动态／性能条件由上表E–G另取证据；Apple等效及任意设备多视频全矩阵不是本轮完成条件。
