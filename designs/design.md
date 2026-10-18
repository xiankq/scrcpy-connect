---
version: alpha
name: 邻接 Interconnect
description: iOS 系统中性内容与黑白主题操作，以真实透色、折射和高光构成 Liquid Glass 控制层。
colors:
  primary: '#1B1B1F'
  primary-dark: '#F2F2F4'
  primary-action: '#1B1B1F'
  primary-action-dark: '#F2F2F4'
  on-primary: '#FFFFFF'
  on-primary-dark: '#18181A'
  canvas: '#F2F2F7'
  canvas-dark: '#000000'
  surface: '#FFFFFF'
  surface-dark: '#1C1C1E'
  text: '#000000'
  text-dark: '#FFFFFF'
  secondary: '#636366'
  secondary-dark: '#AEAEB2'
  muted: '#D1D1D6'
  muted-dark: '#38383A'
  tint: '#E5E5EA'
  tint-dark: '#2C2C2E'
  glass: '#FFFFFF80'
  glass-dark: '#1C1C1E99'
  glass-clear: '#FFFFFF26'
  glass-clear-dark: '#1C1C1E4D'
  glass-clear-panel: '#FFFFFF80'
  glass-clear-panel-dark: '#00000080'
  glass-edge: '#FFFFFF66'
  glass-edge-dark: '#FFFFFF26'
  glass-low-edge: '#75757A42'
  glass-low-edge-dark: '#000000A3'
  glass-shine: '#FFFFFF66'
  glass-shine-dark: '#FFFFFF1F'
  shadow: '#00000014'
  shadow-dark: '#00000066'
  success: '#34C759'
  success-dark: '#30D158'
  warning: '#FF9500'
  warning-dark: '#FF9F0A'
  danger: '#FF3B30'
  danger-dark: '#FF453A'
  scrim: '#17171B4D'
  scrim-dark: '#00000080'
  white: '#FFFFFF'
  transparent: '#00000000'
  media-ink: '#111114'
  media-shade: '#00000099'
  accent-blue: '#007AFF'
  accent-blue-dark: '#0A84FF'
  accent-blue-soft: '#E6F2FF'
  accent-blue-soft-dark: '#1A2635'
  accent-coral: '#FF3B30'
  accent-coral-dark: '#FF453A'
  accent-coral-soft: '#FFEBEA'
  accent-coral-soft-dark: '#332021'
  accent-amber: '#FF9500'
  accent-amber-dark: '#FF9F0A'
  accent-amber-soft: '#FFF4E6'
  accent-amber-soft-dark: '#33291C'
  accent-mint: '#34C759'
  accent-mint-dark: '#30D158'
  accent-mint-soft: '#EBF9EE'
  accent-mint-soft-dark: '#1E2E24'
  glass-selected: '#FFFFFF66'
  glass-selected-dark: '#FFFFFF26'
  glass-reflection: '#FFFFFF08'
  glass-reflection-dark: '#1C1C1E08'
  glass-action: '#1B1B1F'
  glass-action-dark: '#F2F2F4'
  glass-action-shine: '#FFFFFF14'
  glass-action-shine-dark: '#FFFFFF1F'
  glass-panel: '#FFFFFF33'
  glass-panel-dark: '#1C1C1E33'
  black: '#000000'
  on-danger-dark: '#FFFFFF'
  danger-container: '#FFEBEA'
  danger-container-dark: '#332021'
  on-danger-container: '#000000'
  on-danger-container-dark: '#FFFFFF'
  surface-low: '#F2F2F7'
  surface-low-dark: '#1C1C1E'
  surface-high: '#E5E5EA'
  surface-high-dark: '#2C2C2E'
  outline: '#8B8B92'
  outline-dark: '#76767E'
typography:
  display:
    fontFamily: Noto Sans SC
    fontSize: 28px
    fontWeight: 700
    lineHeight: '1.15'
    letterSpacing: -0.6px
  title:
    fontFamily: Noto Sans SC
    fontSize: 22px
    fontWeight: 600
    lineHeight: '1.25'
  heading:
    fontFamily: Noto Sans SC
    fontSize: 17px
    fontWeight: 600
    lineHeight: '1.35'
  body:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.45'
  body-emphasis:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.45'
  body-compact:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.4'
  label:
    fontFamily: Noto Sans SC
    fontSize: 13px
    fontWeight: 500
    lineHeight: '1.4'
  caption:
    fontFamily: Noto Sans SC
    fontSize: 12px
    fontWeight: 400
    lineHeight: '1.4'
  micro:
    fontFamily: Noto Sans SC
    fontSize: 11px
    fontWeight: 500
    lineHeight: '1.3'
  numeric:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.3'
  clock:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: 600
    lineHeight: '1.1'
    letterSpacing: -1px
