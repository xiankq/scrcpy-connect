# 产品与实现收敛（2026-10-18–19）

> 此文件是 2026-10-18–19 产品修订的验收记录，保留各阶段测试数、失败、截图及产物边界。它不是另一份产品规范；当前行为以 [交互规则](../../designs/prod/interaction-rules.md) 为准，实现所有权与生成链分别见 [架构](architecture.md) 和 [工具链契约](repository-tooling.md)。

> 播放器现已改为 pub.dev 社区原版 fvp 0.39.1，本地副本与专用补丁回归已移除。下文采用本地补丁或固定 MDK 的测试、GPU 采集和 APK 回执保留其历史身份，不继承为此次原版依赖切换后的通过证据；原版依赖规则及 snapshot 限制见[工具链契约](repository-tooling.md#社区原版-fvp-0391)。

本轮按用户最初十一项反馈及后续逐页／工具链要求调整产品规则、同一份Pencil源稿和Flutter/Rust实现。当前设计为101页（99手机、2大屏）；原92手机逐张截图分为各46页两批，新增7页及2大屏另有实际截图查看回执。全部41源码页已对照，当前96张浅／深与响应式夹具截图已重拍。视觉值来自 [design.md](../../designs/design.md)，流程来自 [交互规则](../../designs/prod/interaction-rules.md)。既有 ADR 的主控免调试、真实应用任务与连接授权约束继续有效。

| 反馈 | 原问题与决定 | 实现与验证位置／证据边界 |
| --- | --- | --- |
| 1 默认 iOS 返回 | 使用框架的 Cupertino 转场，各普通页面不维护自己的返回动画或手势 | design_system的CupertinoPageTransitionsBuilder、[navigation_test](../../app/test/navigation_test.dart)；沿用平台返回路由。既有模拟器流程有系统返回证据，物理设备交互手势不继承为通过。 |
| 2 移除易用性设置 | 外观只选择浅色、深色、跟随系统。文字缩放、减少动态和高对比读取系统信号 | AppearancePage／ConnectApp、[preferences_ui_test](../../app/test/preferences_ui_test.dart)；当前浅／深外观截图已捕获，系统减少动态／高对比与降低透明度分别处理，不另加产品设置入口。 |
| 3 声音随打开页面 | 设备连接、后台保留会话、实际打开控制页面是三个不同状态。只有最后一种持有播放意图；同时打开设备合并播放，同设备去重 | AppController页面租约、RemotePage与native audio；[audio_test](../../app/test/audio_test.dart)、[activities_audio_test](../../app/test/activities_audio_test.dart)；后者纳入本轮33项定向通过。多设备实际听测仍需物理环境。 |
| 4 设备内剪贴板开关 | 删除全局开关、固定对象、手动发送/获取设置页和冲突选择。当前设备开启同步时，进入和切换立即以设备内容覆盖主控；后续复制自动同步 | DeviceDetailsPage、ClipboardCoordinator与native preferences；[clipboard_test](../../app/test/clipboard_test.dart)、[preferences_ui_test](../../app/test/preferences_ui_test.dart)覆盖切换、代次与按设备独立保存；真实系统权限组合仍单列。 |
| 5 字体按钮紧凑 | 收紧语义文字级别、按钮、列表行、内容边距和导航。触控区域至少44，不以整体缩放达到紧凑 | 共享design_system与生成token；[ios_review_regressions](../../app/test/ios_review_regressions_test.dart)、[ios_pages_layout](../../app/test/ios_pages_layout_test.dart)覆盖标题对齐、最小命中、图标尺寸、短横屏、2倍文字。 |
| 6 玻璃与紫色 | 删除紫色装饰与灰色金属反光，显式定义中性色，内容改普通面。浮动控制共享轻阴影、细边缘和透色材质 | Glass／ContentPanel分层，黑白primary保留；亮蓝／橙／红／绿用于功能图标。官方研究后去静态文件名玻璃、分离文字动作、退出改regular，并去shader路径重复保护渐变／边框；Android shader采集与9图有限人工复核、真实产品r2已通过；原生等效／完整动态／性能不在该结论内。 |
| 7 设计还原 | 同步调整共享组件、实际页面结构、信息归属与文案；移除废弃设计页面，不保留旧入口 | 同一mobile.pen当前101页；原94页结构扫描后，92手机分批逐张截图＋7补稿＋2大屏；41实现页、96当前Flutter图。详见[逐页审计](ios-visual-audit.md)，不把设计页数换算成已运行业务状态数。 |
| 8 Flexible | 根据父约束决定标题和内容空间；文本换行、内容滚动、大屏扩展。手机画稿尺寸只作视口，不作为缩放因子 | PageFrame／HomePage按父约束；全部页面在280×620、620×280与2倍文字测试，根导航另测窄pane／宽短pane。定向测试通过；实际键盘与任意长数据仍按场景验收。 |
| 9 旧版 TCP | 无线指南提供直接 IP+端口入口，默认5555，保留明确的 TCP 传输类型，不依据端口猜测协议 | WirelessGuidePage／ConnectionFormPage与[connection_transport_test](../../app/test/connection_transport_test.dart)、preferences_ui_test；配对／TLS／TCP类型保留。当前空／错字段点击提交由同一Form.validate原位解释，0协议请求，Pen／规范同步此契约。 |
| 10 远控返回与三键 | 系统返回/实体 Escape 发远端 Android Back；仅关闭按钮离页。每设备 showNavigationBar 默认true，三键为4/3/187 | RemotePage与设备偏好、[remote_input_test](../../app/test/remote_input_test.dart)、[remote_lifecycle_test](../../app/test/remote_lifecycle_test.dart)、[exit_handle_test](../../app/test/exit_handle_test.dart)；既有AVD实际Back／三键／拖拽关闭证据按原时间保留，本轮GPU另跑。 |
| 11 越界静默丢弃 | 原坐标舍入可能产生 width/height 本身，引起远端参数拒绝并被误判为画面失败。边沿限制在有效像素内，越界取消已开始手势并忽略余下事件 | RemotePage.pointer有效像素约束、出界cancel／余下事件忽略；remote_input与remote_lifecycle回归及既有AVD边沿用例。正常断线仍阻止输入；不把触控出界写成画面失败。 |

## 后续要求与当前证据

| 要求 | 已实现／已核对 | 验证与剩余边界 |
| --- | --- | --- |
| 黑色主题保留，只把点缀做亮 | primary／主动作仍黑白；功能小图标及状态采用语义亮色，普通正文保持中性 | Pencil逐页与生产组件／浅深图；不能将黑色本身列为缺陷，也不改全蓝主题 |
| 删除页头／普通列表二级描述 | PageFrame、ActionRow、ChoiceRow和普通ListTile描述型subtitle及手工稿特例已清理；设备、错误、进度、通知、来源目标等真实正文保留 | 全41源码与当前96图；活动／诊断／文件等信息丢失回归已恢复并通过定向用例，不以全删小字充当简化 |
| 每页完整排查，不能只改母组件 | 原92手机各46页实际TakeScreenshot；7新增各截图与Get；2大屏有目视回执；41源码对应表与96图清单 | 当前96已重拍；材质代理全96目视属于前一捕获版，最新媒体首帧由页面代理复验；GPU及全部异常状态不能由这些截图代证 |
| 先读Apple官方再继续 | 已读Materials、Toolbars、Tab bars、Sidebars、Layout、Buttons官方正文及WWDC25 219／356／284 | [官方复核](../research/liquid-glass-design-review.md)含直接URL、用途边界与后续实施。研究阶段暂停已结束；当前GPU采集、9图有限人工复核和真实产品r2已完成；未将其扩大为原生等效 |
| 简约且精致 | 统一返回／标题／动作基线、分组、内外几何与列表节奏；内容不玻璃化，文字动作独立，媒体静态文件名不再像玻璃按钮 | 定向回归包括对齐、双分隔、图标拉伸、状态本地化、画质单位、拒接对比；真实背景折射与交互观感另验 |
| 官方token工具自动生成 | 固定@google/design.md 0.4.0公开lint().designSystem解析，项目仅Dart emitter；generate.py／--check接入门禁，含漂移／未知字段／缺引用等失败检查 | [工具链记录](repository-tooling.md)、tool/design_tokens；材质代理最新回执lint为0错误63警告（27组件扩展＋36标准components未直接引用颜色），generator/check与包11测试／analyze通过；最终生成一致性日志已回填，见当前视觉轮验收。该计数不等于Pencil母组件数 |
| 社区原版播放器 | 精确使用 pub.dev fvp 0.39.1；移除本地源码副本、path override、snapshot 补丁及 MDK 固定回归，MDK 平台依赖沿用上游规则 | 此前五份空回调保护及固定归档的验收仅属历史。原版 snapshot 空结果未判空的限制保留说明；当前选择使用原版，不以先补修复作为删除副本的条件。规则见[工具链契约](repository-tooling.md#社区原版-fvp-0391)，切换后结果见[验收记录](validation.md) |
| 当时的根目录单应用迁移 | 该阶段以根pubspec／lib／test／integration_test／runner为唯一入口，旧apps/connect与空apps已移除；design_system、interop_bridge和Rust各自保留职责 | 最终普通lib/main.dart Android-x64 debug包已构建、ZIP／ELF及签名校验并覆盖安装启动；具体摘要见末尾。业务r2与普通入口启动观察各保留自身范围，不继承旧APK结果 |
| 清理旧产物与临时文件 | 已清重复旧build／Dart缓存／旧APK／过渡设计导出；历史记录约释放11.32GiB。设计导出放系统临时目录，Git保留源稿、规范与实际引用素材 | 最新96图、测试日志／回执、仍复用缓存与当前APK有意保留。主代理最后清理23项、2,087,737,945字节（约1.944GiB），回执见末尾；11.32GiB仅是之前迁移阶段记录。保留唯一普通入口APK及共享Rust／native缓存，本次文档未reset／commit或删除产物 |
| 真Android光学验收 | 独立生产Glass harness＋strict driver，9场景；检查shader支持／加载、非Lite、真实拖动、按下／取消、亮暗与reduceTransparency，并在/tmp保存PNG／JSON | **9场景采集契约与逐张有限人工复核完成，真实产品r2通过**。shader支持／加载、交互、非Lite及场景像素标记均通过；visualAcceptanceComplete保持false作为工具不签发人工认证的边界，原生等效／完整形变／性能仍分开验收 |


## 衍生问题

旧偏好仅作一次性清理，不继续提供旧模式。旧后台声音偏好也一并移除，后台声音随统一的后台保持设置。设备设置按设备 ID 存储，更新一个设备不能覆盖另一个设备；移除设备同步移除偏好。剪贴板使用代次与当前设备检查阻止旧请求、旧事件及离开前台后的结果写入主控。

音频检查除了“同设备去重”，还必须覆盖一台设备启动挂起时关闭另一台、退出期间启动返回，以及真实 session.disconnected 事件。清理不能排在另一个设备的启动之后；最后一个页面释放应立即撤销媒体启动意图，并独立停止对应设备声音。

空闲状态没有页面租约和声音任务时不查询音源，避免恢复事件触发无意义的状态查询循环。测试查询按设备用途区分，保留恢复流程不重放副作用的断言。音源启动要求真实控制会话，Rust夹具同步补齐视频/控制握手，不放宽生产约束。

远控有效手势出界必须发送最后有效点的 cancel，避免远端残留按下；重新进入画面不自动续接旧指针。正常断线仍可标记最后一帧与阻止输入，触控越界不进入该状态。导航条使用独立空间，触控坐标按剩余画面区域计算。

## 历史门禁与产物（目录迁移／本轮视觉修订前）

以下计数、日志和APK摘要对应当时源码，不能当成后续101页视觉修订的最终全量结论。该轮稳定源码通过 `tool/check.sh` 各门禁：协议与FRB生成一致性、伴生组件确定性构建、工具与原生依赖检查、Dart/Rust格式、视频snapshot回归、workspace clippy（`-D warnings`）、Flutter analyze及架构分析插件契约。Rust共301项通过、68项依其真机/外部环境契约忽略；Flutter应用310项、interop_bridge 131项、design_system 3项通过。CPU敏感的既有密码学测试以 `RUST_TEST_THREADS=4` 执行。完整日志保存在 `/tmp/connect-refinement-check.log`。

Android 本轮实际端到端流程通过：独立主控与目标 AVD，旧版 TCP 连接、文件流程、H.265 486×1080 实际编码/解码与 `mdk.snapshot` 证据、默认三键、系统返回保留远控、画面外点击不暂停、退出控件拖动/收起/展开、关闭返回工作台、本地呈现暂停与关闭后无活动音源。最终 `productAcceptanceComplete` 与全部新增回执为 true，日志、回执及截图位于 `/tmp/connect-refinement-e2e`。本次启动的目标 AVD 与临时转发已清理，保留既有主控。

Android x64 debug APK 已构建并独立验证 ZIP、签名、Flutter/Rust ELF 架构与16KB对齐，使用既有 debug 签名。实际AVD流程的集成入口APK在收尾清理中移除，摘要回执保留于 `/tmp/connect-refinement-e2e/product-flow-apk-receipt.json`。该轮在目录迁移前、最终空闲查询修复后另构建普通 `lib/main.dart` 入口，产物为 `build/app/outputs/flutter-apk/app-debug.apk`（120,543,637字节，SHA256 `1f30b81316f955429560456965f74ee54ec4994c5febc00056af564300dfb71b`），构建及包装验证通过，未对普通入口重复drive。构建日志位于 `/tmp/connect-refinement-main-apk.log`，debug包不作为发行签名产物。

较早一轮Pencil修改保存并重开时为94页、27母组件、158变量（历史计数，当前页面数已为101；母组件／变量当前为30／186，见末尾最新回执），未保留独立音源/剪贴板/易用性设置页；活动分支无意外越界，工作台的一处纵向滚动视口裁剪按设计单独确认，完整内容保留；组件与变量无缺失。共享页头65个实例文案、工作台分组列表和X关闭按钮已核对。官方 DESIGN.md lint 为0错误、31警告，分类见[工具链记录](../research/design-system-and-toolchain.md)。Flutter 截图含浅/深色、外观、设备设置、TCP、平板、280窄屏与横屏2倍文字，保存在 `/tmp/connect-refined-ui`。

单测、组件测试和模拟器截图不能替代物理手机上的多设备声音听测、剪贴板系统权限、GPU材质与系统返回手势验收。模拟器日志仍有 GLES 0x501 及 Surface 释放后的 BufferQueue 告警，当前实际解码、健康状态和截图核对通过；不把这些局部证据推广为各GPU零告警或四端运行全部通过。未执行的真机组合不继承历史通过记录。

## 视觉修订阶段验收（历史产物）

根应用最终`flutter test --no-pub --reporter json`全量 **323个非hidden项success**，done.success=true：[JSONL](/tmp/connect-final-tests.jsonl)。之后只修startupError无用字符串插值和测试braces两处lint；`ios_review_regressions`、`ios_pages_layout`、`ios_pages_capture`3文件 **13项success**，含全部96图再次捕获：[JSONL](/tmp/connect-final-pages.jsonl)。[Flutter analyze](/tmp/connect-final-analyze.log)为No issues found；[tool/generate.dart --check](/tmp/connect-final-generate.log)包含官方token解析、FRB Rust／Dart及build_runner生成一致性，全部成功。材质代理另有design_system 11项和Node生成器4项通过回执；这些是当前轮证据，不重复使用历史Rust301／桥接131计数。

当前96图为41页浅／深＋5额外状态浅／深＋4根导航响应图，位于`/tmp/connect-ios-review`，详见[页面与完整清单](/tmp/connect-ios-review/page-audit.md)。图片等待实际首帧，gallery／media_preview检查RawImage非空，最新媒体浅深图已打开确认照片；远控夹具用测试纹理。Widget截图验证布局、字级与用途，不能证明实际折射；材质代理全96逐张目视属于之前捕获版，没有冒充最新96全量重看。

Android Impeller独立9场景[result.json](/tmp/connect-glass-material/result.json)报告shader支持／加载true、Lite=false、交互与host校验true、9张实际截图的场景像素标记true；降低透明度3图光学组件全0。材质代理已逐张实际view_image：clear明暗左上close内蓝条明显弯折／位移和背景透入；regular浅深／滚动文字清楚，未见额外异常黑块、斜线或截断；reduced三图实色且不透背景。规则黑方块／中央marker为诊断背景。pressed图有debug指针和Tooltip，只证明按压捕获，不能证明完整形变、动态高光、回弹或性能。工具`visualReviewRequired=true`、`visualAcceptanceComplete=false`原样保留：它不签发人工认证，**不表示另行9图有限人工复核未做或失败**。未改写工具结果，也不宣称Apple原生等效。

真实Android产品 **r2完整通过**：[result.json](/tmp/connect-final-product/result.json)、[drive日志](/tmp/connect-final-product-r2.log)。productAcceptanceComplete=true，H.265实际编码／解码486×1080、默认三键、系统Back保留streaming、letterbox点击不暂停、把手内向展开、退出仅暂停本地呈现与关闭后停止设备音源均为true；root实际查看Back／letterbox后远控及返回工作台截图。首次r1失败是画质UI增加px单位后旧测试仍查裸数字；改为精确px断言后r2通过，没有改产品行为或降低画质门槛。

仍保留物理多设备声音听测、剪贴板权限组合、iOS原生返回手势、多路真实Texture／GPU预算、完整可打断形变／来源过渡、读屏与四宿主运行的独立边界；本轮通过不扩大为这些未执行组合均通过。

当前稿／代码映射须保留以下区别：独立设计页常对应实现中的同一PageFrame、多模式状态或系统交接，不是一页一条产品路由；所有101静态稿不能由41默认夹具状态全部运行复现。2大屏已收敛为侧栏与单一当前内容，不把早期并行工作区示意写成既有原生多窗口能力。主代理已确认mVNnf改为整页通知＋输入／发送、XPceX改为3预设choice＋5细项内容行，与源码下钻一致；远控内FkCjb/h7lWL保留真实上下文sheet。这些旧差异不再列为当前未修复问题。

主代理当前Pencil回执为101页、30母组件、186变量：新增共享sidebar、删除闲置母组件；18处旧blur使用同一编译成功的liquid-glass.glsl。更新后媒体预览、大屏与远控代表截图已实际查看；Pencil材料属于静态表达，不能据此声称Flutter GPU或Apple原生像素一致。main已等待GlassMaterial.initialize，GPU新材质9图捕获已完成，9图有限人工结论及真实产品r2已在上文回填；W7Lua降低透明度导航已改全实色，Get确认无shader并保存，统计不变。

## 视觉修订阶段普通入口与清理（历史产物）

普通`lib/main.dart`入口Android-x64 debug包已构建：[构建日志](/tmp/connect-final-main-build.log)、[产物回执](/tmp/connect-final-main-apk.json)。保留唯一APK为`build/app/outputs/flutter-apk/app-debug.apk`，**147,239,422字节**，SHA256 `b7c766abfc6a94a2166af30fa2a4572898deb297e4a6ae62c94b5973e91073e8`；ZIP完整性、x64 ELF与apksigner签名验证通过。该普通包已成功覆盖集成测试包安装并am start，启动观察pid11476、Impeller OpenGLES、未见UnhandledException；这是普通入口启动证据，完整业务通过仍以此前独立集成r2回执为界。debug包不等同发行签名产物。

[最终清理回执](/tmp/connect-final-cleanup.json)实际删除 **23项、2,087,737,945字节（约1.944GiB）**，包括本轮build中间目录、测试资产、重复APK和`.dart_tool/flutter_build`。保留上面的唯一普通APK、验收日志／截图／回执，以及共享Rust／native编译缓存；这次统计不与历史11.32GiB混加。目标AVD5556和临时15556转发已清理，adb只保留原主控5554。未reset或commit外部变更。
