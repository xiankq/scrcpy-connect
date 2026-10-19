# 逐画布审核记录（2026-10-19，玻璃覆盖优化）

这是本轮最终输入及分层复核记录，不是41个主要画布、13个状态板全部像素或业务通过的声明。视觉规范仍由[design.md](../../designs/design.md)负责，产品行为见[产品规格](../../designs/prod/README.md)；捕获与GPU边界见[对照记录](design-fidelity.md)。

本轮通过Pencil对象API修改并保存源稿，仍为41个主要画布（39个402×874手机画布、2个大屏）、13个状态板及60个局部状态。`DYMK6`设计入口、`V6QGx4`材料与交互板、`F1jCz`共享组件区另列。36个普通手机页的滚动视口延伸至透明页头背后，首屏避让属于滚动内容；两个大屏同步阅读列及标题保护。照片预览、远控及独立应用三种沉浸页保留各自画面归属。未按文本读写 `.pen`；对象清点不代替视觉或运行验证。

## 状态与证据身份

- **已修**：有明确改动及所列检查点的目视回执；不能扩大为所有状态、像素和业务通过。
- **待核**：本轮最终实例／截图／人工结论尚未关闭，不等于已经确认有缺陷，也不等于没有缺陷。
- **受限**：现有夹具／配对／静态示意无法给出同状态的一对一结论，需先解决条件或另取证据。

当前证据根为 `/tmp/connect-glass-coverage/`：100张Flutter页面、70张local-actions、20张local-recovery、12张state-boards，共202张静态PNG；另有32张实际GPU图。100页面逐张复看，窄屏滚动标题叠字、目录路径被页头覆盖、短横屏首卡遮挡和设备名称说明截断已修复重捕。主捕获 `2026-10-19T13:20:48.118446Z`；94布局PNG哈希全部匹配。40对比较时间 `2026-10-19T13:24:42.865769Z`、SHA-256 `5233c6ea540a7e5fbc95bed33a86e9ab3d59911f9ea758b11043a992fc096bc0`，40 compared／40 associated及80输入哈希独立复核一致。41主帧、13状态板与材料板已重导；源稿保存后关闭headless会话。