rounded:
  sm: 10px
  md: 14px
  lg: 20px
  xl: 28px
  phone: 38px
  full: 999px
spacing:
  zero: 0px
  hairline: 1px
  micro: 2px
  xxs: 4px
  tight: 6px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  section-title: 28px
  xl: 32px
  xxl: 40px
  section: 48px
  board: 80px
  group: 144px
components:
  phone:
    width: 402px
    height: 874px
    padding: '{spacing.md}'
    backgroundColor: '{colors.canvas}'
    textColor: '{colors.text}'
  phone-dark:
    backgroundColor: '{colors.canvas-dark}'
    textColor: '{colors.text-dark}'
  tablet:
    width: 1194px
    height: 834px
  desktop:
    width: 1440px
    height: 960px
  sidebar:
    width: 244px
    backgroundColor: '{colors.glass}'
    textColor: '{colors.text}'
  status-bar:
    height: 54px
  page-header:
    height: 56px
  page-body:
    height: 632px
  button-primary:
    height: 44px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary-action}'
    textColor: '{colors.on-primary}'
    typography: '{typography.label}'
  button-primary-dark:
    backgroundColor: '{colors.primary-action-dark}'
    textColor: '{colors.on-primary-dark}'
  icon-button:
    size: 44px
    rounded: '{rounded.full}'
  small-button:
    size: 36px
  icon:
    size: 22px
  icon-small:
    size: 16px
  icon-action:
    size: 19px
  icon-feature:
    size: 23px
  icon-large:
    size: 32px
  app-icon:
    size: 52px
    rounded: '{rounded.md}'
    backgroundColor: '{colors.tint}'
    textColor: '{colors.text}'
  device-icon:
    width: 108px
    height: 208px
    rounded: '{rounded.lg}'
  device-hero:
    height: 268px
    rounded: '{rounded.lg}'
  navigation:
    height: 64px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass}'
    padding: '{spacing.xs}'
  navigation-dark:
    backgroundColor: '{colors.glass-dark}'
    textColor: '{colors.text-dark}'
  glass:
    backgroundColor: '{colors.glass}'
    borderColor: '{colors.glass-edge}'
    blur: 12px
    shadowBlur: 16px
    shadowOffset: 4px
    angle: 45
    refractionIndex: 1.1
    refractionWidth: 16px
    dispersion: 0
    magnification: 1
    saturation: 1
    specularThickness: 2px
    specularSharpness: 0.5
    specularSpread: 0.9
    specularIntensity: 0.75
    specularOppositeIntensity: 0.65
    glowThickness: 6px
    glowAngle: 90
    glowSpread: 0.5
    glowIntensity: 0.25
    glowOppositeIntensity: 0.5
  glass-clear:
    backgroundColor: '{colors.glass-clear}'
    textColor: '{colors.text}'
    blur: 4px
  chip:
    height: 32px
    rounded: '{rounded.full}'
    padding: '{spacing.sm}'
  row:
    height: 56px
    gap: '{spacing.sm}'
    verticalPadding: '{spacing.xs}'
    padding: '{spacing.md}'
  row-large:
    height: 64px
  switch-track:
    width: 44px
    height: 28px
    rounded: '{rounded.full}'
  switch-thumb:
    size: 20px
  file-icon:
    size: 44px
  thumbnail:
    size: 112px
    height: 112px
    rounded: '{rounded.sm}'
  remote-screen:
    height: 492px
    rounded: '{rounded.lg}'
  app-screen:
    height: 424px
    rounded: '{rounded.lg}'
  sheet-short:
    height: 304px
  sheet-medium:
    height: 448px
  sheet-long:
    height: 580px
  call-avatar:
    size: 104px
  control-cell:
    height: 64px
  sheet:
    rounded: '{rounded.xl}'
    padding: '{spacing.lg}'
  content-panel:
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
    rounded: '{rounded.lg}'
  content-panel-dark:
    backgroundColor: '{colors.surface-dark}'
    textColor: '{colors.text-dark}'
  secondary-label:
    textColor: '{colors.secondary}'
  secondary-label-dark:
    textColor: '{colors.secondary-dark}'
  status-connected:
    textColor: '{colors.text}'
  status-connected-dark:
    textColor: '{colors.text-dark}'
  status-warning:
    textColor: '{colors.text}'
  status-warning-dark:
    textColor: '{colors.text-dark}'
  status-danger:
    textColor: '{colors.text}'
  status-danger-dark:
    textColor: '{colors.text-dark}'
  canvas-heading:
    height: 96px
  component-board:
    width: 1848px
    height: 420px
  app-cell:
    width: 78px
    height: 84px
  hero-action:
    width: 160px
  remote-clock:
    height: 108px
  hero-label:
    width: 176px
  floating-action:
    width: 196px
  accent-coral:
    backgroundColor: '{colors.accent-coral-soft}'
    textColor: '{colors.text}'
  accent-coral-dark:
    backgroundColor: '{colors.accent-coral-soft-dark}'
    textColor: '{colors.text-dark}'
  accent-amber:
    backgroundColor: '{colors.accent-amber-soft}'
    textColor: '{colors.text}'
  accent-amber-dark:
    backgroundColor: '{colors.accent-amber-soft-dark}'
    textColor: '{colors.text-dark}'
  accent-mint:
    backgroundColor: '{colors.accent-mint-soft}'
    textColor: '{colors.text}'
  accent-mint-dark:
    backgroundColor: '{colors.accent-mint-soft-dark}'
    textColor: '{colors.text-dark}'
  glass-selection:
    backgroundColor: '{colors.glass-selected}'
    textColor: '{colors.text}'
  glass-selection-dark:
    backgroundColor: '{colors.glass-selected-dark}'
  glass-action:
    backgroundColor: '{colors.glass-action}'
    textColor: '{colors.on-primary}'
  glass-action-dark:
    backgroundColor: '{colors.glass-action-dark}'
    textColor: '{colors.on-primary-dark}'
  icon-blue:
    textColor: '{colors.accent-blue}'
  icon-blue-dark:
    textColor: '{colors.accent-blue-dark}'
  accent-blue:
    backgroundColor: '{colors.accent-blue-soft}'
    textColor: '{colors.text}'
  accent-blue-dark:
    backgroundColor: '{colors.accent-blue-soft-dark}'
    textColor: '{colors.text-dark}'
  icon-coral:
    textColor: '{colors.accent-coral}'
  icon-coral-dark:
    textColor: '{colors.accent-coral-dark}'
  icon-amber:
    textColor: '{colors.accent-amber}'
  icon-amber-dark:
    textColor: '{colors.accent-amber-dark}'
  icon-mint:
    textColor: '{colors.accent-mint}'
  icon-mint-dark:
    textColor: '{colors.accent-mint-dark}'
  glass-panel:
    backgroundColor: '{colors.glass-panel}'
    textColor: '{colors.text}'
  glass-panel-dark:
    backgroundColor: '{colors.glass-panel-dark}'
    textColor: '{colors.text-dark}'
  remote-exit:
    size: 52px
    padding: '{spacing.sm}'
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass-panel}'
    textColor: '{colors.text}'
  remote-exit-peek:
    width: 12px
    height: 52px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass-panel}'
    textColor: '{colors.text}'
  remote-exit-hit:
    width: 44px
    height: 52px
  device-list-item:
    height: 64px
    rounded: '{rounded.lg}'
    padding: '{spacing.md}'
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
  connection-field:
    height: 52px
    rounded: '{rounded.md}'
    padding: '{spacing.md}'
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
  field-block:
    height: 104px
  control-feedback:
    opacity: 0.12
  feature-icon:
    size: 40px
    rounded: '{rounded.md}'
    opacity: 0.1
  empty-content:
    width: 380px
    padding: '{spacing.md}'
    verticalPadding: '{spacing.xxl}'
    gap: '{spacing.lg}'
  empty-content-icon:
    size: 72px
  empty-content-message-gap:
    height: 10px
  pairing-qr:
    size: 176px
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
---

