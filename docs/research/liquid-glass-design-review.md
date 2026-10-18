# Liquid Glass 官方设计复核

日期：2026-10-19。状态：研究完成，视觉实施暂停。本轮仅新增此文件，不修改 Pen、规范、代码或此前101页审计事实。

## 结论

本项目应继续保持用户指定的**黑白主题与黑色主动作**，亮色只承担有意义的图标和状态点缀。下一轮的重点是统一对齐、分组、内外几何与内容层级，而非把所有表面做成圆形玻璃。官方允许工具栏采用默认单色外观；这是与项目选择相容的原则，不代表 Apple 要求所有产品使用黑色主题。[HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

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

## 当前本地用法的具体复核

本节依据只读源码；不修改实现。Pencil只读连接在本轮检查时断开，因此不把旧组件记忆当作当前画布的新证据。

| 定位 | 当前事实 | 建议纠正／证据边界 |
| --- | --- | --- |
| `lib/pages/media_preview/media_preview_page.dart:195` | 不可点击的文件名单独包在clear Glass中，左右另有返回和动作组 | 文件名回归普通标题/内容标识；若需要可读保护，以整体媒体导航关系解决，避免静态标签看起来像按钮。属于基于Toolbars职责的项目判断 |
| `lib/widgets/page_frame.dart` actions处理 | 全部actions直接放入同一个GlassToolbarGroup，不区分文字、普通图标和主要动作 | 分组接口表达语义：相关图标共享、文字动作单独、主要动作独立。不能只依据children数量均摊 |
| `packages/design_system/lib/design_system.dart:406` Glass.optics | 已调用LiquidGlassLens，配置refraction、specular与glow；不支持shader时回退BackdropFilter | 可以称有实时光学与兼容路径，不能只因API名称就称为原生Liquid Glass等效 |
| 同文件Glass.build及外部BoxShadow | wrapper按Theme brightness选材料，外阴影与保护渐变固定；未在wrapper看到尺寸或背景对比驱动这些参数 | 固定阴影不是Apple描述的自适应阴影。依赖库内部是否补齐仍需独立核验，不凭未检查的库内部断言完全没有适应 |
| 同文件Glass保护层 | 所有表面使用相同机制的径向保护渐变 | 不用重复白雾遮住全部透色来“修复”对比；按regular/clear职责与内容量检查文字、边缘及大面板 |
| `lib/pages/remote/widgets/exit_handle.dart:159` | 退出控件一律clear，颜色由当前Theme决定；远端内容不保证是照片或视频 | 对任意远端应用优先regular；明确媒体背景才评估clear，不通过更浓统一遮罩代替正确variant选择 |
| GlassToolbarGroup、GlassTabBar | 已有一层共享Glass，子项保持普通控件/浅选中面 | 方向正确；保持一层材料，不新增每项完整玻璃 |
| OriginalFileHeader、GroupedListView | 文件标题是普通内容，相关行以ContentPanel统一分组 | 方向正确；别为了全局“玻璃化”把它们替换为lens |
| GlassIconButton与普通返回控制 | 已区分点击区域与内部图标 | 保持一致命中；不要把每个图标图形都扩大成整块圆形 |

这些是阅读时的代码事实与后续建议，不代表新的逐页运行验收。此前94页结构扫描、分批截图复核和7页补稿的证据继续保留在 [ios-visual-audit.md](../implementation/ios-visual-audit.md)，本研究不修改它们。

## 后续行动顺序（尚未执行）

1. 先确定每个对象属于内容、导航还是局部动作；删除没有控制语义的玻璃标签。
2. 再统一标题/行/工具栏的基线、内边距、同心关系与动作分组，保留黑白主题和语义点缀。
3. 分别对regular与媒体clear验证真实明暗/文字背景；再检查大面板、侧栏与滚动边缘。
4. 最后验证按下、取消、过渡中交互及降低透明度/高对比/减少动态。没有这些运行证据，保留“静态近似/兼容降级”的明确限制。

本轮没有实施上述行动。Flutter架构按既有 [ADR 0002](../adr/0002-rust-adb-and-flutter-monorepo.md)保持；官方原生控件建议不能被写成已获授权重写技术栈。

