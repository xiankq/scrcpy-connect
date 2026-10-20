# Liquid Glass 官方设计复核

研究日期：2026-10-16、19。依据 Apple HIG、WWDC25/26 官方正文与字幕，区分官方原则和 Flutter/Pencil 设计推论。当前视觉规则见[视觉规范](../../designs/design.md)，材料实现与运行证据见[设计与实现对照](../implementation/design-fidelity.md)。

## 结论

官方允许工具栏采用默认单色外观，与本项目黑白主题和黑色主动作的选择相容；这不代表 Apple 要求所有产品使用黑色主题。[HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

Liquid Glass 是内容上方的功能层。设备卡、普通列表、表单、文件名等内容，不应因为可见就各自拥有一片玻璃；普通内容材料有其独立作用。[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

## 官方资料与阅读方式

以下使用 Apple 官方正文及字幕，重点为通用规则和 iOS/iPadOS 适用部分。

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

## 先区分版本：2025 的原理与 2026 的修订

WWDC25 建立了光学与运动统一的基本模型：材质弯折光线，控件随着触控伸缩、形变；导航浮于内容之上。2026 的官方方向继续保留这种模型，同时强化复杂背景的扩散、可读性和分离感。Mac 顶部工具栏更统一、侧栏延伸到窗口边缘、窗口圆角更收敛；用户可以调节玻璃从更清晰到更着色的外观。[WWDC25 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[WWDC26 Keynote](https://developer.apple.com/videos/play/wwdc2026/101/)

WWDC26 State of the Union 进一步明确 Mac 与 iPad 侧栏延伸到边缘，侧栏图标恢复强调色；已经采用系统 Liquid Glass 的应用获得这些改进。这里“系统自动获得”只针对相应 Apple 系统控件，不适用于本项目自绘 Flutter 材质。[WWDC26 Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/)

## 真正的材料与静态近似

官方在219中描述的是共同工作的系统：实时lensing/refraction建立厚度；阴影随背景文字与纯色变化；亮度、色调与前景对比适应背景；高光响应几何和运动。交互时有即时发光、形变和由来源控件延伸的空间关系。单张模糊图、透明白底、细边框和固定阴影只能表达其中一个静态状态。[WWDC25 219](https://developer.apple.com/videos/play/wwdc2025/219/)

UIKit将 UIGlassEffect 与 UIBlurEffect明确区分；交互性、材质化/退场、相邻玻璃融合与统一适应有专门机制。因此“存在shader”与“所有原生行为已实现”是不同证据等级。[WWDC25 284](https://developer.apple.com/videos/play/wwdc2025/284/)

| 需要分开的能力 | 本项目应如何表述 |
| --- | --- |
| 静态画布表达 | 可检查颜色、分层、边缘、字级和位置；不能证明实时折射与手感 |
| 磨砂降级 | blur＋透明填充可作为兼容路径；明确称为降级材料 |
| 实时光学 | 移动真实背景时验证折射与边缘；参数存在不等于画面已正确 |
| 背景／尺寸适应 | 亮度、透色、对比随背景变化；大面板比小控件呈现更厚、更散射的材料，不能仅切换全局主题或复用一层透明填充 |
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
- **文字增大时布局跟着变。** 根据可用空间改行、堆叠或滚动，安全区与最后一项内容不能被持久控件永久覆盖。[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

## 滚动边缘与上下文弹层

HIG 在 2026 更新中优先推荐 automatic 滚动边缘效果：文字和控件较多的顶栏、固定表头可获得更不透明的分离。soft 需要验证各种内容下的可读性。效果仅用于滚动内容实际位于浮动界面后方时，每个视图使用一个；分栏可各有一个且高度保持对齐。[HIG Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)

系统半屏 sheet 从屏幕边缘内缩，后方内容可见，向全高扩展时更不透明；action sheet 从发起控件附近出现，明确动作来源。[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)

Sheet 用于与当前上下文紧密相关的有限任务；取消、完成与返回具有不同语义，同一主界面不叠加多张 sheet。完成必须有可退出的替代路径。[HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)

## 浅色、深色与无障碍

浅深色不能只把白底换黑底。背景、内容、文字、边缘与阴影需要共同切换语义；单个玻璃控件还会受背后内容影响，不能假定整页属于深色就永远使用白字。[HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)

Apple 的材质会响应减少透明度、增加对比等系统选择。2026 还增加玻璃清晰/着色偏好的连续调节。[HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[WWDC26 Keynote](https://developer.apple.com/videos/play/wwdc2026/101/)

无障碍要求对浅深色分别验证文字对比；状态不只靠颜色传递，控件需要适当点击区域。减少动态效果时，应降低自动和反复动画，可用淡入淡出替代显著空间位移。[HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## 排版与应用图标

Apple 排版指南建议用字号、字重和颜色共同表达层级，减少字体混用，避免细字重损害可读性；支持更大文字时允许换行、增加容器高度与减少列数，不应通过截断保留原布局。系统文字样式与可变字体支持光学调整。[HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography)

Apple 应用图标采用背景与前景分层，简单明确的形状更利于系统生成高光、折射与透色；不应把完整界面截图做成应用图标，也不应在源图中固化所有系统动态光效。[HIG App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

## 自适应与动态交互验证边界

侧栏适合有足够空间的窗口，紧凑时可切换为标签栏；适配取决于可用空间，macOS 还支持用户调整侧栏宽度与收起。[HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)

动作应有目的、简洁、跟随手势且可取消；直接触控和触控板的反馈强度不同。动作不能是传递重要信息的唯一方式。[HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)

Pencil 能表示静态分层、边缘与阴影，不能证明实时折射、触点高光、控件融合、可打断弹簧、动态视频对比或 GPU 成本。实时材料与磨砂降级的实施证据见[设计与实现对照](../implementation/design-fidelity.md)。