# 邻接 · iOS Liquid Glass 设计规范

## Overview

“邻接”是工作名。以 iOS 中性的系统背景、分组内容和紧凑字体构建互联工具。黑白主题用于主操作、链接和选中图标；普通正文保持黑白中性。鲜蓝、亮红、鲜橙和鲜绿仅用于有功能语义的小面积点缀。设备画面、照片和文件是视觉中心，Liquid Glass 只承担浮动导航与控制。亮红、鲜橙和鲜绿承担危险、文件类型及连接状态等明确语义。

依据 Apple HIG 与 WWDC25/26 的 Liquid Glass 理念，内容构成连续工作画布，导航与控制形成独立光学层。玻璃靠背景透色、渐变边缘光、扩散和离面阴影建立厚度，不把每一段内容包装成白卡或玻璃卡。静态稿表现材料的一帧，不宣称动态折射与平台性能已经验证。

## Colors

浅色使用 #F2F2F7 系统背景、白色分组内容与 #1B1B1F 黑色主题；深色使用黑色系统背景、#1C1C1E 分组内容与 #F2F2F4 浅色主题。主动作在浅色使用黑底白字，在深色使用浅底深字，保持紧凑按钮文字的清晰对比。主题、主动作与功能点缀分别映射，鲜蓝 #007AFF / #0A84FF 只属于 accent-blue，不能替代 primary。Pencil 的 mode=light/dark 将同名语义颜色映射到其 -dark 值。没有深色后缀的媒体遮罩和白色常量保持定义值。

