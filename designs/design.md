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
  glass-action: '#1B1B1F'
  glass-action-dark: '#F2F2F4'
  glass-action-shine: '#FFFFFF14'
  glass-action-shine-dark: '#FFFFFF1F'
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
  remote-exit:
    size: 52px
    padding: '{spacing.sm}'
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass}'
    textColor: '{colors.text}'
  remote-exit-peek:
    width: 12px
    height: 52px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass}'
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

本文件定义主控界面的视觉角色、材料用途和响应布局；数值以 frontmatter token 为准。产品入口、对象归属和操作结果由[产品规格](prod/README.md)定义，视觉稿不另建业务模式。

界面以中性的内容层承载设备、文件和状态，以浮动控制层承载导航和局部操作。保留黑白主题，功能图标使用亮色点缀；液态玻璃用于控制层。精简通过信息取舍、对齐和组件一致性实现，不以删除真实状态或缩小文字代替。

## Colors

`primary` 与 `primary-action` 承担主题和主要操作：浅色外观使用黑底白字，深色外观使用浅底深字。`accent-*` 承担功能点缀，不替换黑色主题。蓝色用于一般功能入口，橙色用于文件类型，绿色用于连接或接听，珊瑚红用于危险或拒接语义；同一功能的含义跨页面保持一致。

点缀使用鲜明色与对应 soft 底色，正文、数值和操作标签保持中性文字。金色、暗红、暗绿和紫色装饰不属于本项目的点缀体系。连接、警告和失败同时提供文字或图形依据，颜色不单独承担状态区分。

Pencil `mode=light/dark` 将同名语义变量映射到对应 token；媒体遮罩及白色常量按定义使用。远端画面和媒体保留原色，不套用主控主题。媒体页局部深色控制与全局外观偏好分别处理。降低透明度或提高对比度时使用不透明表面与明确边界。

## Typography

Pencil 的中文使用 Noto Sans SC，时间和数值可使用 Inter；Flutter 使用平台中文系统字体。两者共享语义字号、字重、行高和字距，不以字体文件不同为由重新选择视觉尺度。

页面标题只保留标题，普通列表项不附解释性二级描述。必要信息按职责呈现：

| 内容 | 呈现方式 |
| --- | --- |
| 设备连接状态、文件大小、画质当前值 | 同行状态或尾部数值，不另加一行功能介绍 |
| 通知正文、失败原因、字段校验、传输进度 | 作为真实内容保留，不因清理副描述而删除 |
| 文件来源与目标、同名文件完整路径 | 就近提供可核对信息；受限空间使用详情或提示 |
| 页面用途介绍、普通列表功能解释 | 从标题和列表项移除；仅在实际需要的首次引导中说明操作条件 |

长设备名、路径与放大文字按可用宽度换行、截断并提供完整值，或使容器增高；具体策略随内容职责选择。不能通过全局缩小字号或压低行高修复溢出。

## Layout

设备列表是首页，设备卡呈现身份和真实连接状态；设备工作台组织该设备的功能入口。普通页面使用紧凑页头和内容流，文件采用列表，相册采用媒体网格。相关图标和文字共享对齐线、内容边距与行节奏，数值和尾部操作不挤占标题的必要空间。

### Flexible 布局

布局依据所在父容器的约束决定，不依据整块屏幕宽度放大或缩小设计稿。手机参考尺寸是审阅视口，不是运行时缩放基准。

- 普通页面以纵向 Flex 分配页头、提示和可滚动内容；正文按可用宽度增高。
- 窄容器、横屏、键盘和大文字状态允许换行、堆叠或滚动，末项与主要操作保持可达。
- 大屏根据可用空间呈现侧栏与单一当前内容，不把静态并排示意解释为原生多窗口能力。
- 远控画面、遮罩和浮动操作使用叠加定位；远端画面按源比例容纳，导航键占独立空间。
- 视觉紧凑与命中面积分别控制，最小触控尺寸使用组件 token。

