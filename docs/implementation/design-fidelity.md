# 设计稿与 Flutter 对照（2026-10-19，v3）

本轮截图配置为40对：原34对、补齐4个手机主帧、增加2个大屏。最终40组已完成比较并全部关联同图布局；**这不表示40页像素还原通过**。本记录替换旧v2结果的当前状态表述，保留最终输入、逐图观察和未验证边界；历史截图不作为本轮最终验收。

视觉数值由[视觉规范](../../designs/design.md)负责，产品行为由[产品规格](../../designs/prod/README.md)负责，页面与状态对应见[流程索引](../../designs/prod/user-flows.md)。本文件只记录这次实施与证据，不另设规范。41个主要画布与13个状态板的逐项发现见[画布审核表](canvas-audit-2026-10-19.md)；旧版本记录保留在[iOS视觉审计](ios-visual-audit.md)。

## 当前证据与封版条件

| 对象 | 已有证据 | 当前边界 |
| --- | --- | --- |
| 40对配置与最终源图 | [pages.json](../../tool/visual_parity/pages.json)声明配对、裁剪与夹具差异；41主帧于09:29:10Z重导至 `pencil-final/` | 配对数量不是还原通过数量；独立应用示意未配对 |
| Flutter页面捕获 | `flutter/capture-contract.json`时间 `2026-10-19T09:27:15.004025Z`；100张PNG、94项布局，94项PNG／布局SHA-256全部匹配 | Widget测试使用材料fallback；两个大屏为安全区0、仅替换捕获字体的生产router |
| 最终比较 | `comparison/report.json`时间 `2026-10-19T09:29:42.262279Z`；40/40为 `compared`，40/40布局为 `associated` | `completed=true`，`visualAcceptanceComplete=false`，40项内容验收均未自动完成 |
| 逐图复核 | 20个手机主帧已逐对看新密度版本，最终6个受影响页面又复核；主代理另逐张看21个源主帧，包括远控／独立应用及两个大屏 | 21个源图观察不等于21组双侧逐像素验收；小幅文字、图标和列位置差异仍保留 |
| 13个状态板 | `boards-final/`于09:27:04Z导出，13/13有逐图回执；TfjoF于09:29:23Z重导后另已查看 | 静态片段不验证业务、系统授权、手势或播放 |
| 应用／设计系统测试 | `app-tests-final.log`为345项、`design-system-tests-final.log`为15项通过；搜索选项最后改动后另有12项定向通过 | 345项是全量检查点，12项是其后改动的定向回归；不合并计作357项全量测试 |
| 分析／Token／lint | `analyze-final.log`记录app与design_system无问题；生成器4项通过；最终token漂移检查与官方lint均0错误、64警告 | 警告涉及现有光学／布局扩展与孤立颜色；没有通过放宽错误消除警告 |
| 源稿结构检查 | 主代理遍历41主画布，排除禁用和预期滚动视口裁切后，unexpected problems为0；41主帧及13板的“旧版／TCP／现代无线”用户可见文案均为0 | 结构与文案扫描不证明像素相同，也不等于所有滚动终点或命中区域验证 |
| Android光学捕获 | `gpu/result.json`与9张PNG；`gpu-run.log`记录实际shader harness通过，9图已逐张目视 | 独立材料夹具，不是41页产品运行、原生等效或性能验收 |
| 普通应用恢复 | 主代理确认普通应用已恢复、热重载完成；DTD连接后的 `get_runtime_errors`无错误 | 不扩展为真实设备连接、远端纹理或设备业务已验收 |

证据根目录为 `/tmp/connect-design-v3/`。最终比较报告SHA-256为 `cfddc91c977d5fa8f25ef4e57a9ba1c6beec07bfb9d4efb5fbb71a607bec6df1`；报告逐case保留两侧输入SHA-256及布局身份。此前 `comparison-toolcheck/report.json`的08:24:44Z、34组结果只作为工具检查历史，不混入最终40组结论。最终导出后的六页复核为文件管理、当前活动、传输详情、画质、文件搜索与手机应用；其他14页的双侧目视来自09:26:09Z源图／09:22:14Z捕获检查点，最终报告关联的是更新后的输入，不能把两者称为同一批最终逐图验收。详细已修、受限与较小差异见[画布审核表](canvas-audit-2026-10-19.md)。完整像素、动态及设备业务验收仍未完成。

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

手机参考视口为402×874、DPR1、正常文字缩放；`padding`与`viewPadding`均为top54、bottom34。普通主控页以源坐标 `[0,54,402,786]`比较。照片预览与远控保留全屏 `[0,0,402,874]`，不套普通安全区裁剪而漏掉边缘控制；这两类源图中的系统栏／远端示意与Flutter不绘制的系统内容需另行判读。手机两侧声明相同38圆角轮廓遮罩。平板1194×834与桌面1440×960采用各自完整视口、圆角遮罩0；当前合同已将安全区设0，并通过真实router仅替换捕获字体，两个大屏布局身份均为production-router，主代理已重看源图；本记录未单独复看大屏双侧，不能沿用手机54／34安全区。源图必须1×导出，不拉伸、补边或自动对齐。

捕获输出包含：

- `capture-contract.json`：视口、安全区、字体、测试渲染后端、设备身份、生产路由范围和逐页场景参数。
- `layout-contract.json`：共享组件与主要控件的实际全局 `[x,y,width,height]`，文字段落边界、行框、字号、字重、行高、字距与溢出；每条关联PNG的SHA-256。
- 明暗页面PNG，以及独立的窄屏／横屏2倍文字变体。响应变体没有对应源Frame时，不纳入正常视口像素比较。