默认采用浅色外观。黑白主题承担主动作与当前区域图标，浅中性透明层承担控制内选择背景；深色作为用户可选外观独立展示。照片等沉浸媒体上的控制可按背景选择深浅材质，不改变全局外观偏好。

媒体保留原色。消息、接续与普通功能入口使用中性文字；有功能语义的小图标可使用鲜蓝等亮色点缀；文件类型使用明亮橙色（不是金色），连接状态使用鲜绿，危险动作使用 iOS 亮红；禁止金色、暗红和暗绿点缀。功能色用于小图标与状态点，正文保持中性以保证阅读对比。彩色主要用于小面积图形与局部透色，不覆盖全页。接听按钮使用鲜绿图标配浅绿底和中性正文，禁止沿用厚重的深绿色实色按钮；拒接/挂断保留清楚的红色语义。连接、警告、失败必须同时有文字或图形。降低透明度时使用 surface，增加对比时保留明确边界；颜色变化不改变操作含义。

## Typography

Noto Sans SC 承担中文；Inter 仅承担时间、数值等。标题通过字重、紧凑行距与内容尺度建立层级，正文保持清晰可读。实现阶段使用对应平台的合适中文系统字体，不为模仿苹果牺牲中文可读性。

设备名、正文、按钮和说明分别使用语义文字角色。大文字状态允许换行与容器增高，不能把字号缩小作为溢出修复。

## Layout

手机在安全区内使用紧凑标题、主要内容和悬浮操作，内容可在滚动时经过控制层背后；重要文字和最终操作不能永久被导航遮挡。设备首页突出真实手机预览，文件用列表，相册用媒体网格，通话以联系人和状态为中心。

同一 mobile.pen 按页面类型组织：设备与工作台、连接与授权、手机与应用、文件与传输、相册与内容、通知与接续、来电与通话、偏好与恢复、平板与桌面。每类使用带标题的一整行，行内安排正常、操作中与异常状态；不再按全局编号机械填充网格。各页面保留独立顶层 Frame，分组标题只作画布导航。

平板与桌面延续对象和任务关系，扩展为侧栏、工作区与详情。参考 2026 修订，大屏侧栏可延伸至窗口边缘，顶部工具栏更有结构；不机械放大手机布局。

## Elevation & Depth

regular 玻璃用于标签栏、导航按钮、控制工具、菜单和弹层；clear 仅用于具有丰富媒体背景且能保证文字对比的控制。正文与列表使用普通内容材料。选中胶囊与父导航处于同一控制平面，不叠完整阴影玻璃。

实时折射使用 glass 的光学参数：折射率 1.1、边缘宽度 16px，regular 模糊 12px、clear 模糊 4px；不附加色散、放大或饱和度变化。specular 使用 2px 带宽、0.5 锐度、45° 轴、0.9 扩展、0.75 强度与 0.65 对侧强度；glow 使用 6px 带宽、90° 轴、0.5 扩展、0.25 强度与 0.5 对侧强度。两种光照按真实背景采样，并保留细白色光学边缘与 16px/4px 柔和阴影。参数来自 liquid_glass_easy 5.0.0 的 LiquidGlassStyle 与 LiquidGlassLight 公开构造器，独立 lens shader 为唯一实时光学路径；不新增截图采样。底层采用 glass 透色，文字区域以 glass-panel 局部保护；clear 在 light/dark 上下文分别使用 glass-clear-panel 的白色/黑色局部保护，图标文字与上下文的 onSurface 一致，禁止在 light 保护层放白色文字，保护层按组件长宽形成椭圆，以接近的中性透明度渐退至 glass-reflection，避免灰色条带和镜面边缘；边缘保留背景透入，不以提高整块不透明度遮住所有折射。运行后端支持 shader 背景滤镜时启用，未支持时保留磨砂材质；降低透明度与高对比时直接使用不透明表面，跳过模糊、折射和反光。具体渲染实现与四端构建证据在技术文档维护。