`mobile.pen` 中各状态保持独立顶层 Frame，按任务分类分行。标记为 `scroll-viewport` 的视口可以裁剪完整滚动内容；核对滚动终点和遮挡，不删内容制造首屏完整。画布 Frame 与产品路由的对应见[流程索引](prod/user-flows.md)。

## Elevation & Depth

Liquid Glass 的材料识别来自真实背景的透镜折射、沿形状变化的边缘光、散射与离面阴影。半透明填充与模糊只能表达磨砂材料，不能单独作为液态玻璃成像证据。光学值使用 `glass` 组件 token，不在正文、页面或 shader 使用处另建数值表。

| 对象 | 材料与边界 |
| --- | --- |
| 浮动导航、返回、关闭、工具组、菜单与短暂上下文面板 | regular；兼顾文字保护与真实背景透入 |
| 照片、视频上的紧凑控制 | clear；配亮色前景，必要时由媒体导航区域提供局部暗化 |
| 任意远端应用上的退出控件 | regular；远端可能是白色文字界面，不能仅因属于远控就选择 clear |
| 设备卡、分组内容、表单、文件与通知列表 | 中性内容材料，保持文字和数据清晰 |
| 静态文件名、普通标题、说明文字 | 内容标识，不单独包裹玻璃 |
| 内容流程的主要按钮 | `primary-action` 实色；其强调作用不依赖透明化 |

相关图标动作共享一层玻璃背景，内部图标不再各包一层。文字动作单独组织；导航选中面与父导航处在同一平面，不叠完整玻璃阴影。内容下方没有图像或滚动对象时，不添加装饰图案来制造折射。

媒体控制的渐退保护用于实际可读性，不能把文字保护罩覆盖整块透镜。材料轮廓、高光和阴影使用同一形状关系，避免固定白边、镜面条纹或额外径向遮罩压住折射。普通内容保持清晰，控制层不改变远端图像本身。

Pencil 的 `assets/liquid-glass.glsl` 表达静态光学外观；Flutter 的生产渲染与兼容路径由[工程契约](../docs/implementation/architecture.md)说明。静态稿、Widget 截图与真实 GPU 成像分别验证。支持位、shader 加载成功或单张截图均不等于动态效果与性能通过。

## Shapes

内容面、上下文面板、浮动控制和缩略图使用各自语义圆角。内外形状与间距保持同心关系，胶囊用于导航和操作；图标图形大小与按钮命中区域分别定义。圆角和间距由 token 决定，普通内容行依靠对齐、空白和必要分隔建立关系。

## Components

共享设备卡、页头、内容行、开关、选项、主次动作、浮动导航和侧栏均通过组件实例使用。图标统一为 Lucide；真实应用图标和系统画面属于被控内容，不随主控功能色改绘。

远控正常、收起、画质、资源受限和断线状态共享全屏会话结构，使用画面源、退出控件和上下文插槽表达差异。面板不恢复主控页头或内嵌手机卡片，关闭控件保持可触及；断线最后一帧与触控越界的处理按[交互规则](prod/interaction-rules.md)区分。

共享上下文外壳仅用于真实上下文面板。快捷回复等产品整页使用普通页面结构，不能因为存在可复用面板而改为抽屉。页面实例只覆盖文案、图标、启用状态和明确变体；材料或尺寸变化从母组件及对应规范修改。

## Do's and Don'ts

- 普通路由采用默认 Cupertino/iOS 返回效果；远控的返回映射与唯一关闭出口以产品规则为准，不另加装饰性返回形变。
- 外观设置只提供浅色、深色和跟随系统。文字放大、减少动态、降低透明度和高对比读取系统偏好，不新增产品设置页。
- 动效应具有即时反馈和清楚的来源关系，减少动态时减轻空间位移。动态高光、可打断形变和背景适应分别取得运行证据，不从静态设计推导通过。
- 逐页核对正常与受限状态、明暗外观、长内容和响应布局；母组件一致不替代实例检查。设计状态及运行证据见[逐页审计](../docs/implementation/ios-visual-audit.md)。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。来源与项目判断的区别见[设计研究](../docs/research/liquid-glass-design-review.md)；格式及生成规则见[工具 README](../tool/design_tokens/README.md)。
