# Liquid Glass 官方设计复核

日期：2026-10-19。状态：官方资料研究完成；后续用途、对齐与分组纠正已实施，9场景Android光学采集契约已通过，9张图有限人工复核及真实Android产品流程r2已完成，原生等效／完整动态／性能仍单列。研究阶段曾暂停视觉改动；该历史暂停已结束，不能继续当作当前任务状态。本文不将静态设计或Widget截图写成原生Liquid Glass验收。

## 结论

本项目继续保持用户指定的**黑白主题与黑色主动作**，亮色只承担有意义的图标和状态点缀。后续实施围绕对齐、分组、内外几何与内容层级展开，没有将所有表面做成圆形玻璃。官方允许工具栏采用默认单色外观；这是与项目选择相容的原则，不代表 Apple 要求所有产品使用黑色主题。[HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

Liquid Glass 是内容上方的功能层。设备卡、普通列表、表单、文件名等内容，不应因为可见就各自拥有一片玻璃；普通内容材料有其独立作用。[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

## 官方资料与阅读方式

已读取以下官方资料。HIG网页要求JavaScript，网页提供了 View Markdown 链接；浏览工具不支持该链接的 text/markdown 响应，因此只读获取了同一 Apple 官方URL的Markdown正文，没有以第三方摘要替代。阅读重点为通用规则及iOS/iPadOS适用部分。

| 官方资料 | 实际正文入口／重点 |
| --- | --- |
| [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/materials.md)：内容材料与玻璃、regular/clear、可读性 |
| [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/toolbars.md)：标题、返回/关闭、动作分组、减少装饰 |
| [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/tab-bars.md)：顶层导航、稳定目的地、标签 |
| [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/sidebars.md)：空间、背景延展、层级与图标颜色 |
| [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/layout.md)：对齐、分组、安全区、自适应 |
| [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) | [官方Markdown](https://developer.apple.com/design/human-interface-guidelines/buttons.md)：命中区域、按下反馈、动作层级 |
| [WWDC25 219：Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) | 官方字幕：Dynamics、Adaptivity、Principles |
| [WWDC25 356：Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/) | 官方字幕：几何、结构、分组、滚动边缘 |
| [WWDC25 284：Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/) | 官方字幕：UIKit控制分组、玻璃呈现、背景适应与交互 |

下文“官方结论”来源于上述资料；“项目判断”是对当前Flutter/Pencil用法的推论，不是 Apple 对本项目的认证。没有从 Apple 资料推导新的光学数值或另建token。

## 真正的材料与静态近似

官方在219中描述的是共同工作的系统：实时lensing/refraction建立厚度；阴影随背景文字与纯色变化；亮度、色调与前景对比适应背景；高光响应几何和运动。交互时有即时发光、形变和由来源控件延伸的空间关系。单张模糊图、透明白底、细边框和固定阴影只能表达其中一个静态状态。[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)

UIKit将 UIGlassEffect 与 UIBlurEffect明确区分；交互性、材质化/退场、相邻玻璃融合与统一适应有专门机制。因此“存在shader”与“所有原生行为已实现”是不同证据等级。[WWDC25 284](https://developer.apple.com/videos/play/wwdc2025/284/)

| 需要分开的能力 | 本项目应如何表述 |
| --- | --- |
| 静态画布表达 | 可检查颜色、分层、边缘、字级和位置；不能证明实时折射与手感 |
| 磨砂降级 | blur＋透明填充可作为兼容路径；明确称为降级材料 |
| 实时光学 | 移动真实背景时验证折射与边缘；参数存在不等于画面已正确 |
| 背景／尺寸适应 | 分别检查文字、明暗背景及小控件/大面板，不以全局明暗主题切换代替 |
| 交互 | 按下、取消、来源关系、过渡中再操作以及辅助偏好分别验证 |

## 各类界面的使用边界

| 本项目对象 | 使用边界与可实施方向 | 官方依据 |
| --- | --- | --- |
| 普通设备卡、文件/通知列表、表单 | 内容层保持清晰的中性实体或标准材料。文件名、状态与真实数据通过对齐表达，不能每项再套玻璃 | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| 静态文件名胶囊 | 文件名为内容标识时，优先普通标题；仅当其本身是文档菜单等真实控制时才采用控制语义。此项是项目推论，不是“所有标题禁止背景” | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) |
| 浮动返回、关闭、工具栏 | 返回/关闭使用熟悉符号；相关图标共享一组背景，文字动作独立分组。不要给共享容器内每个图标再加完整玻璃 | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[WWDC25 284](https://developer.apple.com/videos/play/wwdc2025/284/) |
| 设备/传输/设置tab | 只表达稳定顶层目的地，保留标签与各区导航状态；局部保存/发送不混入全局tab | [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) |
| 被控屏幕上的退出控件 | 属于浮动功能控制。但远端可能是白色文字页面，不能仅因“远控”就默认clear；优先能保证对比的regular，特定媒体场景再评估clear | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| 黑色filled主动作 | 可以作为内容流程里的主要动作；不必为了“玻璃感”全部透明化，也不能宣称实体filled按钮具有玻璃效果。用样式层级而非放大尺寸强调，避免多个同等强主动作 | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |
| sheet、菜单与长内容面板 | 短暂控制面板保留来源关系；进入长文本/深任务时提高承载与可读性。不能将整块长内容做成几乎透明clear，也不要叠完整玻璃内卡 | [WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/) |
| sidebar | 依实际可用空间选择；可延展邻近背景以保持连续，但不能镜像正文或遮住核心内容。不是把手机页无限放大 | [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) |
| 照片/视频上的clear | 仅用于丰富媒体背景。亮背景需要局部保护；暗背景或系统播放器已有保护时不机械重复加遮罩。文字密集或背景不可控时回到regular | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |

**filled动作与玻璃染色不能混为一谈。** 219展示“不透明填充破坏玻璃”时讨论的是已经属于玻璃层的控件染色，并非禁止内容流程存在普通filled按钮。项目黑色主动作保留，是用户选择；玻璃与普通按钮按职责区分。

## “简约但精致”的具体判据

- **同一基线与信息分组。** 图标、标题、尾部值、箭头保持可扫描的对齐；同类行共享内边距与分隔规则。空白、形状与分隔线都可以分组，不必每行一张卡。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- **内外同心，而非到处同一圆角。** Apple区分固定圆角、胶囊与按容器推导的同心形状。要同时检查外半径、内间距和子形状，避免嵌套处夹紧或向外张开的角。[WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)
- **44pt命中不是44pt实心圆。** 命中区域、可见图形与间距是三个不同问题；可见图标可以更小，透明点击区仍需足够。主次选择通过样式区分，不靠把首选按钮做得更大。[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- **亮色有语义。** 图标可采用明亮功能点缀，不能把每个动作都染色，也不能让普通正文失去对比。sidebar固定图标颜色应有清楚用途。[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- **休止态可读且不遮挡任务。** 静止时避免关键正文与玻璃控制发生冲突；媒体可延伸到控制后方，但应保护主体与文字。滚动边缘效果只用于真正有浮动UI的边缘，不是装饰渐变。[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)、[WWDC25 356](https://developer.apple.com/videos/play/wwdc2025/356/)
- **文字增大时布局跟着变。** 根据可用空间改行、堆叠或滚动，安全区与最后一项内容不能被持久控件永久覆盖。精简副描述后仍保留支持状态、错误、进度和对象归属。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

## 本地用法复核与后续实施

官方研究阶段只读源码；下表现补入后续实际源码、定向测试及页面代理回执。原92手机页已分两批各46页实际截图，新增7页和2大屏也有截图查看回执。最终浅／深色96张Flutter夹具已重拍；这些仍是测试降级渲染，不能代替真机shader。详细版本边界见[逐页审计](../implementation/ios-visual-audit.md)。

| 定位 | 初始发现与后续事实 | 当前证据／限制 |
| --- | --- | --- |
| `app/lib/pages/media_preview/media_preview_page.dart` | 初始不可点击文件名被clear Glass包裹；现在为普通单行文字，clear只留返回和保存／分享控制，导航后方有局部渐退保护 | `ios_review_regressions_test.dart`检查文件名不在Glass内；浅／深媒体最新截图已显示照片。保护层与图标在真实明暗纹理上的光学表现仍待GPU查看 |
| `app/lib/widgets/page_frame.dart` | 初始所有actions放同一GlassToolbarGroup；现在相关图标仍共享，真实文字动作通过独立`trailingAction`布局，并统一返回与标题对齐 | 相关回归覆盖图标组、文字动作不在Glass内及左右对齐；不以组件接口存在代替所有未来调用正确 |
| `packages/design_system/lib/design_system.dart` Glass.optics | 调用LiquidGlassLens，配置refraction、specular与glow；不支持shader时回退BackdropFilter | 独立GPU harness要求Android shader支持、程序已加载、非Lite，并捕获真实背景；当前9场景采集契约与逐张有限画面复核已完成，原生级质量结论仍单列；不能只因API名称称为原生Liquid Glass等效 |
| 同文件Glass.build及外部BoxShadow | 初始wrapper另绘固定保护渐变／边框；当前shader路径已去掉额外保护渐变与重复边框，外部柔和阴影仍按Theme固定，降低透明度与高对比直接使用实体分支 | 这些清理减少灰色条带与双重描边，但固定阴影不能称Apple自适应阴影；库与实际背景表现仍需独立核验 |
| 同文件Glass交互与启动 | 当前要求支持shader时先初始化程序，main已await GlassMaterial.initialize；交互控件接入细微touch flex，disableAnimations时不启用；不再由页面单独画一套玻璃 | 已有包级回归与静态分析回执；实际按压／取消画面、可打断性及对比适应由GPU运行验证，接入参数不等于原生级手感通过 |
| `app/lib/pages/remote/widgets/exit_handle.dart` | 初始退出控件一律clear；后续已改regular，适用于任意远端应用背景，既有拖拽／吸附／展开／关闭行为保留 | `exit_handle_test.dart`纳入定向回归；真实文字、明暗背景及视频上的可见性仍需设备截图与输入结果 |
| GlassToolbarGroup、GlassTabBar | 已有一层共享Glass，子项保持普通控件/浅选中面 | 方向正确；保持一层材料，不新增每项完整玻璃 |
| OriginalFileHeader、GroupedListView | 文件标题是普通内容，相关行以ContentPanel统一分组 | 方向正确；别为了全局“玻璃化”把它们替换为lens |
| GlassIconButton与普通返回控制 | 已区分点击区域与内部图标 | 保持一致命中；不要把每个图标图形都扩大成整块圆形 |

上述已实施的用途纠正关闭了相应初始建议，尚未验证的动态能力保持开放。它们不代表所有页面业务状态运行通过，也不改变初始94页结构扫描的历史事实。

主代理另已将Pencil的18处旧blur替换为同一`assets/liquid-glass.glsl`，实际编译成功，并查看更新后的媒体预览、大屏和远控代表页。该静态光学表达与Flutter生产shader是两类证据；不能因Pencil编译或静态图中边缘可见，就称为Apple原生效果一致。源稿当前101页、30母组件、186变量，源码当前41页，完整对应关系以逐页审计为准。

## 实施与验收顺序

1. 已按内容、导航和局部动作区分用途；静态文件名去玻璃，普通内容维持中性实体。
2. 已统一标题／行／工具栏分组与对齐，删除描述型副标题，保留黑白主题及真实状态正文；41页各有浅／深截图，窄屏／横屏2倍文字和重点回归已有证据。
3. 独立Android shader场景已经完成9图采集与严格driver校验。生产GlassIconButton、GlassToolbarGroup、GlassTabBar、regular面板和clear媒体控制覆盖明暗背景；测试背景含细线、字样、格纹与彩色几何，属于诊断夹具，不加入产品装饰。
4. harness要求实际拖动背景、按下／取消后再操作，并切换light／dark／reduceTransparency；降低透明度场景必须移除Lens／Lite／BackdropFilter。严格driver保存PNG与JSON，shader不支持或退回fallback不得登记光学完成。

当前[result.json](/tmp/connect-glass-material/result.json)已报告shader支持／加载、非Lite、交互、9图场景像素标记及host校验通过；降低透明度3图未挂载Lens／Lite／BackdropFilter。材质代理已逐张实际查看9图，真实产品r2也已通过，分别见下文记录。`opticalCaptureComplete`只表示满足shader路径条件的捕获完成，`visualAcceptanceComplete`仍为false，这是工具不签发人工认证的固定边界，并非另行9图人工复核失败；不能把blur＋border、capability=true或单张静态图当作完整原生效果。材质代理逐图确认clear明暗左上close的蓝条弯折／位移与背景透入，regular浅深／滚动文字清楚且未见额外黑块、斜线或截断，reduced三图实色且光学组件为0；pressed图含debug指针与tooltip，不证明完整动态形变。背景自适应阴影／对比、可打断形变、来源过渡、多路真实视频预算、减少动态与读屏等仍需相应证据。

最终实现验证：根应用[323项全量](/tmp/connect-final-tests.jsonl)通过；之后两处纯lint修复的[3文件13项回归及96图重拍](/tmp/connect-final-pages.jsonl)通过；[analyze](/tmp/connect-final-analyze.log)无问题，[生成一致性](/tmp/connect-final-generate.log)含FRB与build_runner通过，design_system 11项和Node生成器4项通过。真实[产品r2回执](/tmp/connect-final-product/result.json)验证H.265实际486×1080、三键、系统Back保留远控、画面外点击静默、退出把手与关闭后停止音源；root另实际查看远控与返回工作台画面。这不代替多设备实机、原生交互等效或性能验证。Pencil降低透明度页W7Lua导航意外继承shader已改全实色，主代理Get确认无shader并保存。

普通lib/main.dart Android-x64 debug包另完成构建、ZIP／ELF／签名验证与覆盖安装启动，启动观察为Impeller OpenGLES、未见UnhandledException，详见[最终产物回执](/tmp/connect-final-main-apk.json)。该启动观察与集成r2业务、独立9图光学分别记录，不宣称全套原生材料行为通过。最后[清理23项、2,087,737,945字节](/tmp/connect-final-cleanup.json)后保留普通APK、验收证据与共享编译缓存，未修改本研究引用的工具结果。

Flutter架构按既有 [ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md)保持；官方原生控件建议不能被写成已获授权重写技术栈。所有视觉值仍来自`designs/design.md`及生成token，本研究不建立另一份参数规范。