实时通知使用连续内容行，来源、正文与原应用动作就近呈现；仅标题和正文均为空的系统汇总项不单独占位，有实际内容的汇总继续展示。普通通知未提供预览时明确说明，保留在原手机查看入口，不能把内容受限误判成没有通知。

Pencil 材料用中性透色、细边缘光和柔和阴影表达。主按钮使用 primary-action 黑白主题实色；设备信息、内容列表、快捷入口与表单使用普通内容面，取消装饰渐变和镜面条纹。仅悬浮导航、退出与上下文浮层使用玻璃；远控三键使用独立媒体底色，选中项不再叠一层玻璃。真实远端图像为悬浮控制提供透色依据。大弹层更厚、更扩散，小按钮轻盈。滚动边缘仅出现于实际有内容进入控件后方的区域，文字密集顶栏使用更明确的分离。

动态实现需呈现即时按下反馈、可打断的形变、控件来源关系与内容变化下的对比适配。减少动态效果时保留反馈并减轻空间位移；降低透明度时转实色。这些属于后续运行验证，静态图不能证明其通过。

## Shapes

内容容器统一 20px 圆角，sheet 28px，浮动控制使用完整胶囊或圆形。形状与屏幕、窗口边缘保持同心关系；大内容区、控件、图标与媒体缩略图使用不同语义圆角。胶囊服务导航和操作，图标大小不等于点击区域。内容行靠对齐、空白与必要分隔建立关系。

## Components

- Device hero：设备身份、连接状态与打开手机屏幕动作构成工作台入口；真实屏幕在远控页呈现。
- Floating navigation：设备、传输、设置为稳定目的地；当前区域使用一体选中胶囊，图标与文字同时可辨。
- Glass control：渐变亮边、背景透入与阴影共同说明可操作性；不对每个普通内容行加玻璃。
- Content list：文件与通知保持连续内容节奏，状态与动作就近显示。
- Media controls：相册预览与远控画面保留内容，边缘悬浮工具不污染实际远端触控区域。
- Context sheet：设备切换、质量与同名冲突保留来源上下文；主动作、取消和破坏性动作含义明确。
- Capability state：受限、离线、失效与恢复具有可执行下一步，不以灰按钮代替解释。

图标统一使用 Lucide；远端应用图标在静态稿中用功能图形示意，不绘制第三方商标。录屏、备份、自动编辑回写、专用相机页与独立短信中心不再出现。短信等通知进入手机原应用，通话、文件与相册保留专用页面。

## Do's and Don'ts