13板的既有内容投影与逐张复核属于此前v4基础证据；本轮同步共享玻璃弹窗、抽屉及恢复材料，并重投影实际资源不足面板和相册范围抽屉。设备名称弹窗322宽、227高，归属说明移至输入框上方并允许换行；`UwGyp`保留实际785.2高抽屉内容，所在状态框450宽，避免把整片抽屉压入旧窄框。原状态ID保留，不新增路由。最终GPU人工复核结果见[对照记录](design-fidelity.md#本轮透明页头与覆盖层-gpu-证据)；初次reduced-menu失字已证实并修复，不能从host布尔值推断视觉通过。

此前v4、v3及easy后端回执保留历史身份。下表保留逐页的内容核验基础；所有36个普通手机页和两个大屏另统一完成透明页头、完整滚动视口及标题保护，不能把旧静态内容核验扩大为本轮GPU或业务验证。纯列表父padding0、亮色小圆角白图标和无多余末线继续保留；此前性能超预算仍未关闭。

## 主要画布（41）

“配对case”来自当前[pages.json](../../tool/visual_parity/pages.json)。当前配置40对，覆盖38个手机主帧和2个大屏；独立应用示意仍单列受限。下表的检查项是本轮责任记录，不另设视觉数值。

| Frame | 页面 | 配对case | 本轮发现／下一步 | 当前状态 |
| --- | --- | --- | --- | --- |
| `lUDPa` | 设备列表 | `devices` | v4双侧设备身份、108卡、名称／状态／动作层级已逐图核对；非实时设备事实不扩大为协议通过。 | 主控内容／几何已核 |
| `W3GRn` | 添加设备 | `add_device` | 三种连接方式同卡并列、三行168已逐对看；IP入口与无线／USB同级。 | 入口及密度已修已核 |
| `c0wxY` | 开启无线调试 | `wireless_guide` | 步骤与USB恢复已逐对看；蓝色FeatureIcon按实际primary alpha.1叠canvas投影、序号body400同步，修后复看关闭旧色底差。 | 内容／alpha已修已核 |
| `XQZRD` | 使用配对码 | `pairing_form` | 正常态输入字段与动作已逐对看；源按真实InputDecorator内部20缩进及helper位置投影，修后复看。失败清空配对码等另列FCb8o，不混为正常态。 | 正常态已修已核 |
| `OxUaB` | USB连接 | `usb_guide` | 主控USB访问与被控调试授权两端说明、正文及操作行已逐对看；feature底按alpha投影。系统弹窗保持系统归属。 | 主控内容／几何已核 |
| `nqQEb` | 设备工作台 | `device_workspace` | 设备实体、能力与会话摘要、主动作和功能分组已逐对看；真实设备能力执行与静态内容分列。 | 主控内容／几何已核 |
| `tbWkA` | 手机应用 | `apps` | 三行内容及168密度保留；本轮搜索与列表共用嵌套滚动避让，打开方式抽屉使用共享玻璃入口。真实应用图标仍归被控内容。 | 搜索／内容滚动与抽屉已核 |
| `aVxBi` | 独立应用·移动端全屏 | 未纳入40对 | 主代理已看完整源帧，未纳入40对；原应用画面是远端内容，不由主控主题重绘。 | 源图已看；未配对受限 |
| `iEvoR` | 窗口切换 | `sessions` | 新密度版本已逐对看单手机屏幕会话，白卡100高且标题／工具／关闭对应；旧132及348观察均不用于最终几何。 | 密度已修已看 |
| `MaHXL` | 文件管理 | `files` | 56行密度与尾列保留；本轮路径和列表共用嵌套滚动避让，菜单迁至GlassMenuButton并保留行为。 | 路径／菜单／密度已核 |
| `W6enLf` | 传输中心 | `transfers` | 已同步并逐对看单一旅行照片任务、我的手机→本机暂存、14.9/22.9MB和进度；旧完成列表／项目数差异已消除。 | 已修已看；无新裁剪 |
| `RqDYL` | 手机相册 | `gallery` | 已逐对看1/1摘要、计数与范围同行、真实湖边照片和118缩略图；内容与主要位置对应。 | 已修已看 |
| `sepTa` | 照片预览 | `media_preview` | 已逐对看相同湖边.jpg、真实湖景比例、全屏黑底和返回／取回／分享位置；旧森林差异已消除，Widget材料仍是fallback。 | 已修已看；光学受限 |
| `a7A57` | 实时通知 | `notifications` | 已逐对看单条信息通知、小林正文和行内打开／快捷回复；主要位置对应，无新动作溢出。 | 已修已看 |
| `mVNnf` | 快捷回复 | `notification_reply` | 已逐对看真实通知、112高空编辑器、0/16384、发送及核验说明；无伪造草稿，主要边界对应。 | 已修已看 |
| `NVEMy` | 设备能力 | `capabilities` | 已逐对看三项能力及设备声音受限原因，刷新动作对应；旧五项能力库存差异已消除。 | 已修已看 |
| `w6WUAT` | 设置 | `settings` | 纯列表父padding0、行内16后的56／112密度、根标题、分组及无多余末线已逐对看，旧用户截图留白问题关闭。 | 密度已修已核 |
| `DtZbX` | 全屏整机控制·暂停代表状态 | `remote` | 黑底与真实paused内容保留；本轮暂停／恢复及相关失败面板统一regular玻璃，退出及导航继续悬浮。未伪造远端Texture。 | 主控恢复材料已同步；live内容不比较 |
| `DtBNP` | 后台与连接 | `background` | 后台状态正文已左对齐并有实际x32回归，off开关按muted同步；双侧内容与几何已复看。系统权限执行不纳入静态UI结论。 | 对齐／开关已修已核 |
| `H0TFx` | 平板设备列表 | `devices-tablet` | 1194×834安全区0的生产router已逐对看；sidebar顶16到底818全高、设备列表与主要位置对应，旧居中短栏问题关闭。 | 大屏几何已修已核 |
| `zLBrM` | 桌面设备工作台 | `device_workspace-desktop` | 1440×960安全区0的生产router已逐对看；720阅读列、hero／列表／首屏滚动裁切对应，不以手机缩放替代大屏。 | 大屏几何已核 |
| `a05tWj` | 来电与通话（受限夹具） | `calls` | 已逐对看通话控制可用／主控双向语音受限、小林来电、接听／拒接与手机继续；旧音频状态不一致已关闭。 | 已修已看；通话执行受限 |
| `TMxVJ` | 设备详情 | `device_details` | 实际元数据值通过Expanded占尾列，右edge386回归通过，双侧已复看；旧值停中列问题关闭。 | 尾列已修已核 |
| `q3bM72` | 连接方式 | `device_connection_preferences` | 3×56连接偏好与必要说明已逐对看；保存仅当前设备的语义由preferences_ui回归，执行结果不由PNG推定。 | 主控内容／几何已核 |
| `eWu3m` | 连接诊断 | `diagnostics_failed` | 固定离线／TCP不可达／身份保留的失败夹具已逐对看，恢复动作与原因对应；未混配成功诊断。 | 同状态配对已核 |
| `yMlVd` | 附近设备 | `discovery` | 普通发现列表已逐对看，单行56对应；另补discovery_empty四恢复入口实现、路由及窄屏明暗证据，局部源投影见c1sOp。 | 正常态已核；空态另列 |
| `YvzMk` | 手动连接 | `connection_form` | 生产router字段／正文／动作已逐对看；最后源按真实InputDecorator修正内部20缩进，最终重导双侧已复看。 | 正常态已修已核 |
| `G4CpTk` | 扫码配对 | `qr_pair` | 有效黑码150、容器含静区176；固定payload／L的25×25模块中心625点直接采样差0，转置差214；并排栅格疑点已排除，不转置。 | 尺寸／实际矩阵已核 |
| `R759qi` | 传输详情 | `transfer_details` | 最终复看部分完成、一个完成／两个失败与从头重传；说明已逐字同步为重新检查同名内容，旧措辞差异关闭，无新裁剪。 | 文案已修已看 |
| `XPceX` | 画质细项 | `quality` | 最终复看三个预设和1920px／60fps／8Mbps／H.264／自动；父面裁切已使预设圆角对应，末尾说明在首屏完整可见，旧截断观察关闭。 | 圆角及密度已修已看 |
| `mDL3I` | 当前活动 | `activities` | 最终复看两项活动与停止动作；源尾部改48宽居中后与真实TextButton对应，旧约11px尾部差异关闭，无新裁剪。 | 对齐已修已看 |
| `PLzIA` | 外观 | `appearance` | 三项28蓝badge及文字x72已同步；最后跟随系统从sunMoon改为实际monitor，11:02报告对应新图已复看。全应用偏好另列GPU。 | leading／字形已修已核 |
| `XvviW` | 屏幕与输入工具 | `selected_session_tools` | 新密度版本已逐对看：三键74／87／100与源对应，截图／实体屏／键盘及发送文字行无新裁剪，旧均分三键差异关闭。 | 宽度及密度已修已看 |
| `ERONu` | 原文件准备中 | `receive_content` | 已逐对看旅行照片、我的手机→本机暂存、14.9/22.9MB、取消及详情／重核入口；运行中取消保留，主要位置对应。 | 已修已看 |
| `lm0us` | 搜索子文件夹 | `file_search` | 44高、185等分选段、唯一白色选中项、搜索字段与真实EmptyContent已逐对看；最后helper源投影更新后已核对最终输入身份。 | 选段／正常态已修已核 |
| `Q2ZaRT` | 媒体暂存 | `media_cache` | 已逐对看已用534.1MB／预算1907.3MB、保护114.4／回收419.6／准备22.9MB及清理说明；旧数值差异已消除，未见按钮溢出。 | 已修已看 |
| `OpFKk` | IP地址连接 | `legacy_tcp` | 从添加页进入IP地址连接，无用户可见旧版／协议标签；真实字段x36、已填端口label／value及helper20缩进已按InputDecorator投影并复看。 | 字段／文案已修已核 |
| `XABsw` | 设备记录与恢复 | `data_preferences` | 完整页面配对已逐对看：授权身份说明、两条本机记录入口及移除说明对应；不把系统恢复执行作为像素条件。 | 主控内容／几何已核 |
| `FeFSp` | 选择目标目录 | `share_directory_picker` | 修复路径行落在透明页头后方的问题；路径与列表进入同一NestedScrollView，/sdcard、Download、上一级和选择动作保持可达，明暗重捕复看。 | 路径遮挡已修已核 |
| `Z5rvv` | 文件详情 | `file_details` | 已补配对并逐对看72对象区、文件名／PDF／2.4MB／完整路径及44取回／分享动作；无新裁剪。 | 已补已修已看 |
| `MIxzU` | 发送本机文件夹 | `document_import` | 已补配对并逐对看选择系统文件夹、临时暂存与核对后发送说明；主要内容和44动作位置对应。 | 已补已看 |

“已看”仅覆盖当前截图明确呈现的内容和几何；40对没有以字体、图标或fallback光学栅格差异判为像素通过。普通ActionRow／ChoiceRow自动分隔已移除；必要文件／通知数据分隔单独保留。大屏须以各自父约束和视口验证，不能缩放手机截图凑尺寸。

## 局部状态板（13）

以下责任主帧和局部ID保留此前v4内容核验索引；本轮共享母组件及实际投影差异就地更新。纯行父卡、行内缩进和末行无分隔保持，正文与对象卡保留内容间距。局部状态不按数量建设新路由；40对完整页面截图不自动覆盖这些状态。

| 状态板 | 分组 | 责任主帧 | 保留局部ID | 复核项 | 当前状态 |
| --- | --- | --- | --- | --- | --- |
| `caN7i` | 设备列表 | `lUDPa` | tSC6u、HvaW2、oHSUW、lj24R | 新板居中EmptyContent／搜索无结果／offline StateNote及108卡已对应，离线副标题窄框已改单行；checking搜索下方indeterminate细进度轨迹已补并复看。 | 主体／loading已修已核 |
| `c1sOp` | 添加与发现 | `yMlVd` | h5JZfa | 四恢复入口真实实现和phone／narrow2x明暗已捕获；新板28badge正确，两ActionRow尾chevron已用固定文字约束保持统一右缘，最终板已复看。 | 入口／尾对齐已修已核 |
| `FEiWw` | 文件与传输 | `ERONu` | K950NO、wLQoJ、aVAri、x4cTCx、VZ4BH、Y0LpW、uhuiJ、Gfe22、mcRQa、vSjZS、pSoci、cdQol、jcZXq、zD1BI、HwqEs | 同名冲突inline内容卡、trailing圆形checkbox与3个TextButton，及rename／delete真实对话框已重投影复看。HwqEs为保存前初态。保存结果另补34PNG／JSON并重投影5态，最终5片段及整板已看：保留原文件身份，结果为纯正文ContentPanel；pSoci为右侧18圆环／禁用重选，未核验不能自动写。旧彩色结果图标／leading方框已消除。系统选择器本体单列。 | 冲突／对话框／5保存结果已修已核 |
| `YyT7m` | 通知与接续 | `a7A57` | Q2B7mM、Ib6xa、NgsYw | 已按实际ReplyRoute重投影readonly编辑器／9计数／手机核对与复制；无原通知且无保留为RouteError。新板已逐图看，保留内容与防自动重发说明对应。 | 真实结构已修已核 |
| `C2JJ8t` | 来电与通话 | `a05tWj` | LVKgj、aLUZD、oBEk5 | limited／active真实能力卡＋呼叫卡、无duration／mute／speaker；oBEk5已明确同设备等待来电。soft操作底已修mint／coral并复看，不再保留灰／黑误投影。 | 身份／结构／soft底已修已核 |
| `TfjoF` | 偏好与恢复 | `XPceX` | FkCjb、zLQT5、dPgTI | 预设已取真实QualityPage三行，恢复为黑底center暂停卡／重新检查；两项新板已看，不存在假快捷sheet／立即重试。cache保留0B禁用语义，最后保护mint／回收blue双色badge重导后已复看。 | 预设／恢复／cache已修已核 |
| `iO69Y` | 外观与辅助偏好 | `lUDPa` | OxyeM、W7Lua | 新板深色与降低透明度内容／实体分支已看；设备代表身份已统一我的手机并复看；当前widgets GPU偏好另核，不复用easy图。 | 代表身份／静态分支已修已核 |
| `F4y7lA` | 手机与应用 | `DtZbX` | HjBtR、D5Cjet、D3HWzx、P8F1YG、Nph5q、tch6A、qTeGO | 资源不足中心卡与退出拖拽／吸附片段已看；实际AppsRoute打开sheet与RemoteApp失败另有12PNG／JSON，窄2x退出交叠已生产修复并复看，源两个旧sheet已替换为真实2个满宽44动作＋取消，以及黑底中心失败卡／显式回退，最终板已复看。 | 资源／手势／打开方式／失败已核 |
| `FCb8o` | 无线连接与配对 | `YvzMk` | HevUb、E0CAl、gOwYI、pFGBZ、xq5If | 本组5个真实状态已重投影并逐图复看：原表单授权StateNote、标准红label／helper无外红框、失败后空码0/6、配对确认卡、灰禁用表单＋黑spinner／取消。 | 5态已修已核 |
| `PMkdo` | 相册与内容 | `RqDYL` | Wa6hu、OLDRn、w4Qqmf、KFfP4、x4oRdN、s4p7JF、UwGyp | 多选、扫描、partial、有限空态、80%范围sheet已真实投影并逐图看，空态center与“未完整检查·2处”单行已修；OLDRn为真实0:39/1:18控件。w4已按真实暗媒体失败图替换为72中性EmptyContent＋单保存原文件动作，最终板已复看，旧红卡／假动作已消除。 | 索引／控件／失败态已修已核 |
| `powiM` | 设备工作台与管理 | `TMxVJ` | eDTbS、Txxv0、I6WG6Q、zyRl5 | rename／remove／disconnect改用共享玻璃弹窗；eDTbS同步实际322×227结构，本机归属说明在输入框外允许换行。窄2倍文字明暗、字段语义及提交／取消已核。重授权三等入口保留。 | 玻璃材料／说明与字段已修已核 |
| `XzDEd` | USB连接与授权 | `OxUaB` | WMggr、ONn92、w38WDx、vPWPs | USBwaiting结果卡／serial及实际连接偏好USB转无线片段已看；系统弹窗单列示意。w38旧自制拒绝卡已换成原Guide＋真实StateNote／“已连接，检查授权”，WMggr为系统面板示意配真实busy禁用主按钮及取消，最终板已复看。 | 主控waiting／偏好／失败反馈已修已核 |
| `POTZC` | 系统反馈 | `W3GRn` | MJ3me、s9FWkN | route_error／startup_error明暗PNG对应中性EmptyContent／72灰圆角或64黑图标与正文宽度动作；新板已逐图看，旧红图标／全宽动作已消除。 | 真实结构已修已核 |

上述已核项是最后一次真实结构投影的逐图回执，包含最后补齐的5个保存结果；不以早前13张源板未见溢出替代这些实际复核。主控状态的布局、必要文案与恢复入口须关闭；系统选择器、授权弹窗、实际远端媒体像素仅标明归属，不扩展成任意OEM／任意内容验收条件。

## 60个局部状态的实现与证据映射

本表是有限验收索引。`testWidgets`证明所断言的显示、目标命令、禁用或恢复语义；不自动证明像素、GPU或真实设备操作。PNG为同一生产Widget／router配受控bridge响应，不新增路由、不伪造native纹理。一个状态可由多个语义测试及一个代表截图支持；动态手势用手势测试，不要求为每个中间帧新增页面。

以下详细映射保留此前v4基础证据，临时根为`/tmp/connect-design-v4/`；本轮替换项以文首coverage根及当前画布记录为准：`local-recovery`为10分支×明暗20PNG／JSON；`local-actions`为发现空态和5对话框的正常／窄屏明暗与必要滚动截图；`state-boards`为12个生产分支PNG／JSON；`connection-states`为7个真实router分支PNG／JSON（2026-10-19T10:48:38.843422Z，7/7哈希匹配，独立逐张看）；`video-controls`为真实MediaPreviewPage暂停／播放静音进度／初始化失败的全局明暗6PNG／JSON（10:47:23–24Z，6/6哈希匹配，逐张看）；`app-opening`为实际应用打开sheet／独立窗口失败的12PNG／带色JSON；`usb-feedback`为实际拒绝／系统设备选择取消的phone／narrow2x明暗及滚动12PNG／JSON（10:48:52–53Z）；`document-results`为真实DocumentExportPage的5态及明暗／窄屏／滚动／核对后变体34PNG／带色JSON（11:11:00.784900–11:11:02.343407Z）；`flutter`为主捕获100PNG／94布局。最终源投影状态由上表逐行更新，不从这些文件数量推断60个视觉通过。

下列测试名均位于`app/test/`，是已有回归的可定位映射；新增捕获测试仅复用生产界面获取所缺证据。

| ID | 主控实现／代表状态 | 测试或实际捕获证据 | 检查结果与归属 |
| --- | --- | --- | --- |
| tSC6u | DevicesPage无设备 | widget_test的首屏不造设备；[local_recovery_capture_test.dart](../../app/test/local_recovery_capture_test.dart)／devices_empty | 实际居中空态／添加首设备已捕获 |
| HvaW2 | DevicesPage检查连接 | [local_recovery_capture_test.dart](../../app/test/local_recovery_capture_test.dart)／checking | 实际loading和progress已捕获 |
| oHSUW | DevicesPage全部离线 | device_stage的真实lastSeen；[local_recovery_capture_test.dart](../../app/test/local_recovery_capture_test.dart)／offline | 离线StateNote与可点设备卡已捕获 |
| lj24R | DevicesPage搜索无结果 | [local_recovery_capture_test.dart](../../app/test/local_recovery_capture_test.dart)／search_no_results | 清除搜索实际动作已捕获 |
| h5JZfa | DiscoveryPage未发现设备 | content_pages_layout的4入口typed route；local-actions／discovery_empty | 缺失恢复入口已实现，明暗／窄屏命中已核 |
| K950NO | TransferDetailsPage同名冲突 | [document_export_conflict_test.dart](../../app/test/document_export_conflict_test.dart)；state-boards／transfer-conflict | 实际inline checkbox与3动作已捕获；不伪造成抽屉 |
| wLQoJ | 文件页选择发送入口 | [directory_transfer_test.dart](../../app/test/directory_transfer_test.dart)／[sharing_test.dart](../../app/test/sharing_test.dart)；files正常页捕获 | 目标必须显式选择，系统选择器归宿主 |
| aVAri | 文件页Download目录 | file_search嵌套目录与目标device；files正常页捕获 | 实际路径／56行已逐对核对 |
| x4cTCx | 文件重命名对话框 | [content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart)；local-actions／file_rename | 实际TextField、确认／取消及窄屏已捕获 |
| VZ4BH | 删除所选文件确认 | [content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart)；local-actions／file_delete；[file_guard_test.dart](../../app/test/file_guard_test.dart) | 真确认结构已捕获，无效路径不能误操作替代名称 |
| Y0LpW | 共享内容选择目标设备 | sharing的target／acknowledgment；incoming_share正常捕获 | 选择与发送身份有语义测试；真实系统分享交接另属宿主 |
| uhuiJ | 原文件就绪后可保存 | [receive_content_test.dart](../../app/test/receive_content_test.dart)；[document_results_capture_test.dart](../../app/test/document_results_capture_test.dart)／ready | verified cache lease、result=null且loaded=true才启用；实际原件身份＋正文＋保存按钮已投影复看 |
| Gfe22 | 系统保存取消 | [document_results_capture_test.dart](../../app/test/document_results_capture_test.dart)／cancelled；document_export_conflict的cancelled receipt | 主控取消标题／重选位置真实截图已投影复看；系统选择器另属宿主 |
| mcRQa | 系统确认保存成功 | [document_results_capture_test.dart](../../app/test/document_results_capture_test.dart)／saved；documents再次保存确认 | 系统名称／1文件0夹2.4MB／云盘说明／再保存已投影复看；读回执不重复提交 |
| vSjZS | 系统保存未开始／无输出 | [document_results_capture_test.dart](../../app/test/document_results_capture_test.dart)／failed_empty；document_export_conflict的zero saved | 实际未开始／0文件0夹0B及重选按钮已投影复看，不误报成功 |
| pSoci | 系统保存结果待核 | [document_results_capture_test.dart](../../app/test/document_results_capture_test.dart)／unknown及reviewed；documents的lost receipt／failed journal | 两条中性StateNote、右侧圆环[341,488,18,18]／40命中及禁用按钮已投影复看；勾选后真实重试携reviewedOperationId |
| cdQol | 原文件就绪后可分享 | [receive_content_test.dart](../../app/test/receive_content_test.dart)／[sharing_test.dart](../../app/test/sharing_test.dart)；file_details正常页捕获 | 准备完成与系统交接分层，不造宿主分享面板 |
| jcZXq | 跨目录搜索进行中 | file_search的late creation／nested names；file_search_results捕获 | 结果与设备／目录身份绑定 |
| zD1BI | 停止后保留部分搜索结果 | file_search的confirmed stopped snapshot | 晚到running快照不能恢复已停止任务 |
| HwqEs | DocumentExportPage保存前初态 | [documents_test.dart](../../app/test/documents_test.dart)；flutter／document_export | 是发起前“选择系统位置并保存”，不另算保存结果 |
| Q2B7mM | 通知显式进入手机全屏 | communication的system UI acceptance true／false | 只有系统接受后进入Remote，远端像素不由主控重绘 |
| Ib6xa | 原通知失效 | [notification_reply_recovery_test.dart](../../app/test/notification_reply_recovery_test.dart)；local-recovery／reply_expired、missing_notification | 保留草稿与无记录RouteError实际分支已捕获 |
| NgsYw | 回复结果受理／待核 | [notification_reply_recovery_test.dart](../../app/test/notification_reply_recovery_test.dart)；local-recovery／reply_unknown、accepted、submitted、local_retained | readonly、计数、核对／复制与防自动重发有证据 |
| LVKgj | CallsPage音频受限 | [communication_test.dart](../../app/test/communication_test.dart)；state-boards／calls-limited | 控制与音频分别说明；无伪造收听能力 |
| aLUZD | CallsPage通话中 | state-boards／calls-active；[communication_test.dart](../../app/test/communication_test.dart) | 实际挂断与canSetRoute入口已捕获，无duration／mute假控件 |
| oBEk5 | CallsPage同设备等待来电代表状态 | state-boards／calls-waiting-same-device；communication的incoming device source | 真图仅同设备双call；当前源已明确同设备等待，不能扩大为真实跨设备运行 |
| FkCjb | QualityPage预设区 | [quality_test.dart](../../app/test/quality_test.dart)；flutter／[quality_test.dart](../../app/test/quality_test.dart)；[content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart) | 实际3预设，不存在远控快捷sheet／详细选项假入口 |
| zLQT5 | RemotePage断线暂停 | [remote_connection_recovery_test.dart](../../app/test/remote_connection_recovery_test.dart)；connection-states／zLQT5 | 黑底中心暂停卡／重新检查／退出／nav已捕获，无Texture |
| dPgTI | MediaCachePage受保护内容 | [media_cache_page_test.dart](../../app/test/media_cache_page_test.dart)；[media_cache_lifecycle_test.dart](../../app/test/media_cache_lifecycle_test.dart) | 活跃内容受保护、实际清理bytes与禁用动作有语义断言 |
| OxyeM | 深色设备页 | ios_pages_capture明暗；[preferences_ui_test.dart](../../app/test/preferences_ui_test.dart) | 同身份深色PNG存在，当前GPU另核 |
| W7Lua | 降低透明度设备页 | design_system glass_test；新GPU偏好场景 | 当前widgets GPU降低透明度明／暗／滚动实体分支已成像；同批24图已全部逐看并核marker，不复用easy图 |
| HjBtR | RemotePage资源不足 | [app_launch_test.dart](../../app/test/app_launch_test.dart)；state-boards／remote-resource-busy | 真实全屏中心错误卡／管理活动／重新检查已捕获 |
| D5Cjet | 退出控件拖拽 | [exit_handle_test.dart](../../app/test/exit_handle_test.dart)／widget拖拽消费触摸 | 拖拽不穿透远端输入，手势测试而非静态板注 |
| D3HWzx | 退出控件右侧吸附 | exit_handle的nearest edge／rotation／interrupt | 吸附、旋转与中断有手势断言 |
| P8F1YG | 退出控件左侧吸附 | exit_handle的left drag／expand exit／44 hit | 先展开再退出、44命中和窄屏约束有断言 |
| Nph5q | 单会话继续手机应用 | app_launch的retained screen／[session_workspace_test.dart](../../app/test/session_workspace_test.dart) | 复用原会话身份，不将恢复当新发起 |
| tch6A | 手机应用打开方式 | app_launch的mode／capability选择；app-opening实际AppsRoute sheet | 真2个满宽44按钮＋取消已捕获，窄2x滚动到取消可达；画面内容另归被控 |
| qTeGO | 独立窗口失败后显式转手机屏幕 | app_launch的independent retry／phone fallback；app-opening真实route捕获 | 取消前后无重放；公共恢复viewport避让Exit，narrow2x与滚动动作重捕已看，原8×21交叠已关闭 |
| HevUb | ConnectionForm授权被拒 | connection_transport的CertificateUnknown；connection-states／HevUb | 原表单＋红StateNote／重新配对已捕获 |
| E0CAl | ConnectionForm端口70000 | widget的invalid port；connection-states／E0CAl | 标准红helper，未发devices.add |
| gOwYI | ConnectionForm配对失败 | connection_transport的fresh code；connection-states／gOwYI | 失败后实际清码0/6及错误说明已捕获 |
| pFGBZ | 配对成功待填连接端口 | [connection_transport_test.dart](../../app/test/connection_transport_test.dart)；connection-states／pFGBZ | 原表单＋确认内容卡／typed填写端口入口已捕获 |
| xq5If | ConnectionForm连接中 | widget的attempt cancellation；connection-states／xq5If | 禁用原字段、spinner、取消本次尝试已捕获 |
| Wa6hu | GalleryPage照片多选 | gallery_index的selection identity；state-boards／gallery-multi-select | 真3项选择栏与TextButton.icon已捕获 |
| OLDRn | VideoPreview已初始化视频控件 | [video_preview_test.dart](../../app/test/video_preview_test.dart)；video-controls明暗4PNG／JSON | 初始化2测试核播放／暂停、静音／恢复、seek39/78与释放；媒体局部dark主题及白色控件已看，不供decoded视频像素 |
| w4Qqmf | 视频无法预览 | [video_preview_test.dart](../../app/test/video_preview_test.dart)；video-controls／unavailable明暗2PNG／JSON | 真实初始化error驱动中性72 EmptyContent／保存原文件可命中，源旧红卡及假动作已替换并复看 |
| KFfP4 | GalleryPage检查中 | [gallery_index_test.dart](../../app/test/gallery_index_test.dart)；state-boards／gallery-scanning | 实际progress／停止TextButton已捕获 |
| x4oRdN | GalleryPage部分可读 | [gallery_index_test.dart](../../app/test/gallery_index_test.dart)；state-boards／gallery-partial | 紧凑原因／grid／加载更多已捕获，保留未读边界 |
| s4p7JF | 停止后有限空态 | gallery_index的partial empty；state-boards／gallery-cancelled-empty | 不声称整机相册为空，toolbar重查已捕获 |
| UwGyp | GalleryPage检查范围 | state-boards／gallery-scope | 实际80%sheet／StateNotes／关闭范围已捕获 |
| eDTbS | 设备名称编辑 | [content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart)；local-actions／device_rename | 真实Material编辑框／按钮及明暗窄屏已捕获 |
| Txxv0 | 移除设备确认 | [content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart)；local-actions／device_remove | 仅本机记录说明、真实标题／确认可达已捕获 |
| I6WG6Q | 主动断开确认 | [content_pages_layout_test.dart](../../app/test/content_pages_layout_test.dart)；local-actions／device_disconnect | 真对话框及必要滚动后确认命中已捕获 |
| zyRl5 | AddDevice initialDevice重授权 | widget的preserves identity；connection-states／zyRl5 | 三等入口与既有连接入口已捕获，不另造授权sheet |
| WMggr | 宿主USB访问授权示意 | usb的explicit device choice／cancellation | 系统弹窗归宿主；主控请求／结果有回归，不要求仿绘系统 |
| ONn92 | 等待被控手机调试授权 | [usb_test.dart](../../app/test/usb_test.dart)；state-boards／usb-waiting-authorization | 主控说明页＋waiting结果卡／serial已捕获，手机系统弹窗不仿绘 |
| w38WDx | USB授权未完成／取消 | usb的owning attempt／late result；[usb_feedback_capture_test.dart](../../app/test/usb_feedback_capture_test.dart)／usb-feedback | 拒绝及设备选择取消的真实Guide＋StateNote已捕获；每次重查新attempt，晚到结果不误更新 |
| vPWPs | 连接偏好中的USB转无线检查反馈 | state-boards／usb-wireless-check | 实际DeviceConnectionPreferences动作／反馈已捕获，非USB三步wizard |
| MJ3me | RouteErrorPage内容不可用 | router回归；flutter／route_error | 实际中性EmptyContent及重读／返回已捕获 |
| s9FWkN | StartupErrorPage启动失败 | app_bootstrap回归；flutter／startup_error | 实际64黑图标／正文宽度重启动作已捕获 |


## 材料与共享实例

| 对象 | 本轮明确证据 | 尚未关闭 |
| --- | --- | --- |
| `F1jCz`共享组件区及展开实例 | 普通ActionRow／ChoiceRow自动分隔已移除；37个纯列表父组padding0，行内负责缩进；当前共享区28母组件，删除7个虚构sheet内容及5陈旧label、收紧到680宽并归位3散落母组件；40对及最终13板已逐图复看 | 静态41主帧结构扫描无非预期问题；已有窄屏／大字／大屏／动作可达回归；当前widgets GPU功能／成像已取证；最后5保存结果已实捕投影复核；严格性能缺口单列 |
| `V6QGx4`材料与交互板 | 本轮同步透明页头、完整标题保护、玻璃工具组及按下／取消／重按三种局部状态；实际导出复看，无新增整页副本 | 静态稿只表达状态与材料意图；真实按压和覆盖层见32场景GPU回执，历史压力性能缺口保留 |
| v3 easy后端GPU历史harness | 旧9图已逐张检查；clear蓝条存在可见折射，regular文字可读，reduced三景为实体且光学组件为0 | 按压图含debug指针／提示，不能验收完整形变；明亮clear工具组对比、持续背景追踪和产品实际场景仍有边界 |
| `DYMK6`设计入口 | 对象存在，导向主要页面与状态组织 | 不作为额外产品页或还原通过数量 |

当前结论是：本轮透明页头、覆盖层及按压实现与源稿已同步，40对重比与相关截图复核完成，32场景GPU功能和成像已取证；历史regular／clear／blend压力性能缺口保留。不得将旧图、工具 `completed`、测试数量或母组件一致性合并成41+13全部视觉通过。