几何来自已完成布局的Element／RenderObject读取，不改变生产控件约束；排除Offstage与非当前路由子树。坐标是裁剪前的源图逻辑像素，文字行框是段落局部坐标。滚动内容边界可能超出视口，`intersectsViewport`不证明实际可见、未遮挡或末项可达。

`fixtureContentDifferences`声明夹具内容差异；源稿同步后应更新已经消除的条目，不将旧说明当作永久豁免。本轮已将相册真实湖边照片、单条通知与回复、画质1920px和三项能力对齐；来电整页也已同步为通话控制可用／主控双向语音受限。最终配置已清除消失的旧元数据、缓存、呼叫和照片差异，仍保留实际后端与夹具限制。不得继续把这些已消除的旧差异列成待修。其余设备元数据、场景参数仍以合同逐项核对。传输详情现在明确使用部分失败且可从头重传的任务，原文件准备保留运行中取消能力。差异会改变行数、内容高度和操作集合，不能把文字不同当作可忽略像素，也不能为了匹配截图伪造状态。未纳入配对的夹具及原因列在配置的 `unmatchedCaptures`，仍须与逐画布表核对；有完整源Frame但尚未配对，与没有源Frame是两种状态。状态板不被伪造成新路由。添加页现为无线调试、USB数据线和IP地址连接同卡并列；IP页不使用“旧版”或协议标签，`legacy_tcp`仅是保留的捕获case标识。无线引导只保留配对步骤与USB恢复，不另列IP入口；实际产品责任见[设备与连接](../../designs/prod/device-connection.md)。

## 可重复操作与报告判读

从仓库根捕获：

```sh
(cd app && CONNECT_CAPTURE_DIR=/tmp/connect-design-v3/flutter \
  flutter test --no-pub test/ios_pages_capture_test.dart)
```

通过Pencil对象API将配置中的Frame按 `scale:1`导出到 `/tmp/connect-design-v3/pencil-final/`；禁止按文本解析 `.pen`。同步完成后运行：

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir /tmp/connect-design-v3/pencil-final \
  --flutter-dir /tmp/connect-design-v3/flutter \
  --output /tmp/connect-design-v3/comparison
```

工具复用已有Flutter图像codec，生成左Pencil右Flutter的并排图、RGB绝对差图和 `report.json`。缺图、解码失败、源尺寸或比较区域尺寸不匹配均非零退出；已配置case的旧图片先清除。报告记录输入哈希、尺寸、裁剪、内容差异和像素诊断。只有PNG哈希匹配时才附 `flutterLayout`，否则标记 `stale`或 `unavailable`，不冒用旧几何。

扩展工具时的检查点包含当时配置34组同图误差全0、缺图返回1／`missing-input`、尺寸负例返回1／`dimension-mismatch`、陈旧几何标记 `stale`；证据位于 `tool-selfcheck/result-*`。这些只验证工具行为。

`completed=true`只表示所有输入比较完成；`visualAcceptanceComplete`和 `contentAcceptanceComplete`均不自动转为true。平均RGB误差与差异像素比例不设合格阈值，不是还原百分比。人工仍需分别核对边界、对齐、字号、行高、真实内容、安全区、遮挡、滚动终点和主要操作。字体栅格化与光学后端不同不能代替这些检查。

## Pencil光学修正

本轮未换库，Flutter继续使用受控依赖 `liquid_glass_easy 5.0.0`。Pencil静态shader通过实际文字、1px细线和仓库照片背景诊断后修正，证据在 `optics/README.md`、`optics/diagnosis.json`及同目录图片。

- 原9点散射在sigma12时产生离散文字重影与重复椭圆；改为确定性的64点Gaussian disk采样。bulk散射强度仍由原token控制，额外采样成本仅是Pencil静态投影成本。
- 原稿把16像素倒角宽度同时当作光线路程。现在分离 `u_refractionWidth`与 `u_opticalDepth`；70像素光线路程镜像受控依赖的固定实现，倒角宽度继续只控制边缘带，不声称Flutter可独立配置该值。
- 边缘散射改为连续过渡，着色按相对SDF厚度吸收，中心保留原token着色，边缘显露真实折射背景；没有通过增加白高光、模糊或假阴影制造厚度。

SDF单位、正内侧符号及gb梯度方向已实测符合坐标；背景越界采样在Pencil内镜像，显式LOD-bias第三参数被实际编译器拒绝。相同URL可能继续使用已载入shader缓存；最终诊断用唯一新URL加载与仓库逐字节一致的源码后重拍。`optics/after/A6JKdb.png`、`final-uniform-tint/A6JKdb.png`和 `after-dark/DiWak.png`分别保留最终吸收、同深度但均匀着色、深色投影，不能只以编译成功推断新字节已经成像。

该吸收和散射是静态Pencil投影，Flutter仍采用其依赖自身的采样、着色和边缘模型。两侧共享视觉语义和部分光学输入，不因此成为相同后端，更不构成Apple原生等效。

## 当前Android GPU逐图复核

本轮在Android实际运行材料harness，物理输出1080×2400、DPR2.625。`gpu/result.json`记录shader支持与程序加载，`liteGlassEnabled=false`；regular每景4个Lens、clear每景2个Lens，均无Lite或BackdropFilter Widget。降低透明度三景的Lens／Lite／BackdropFilter均为0。以下结论来自逐张查看PNG，而非仅转述hostValidation。

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

报告还记录取消不激活、取消后再次点击、工具组、导航选择和滚动后点击等harness交互结果。它们与9张静态图共同提供特定Android材料夹具的运行证据，不能替代真实产品页面、任意远端应用和长时间视频验证。背景自适应阴影／对比、连续动态与可打断形变、来源过渡、减少动态与读屏、多视频成本及Apple原生等效仍未由本组证据关闭。
