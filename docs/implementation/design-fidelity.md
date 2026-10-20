# 设计稿与 Flutter 核对

视觉数值归[视觉规范](../../designs/design.md)，页面入口与行为归[产品规格](../../designs/prod/README.md)。本文维护源稿/实现的查找方式、捕获契约和已执行证据的限制，不复制逐页规则或另一份画布清单。

## 源稿与实现定位

`designs/mobile.pen` 是唯一源稿，须通过 Pencil MCP 或 `pen interactive` 对象 API 读取/修改，不按文本解析。代表状态从[用户流程](../../designs/prod/user-flows.md)定位，当前截图配对由[pages.json](../../tool/visual_parity/pages.json)维护；源码入口以[路由契约](flutter-navigation.md)为准。

添加页的配对码/扫码/USB/IP代表稿属于同一表单，帮助、字段错误及系统授权示意是局部状态。工作台承接设备信息与管理，旧独立设备详情/手动无线地址页面已被合并。画布数、Frame数、源码页数和路由数不能相互推导。旧审计的独立页面表及截图配对不再作为当前入口证据。

母组件与受影响实例一并检查；完整手机、系统界面示意、局部状态及大屏分别定位。稿件分区/行列和标注颜色属于源稿组织，不能代替页面实际布局或新增产品路由。2026-10-20的代表稿核对包括统一表单、工作台四态、手机轮廓内状态图标、私钥导入/确认/不可用恢复、单设备活动及传输移除，当前逻辑验证见[验证记录](validation.md#2026-10-20-设备工作台与连接管理)。

以下保留2026-10-20调整中容易混淆的定位关系；完整业务路径仍由用户流程/覆盖表负责，不据此新增规则。

| 核对对象 | 源稿定位 | 实现/验证入口 |
| --- | --- | --- |
| 设备四态、手机内状态图标、轮廓右侧设备信息 | `RTx0Z/uESR9/N5P7M`、`y5TL9/aozX4`；状态实例 `yseUT/Ok1ty/mNfsm` 与 `XYB3Y/i1Irz/darW7/mNfsm` | `devices/widgets/device_identity.dart`、`device_status.dart`、`workspace/index/widgets/device_facts.dart` |
| 工作台整合、快捷移除与离线动作 | `nqQEb/m0AlTk`、`PxnBS/Txxv0/KcWEm` | `devices/workspace/index/`、`devices/widgets/device_access.dart`；保存设备均可进入同一工作台 |
| 活跃应用与目标图标 | `U1FJF/VacW7/OApmp`，受限态`lYdIf` | `running_apps.dart`、Core `apps.list(filter:running)` / `apps.icon`；API29及任务读取权限条件见兼容文档，不用安装列表或主控图标填充 |
| 四形式表单与发现二级页 | 外壳`JORmP`、Tab`igSfI`、`W3GRn/G4CpTk/OxUaB/OpFKk`、`yMlVd` | `connection/form/`与`connection/discovery/`；发现回填及配对后TLS补端口有独立回归 |
| 密钥输入、三种替换确认与不可用恢复 | `nzitC/x7ZjT`、`s3Fdhr/bcFd3/B5nGcj/AXigJ`；全局重置`Rz6jL` | `settings_adb_identity_page.dart` / `adb_identity_validation.dart` / `host_identity.rs`；取消不更改身份，恢复继承需明确确认 |
| 扫码设备归属与转IP失败保护 | `G4CpTk`、`XszXp/gHHmj/vPWPs` | `device.rs`扫码贯通原deviceId与所选身份；`tcpip.rs`目标核验后原子提交，失败/取消保留原method/address/port/GUID |
| 传输历史与单设备活动 | `W6enLf/R759qi/fKBPB`、`mDL3I` | `transfer_history_row.dart`、`files.rs`及设备`activities/`；活动先停止，移除记录不删保存文件 |
| 底栏原版镜片与无固定描边 | 母`Ffm0s`、材料/交互板`N70xWl`，明暗按压/拖动集中对照 | `home_page.dart` / `GlassMaterial.navigationLensSettings`；沿用上游合成能力，运行证据见玻璃记录 |
| 画布组织与标注 | `KTHuP/B3uE9/w4TjN`；共享板`Rie7E/TfjoF` | 此轮完整屏幕按类型每行至多8张，局部板容量5项，尾行分别5/5/3和5/5/1；中灰标注使用canvas-label，未改产品文字语义 |

## 静态布局核查

每个受影响页面分别检查明暗、降低透明度、长标题、窄容器、大字、安全区和必要的横屏/键盘状态。普通内容按父约束流式布局；远控画面和浮动控制才承担叠加关系。滚动视口内裁剪必须确认完整末项可达，其他活动分支不能用“设计裁剪”掩盖溢出。

结构扫描证明引用与几何边界，目视说明文字/材料/层级；二者各有作用。2026-10-20对象扫描核对了新增确认及恢复态、相关母组件和展开实例，未发现活动分支非预期裁切或悬空引用。该检查不是 Flutter GPU 或两设备授权验收。

页头保护层在正文内容层绘制，并止于实际标题栏底部。滚动内容消费相应避让，透明栏后方仍保留真实滚动背景；对齐、安全区与末项可达分别由布局测试核对。大屏使用侧栏和单一当前内容区，不把早期并行示意登记为已有原生多窗口能力。

## 配对与捕获契约

配对配置记录每个case的源Frame、截图名、裁剪、视口、内容差异及生产路由/隔离夹具身份，不在本文抄录易失效列表。没有完整Frame和已有Frame但未配对是不同状态；`unmatchedCaptures`保留原因，局部状态不拉伸成整页。

手机参考402×874/DPR1，常态安全区top54/bottom34，普通主控内容按配置裁剪。照片预览与远控保留全屏，不能用常规裁剪漏掉边缘操作；远控黑底暂停夹具不冒充远端native纹理。平板1194×834、桌面1440×960使用各自完整视口和零安全区，不缩放手机稿。最终数值以每次捕获合同和配置为准。

- `capture-contract.json`：视口、安全区、字体、渲染后端、设备/场景和生产路由范围。
- `layout-contract.json`：RenderObject的全局几何、文字行框与字号/行高/字距/溢出，绑定PNG的SHA-256；排除Offstage和非当前路由。
- 明暗及响应变体PNG；没有相同源视口的变体不混进正常视口像素比较。

几何坐标不能单独证明未遮挡；`intersectsViewport`不证明主要动作可达。夹具的设备/通知/文件状态按实际合同核对，内容差异会改变行数和动作集合，不能因“仅文字不同”一概忽略，也不能伪造状态匹配图片。

## 可重复操作与报告判读

从 `app/` 捕获 `test/ios_pages_capture_test.dart`，设置新的 `CONNECT_CAPTURE_DIR`。局部状态另用 `local_recovery_capture_test.dart`、`content_pages_layout_test.dart`、`state_boards_capture_test.dart`、`connection_states_capture_test.dart`、`video_preview_test.dart` 和 `document_results_capture_test.dart`，各入口的输出变量以测试声明为准。

经对象API将配置中Frame按1×导出后，从仓库根运行：

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir <本次源稿导出目录> \
  --flutter-dir <本次Flutter捕获目录> \
  --output <新的比较目录>
```

工具生成并排图、RGB差图和报告；缺图、解码失败、源尺寸/比较区域不匹配均失败，只有PNG哈希匹配才附几何，否则标记stale/unavailable。源图不得拉伸、补边或自动对齐。

`completed=true`只说明比较完成，RGB均值或差异像素比例没有自动合格阈值。`visualAcceptanceComplete`和`contentAcceptanceComplete`不自动变真；人工仍核对对齐、字级、真实内容、安全区、遮挡和滚动终点。

## GPU与动态证据

2026-10-19透明页头/覆盖层样本使用API36 x64、Impeller OpenGLES和当时Zink/Intel配置，实际JPEG滚入页头背后；明暗、减少动态、降低透明度下的弹窗/抽屉/菜单/提示/反馈分别捕获。输入哈希和像素标记证明产物身份，不能签发人工视觉通过。

该轮OverlayPortal继承来源工具组44px采样范围，实际截图出现菜单失字；独立本地采样层修复后重捕并目视。有限按压/取消/恢复与弹层矩阵检查通过，降低透明度时无光学面/模糊。入口仍为 `app/integration_test/glass_chrome_test.dart` 与 `tool/driver/glass_chrome.dart`，照片夹具在设备上准备并核验后才捕获。

2026-10-20采用上游原版控件的运行环境、模拟器崩溃规避及新GPU样本见[玻璃运行记录](glass-components-2026-10-20.md)。旧easy后端的散射/静态shader与GPU图片不覆盖现有widgets；Pencil投影和Flutter运行库并非相同后端，也不证明Apple原生等效。

## 性能与未验范围

widgets迁移阶段的诊断背景压力样本中，regular/clear/blend/reduced约33.582/16.999/29.739/3.842ms，前三项超过16.6667ms预算。后续成像捕获没有重测该性能场景，不能以“GPU截图通过”关闭缺口。

历史优化探针只在临时依赖副本运行，未把实验修改带入发布包；它们缩小了材料层成本范围，没有证明所有GPU、连续手感、多路真实视频、读屏或四宿主性能通过。当前样本的`visualAcceptanceComplete=false`/`performanceMeasured=false`保留原义；有限人工目视和工具回执分别记录，不能互相替代。