- 每页说明当前设备、内容归属和下一步动作；删除、断开和关闭窗口使用不同语义。
- 保持中性系统内容与黑白主题操作，允许功能色图标与小元素点缀；使用明确的色彩角色，避免全灰或大面积品牌染色。
- 内容与控制分层，避免纯白空卡堆叠、全界面玻璃和玻璃叠玻璃。
- 主控不要求调试；连接引导中的调试设置发生在被控手机。
- 唤醒指打开远控画面，不强制点亮实体屏幕，不绕过手机锁屏。
- 预览导出到系统临时目录；Git 只保留设计源文件、规范与必要素材。
- 不以静态设计宣称动态折射、四端编译或真机能力已验收。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[WWDC25 Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[WWDC26 修订](https://developer.apple.com/videos/play/wwdc2026/101/)。详见[研究记录](../docs/research/apple-liquid-glass-redesign.md)。格式：[Google DESIGN.md](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)。行为：[产品设计](prod/README.md)。

彩色图标与标签分工明确：accent 组件的正文使用中性文字，icon 组件映射功能色。soft 色为对应功能色以10%透明度叠加在 surface 上的预合成值，Flutter 的 FeatureIcon 按同一透明度渲染；透明选中层的文字对比按实际背景合成后验证。主动作使用 primary-action 黑白主题实色，按钮按下即时显示浅中性反馈，不做金属斜面。来电拒接使用浅珊瑚与深色文字，接听使用鲜绿点缀，避免大面积红色压过接听；通话中的结束动作保留明确危险语义。设备内容面板使用实色表面，玻璃控制层在深色下避免亮背景使文字失去对比。降低透明度关闭控制材质的半透明、反光和背景模糊，保留功能语义图标色。

移动端控制会话默认沉浸全屏：远端画面占据整个内容区域，移除主控页面标题、额外手机边框和重复系统状态栏。不同屏幕比例保持源画面完整，不拉伸或裁掉远端系统控件；空余区域使用媒体底色，不能恢复为带页头的内嵌播放器。默认导航条使用独立控制空间，画面在剩余区域按比例容纳，不覆盖远端内容。悬浮关闭按钮是唯一退出入口；默认另显示返回、主屏、最近任务三键，设备设置可隐藏三键。主控系统返回发送给远端，不退出页面。按钮拖动连续跟手，松手吸附最近左右边缘并收起，保留侧边把手；点击把手展开、点击展开按钮退出。拖拽释放不能触发退出，退出返回互联工作台，设备连接与其他活动按各自规则继续。收起态使用独立可访问热区，语义为展开退出按钮，按钮信息与触摸均不发送给远端；位置随旋转和安全区域重新约束。降低透明度使用实色按钮，减少动态保留即时定位与反馈。

全屏会话规则同样适用于画质面板、资源不足和断线重连等叠加状态。面板底层仍为整个屏幕的远端内容，不重新插入主控页头、卡片画面或底部工具栏。断线时底层明确为最后一帧，标记画面暂停并停止远端输入；退出按钮始终位于面板之外可触及的位置。工作台和会话列表使用设备/会话状态卡，点击后进入全屏操作，不用裁切的横向屏幕模拟可操作会话。

Pencil 复用规则：移动端远控页面使用同一全屏会话组件，通过画面源、展开/侧边退出、遮罩与上下文面板插槽表达状态；重连、画质、资源不足、文件冲突和回复共用玻璃面板外壳，业务内容作为嵌套组件。主/次按钮、内容行、导航、系统状态栏与手势指示使用组件实例。页面仅覆盖文案、图标、启用状态、位置与有语义的变体，不复制通用材质和尺寸；降低透明度的实色样式属于明确变体。源组件集中在设计系统画布，变更后检查正常、收起、异常、深色与低透明度实例。

首屏是设备列表，单台和多台设备使用同一种设备卡，不设置主手机、备用手机或默认主次层级。在线、离线、检查中、主动断开和需要授权分别呈现；旧状态附时间，电量只在在线可确认时作为当前值。设备工作台在选择设备后进入。连接表单使用可编辑地址、端口及配对码字段，字段错误在原位说明；配对端口与连接端口分开，输入完整才启用提交。二维码由主控出示、被控手机系统扫描。设备卡、表单字段、页头和流程状态优先复用共享组件，页面保留清楚的返回、取消和替代路径。


## Flexible layout contract

设计与实现以相同的内容流和约束工作：页面为纵向 Flex，内容区填充可用空间；文本固定可用宽度并按内容增高，普通列表行以最小高度为基线。手机参考尺寸仅作审阅视口，不能作为缩放因子。窄屏、横屏、键盘与大文字下允许换行和滚动，关键动作始终可达；大屏按可用宽度增加侧栏或内容列。触控区域至少44，按钮视觉紧凑不等于缩小命中区域。

Pencil 工作台以标记为 `scroll-viewport` 的固定视口裁剪完整纵向内容，保留视口以下的会话与设备入口；这类有意的滚动裁剪单独检查，不压缩行高、不删除内容来制造首屏全部可见。

普通页面采用默认 Cupertino/iOS 返回效果；按钮移除 Material 水波与厚重选中层，开关和单选/复选使用 iOS 外观，搜索和分组列表保持中性内容材料。取消手工返回手势与额外形变。外观页仅保留浅色、深色和跟随系统；减少动态、降低透明度和高对比自动尊重系统。远控越界动作静默丢弃，不暂停视频、不显示错误面板。设备音源随打开控制页面自动合并播放，无音源设置页；剪贴板只有设备内自动同步开关，切换即覆盖主控。
