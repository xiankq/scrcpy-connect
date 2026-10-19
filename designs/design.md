---
version: alpha
name: 邻接 Interconnect
description: 设备舞台：设备身份与真实内容建立主视觉，黑白内容层之上悬浮液态玻璃导航与操作。
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
    letterSpacing: 0px
  heading:
    fontFamily: Noto Sans SC
    fontSize: 17px
    fontWeight: 600
    lineHeight: '1.35'
    letterSpacing: 0px
  body:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.45'
    letterSpacing: 0px
  body-emphasis:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.45'
    letterSpacing: 0px
  body-compact:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.4'
    letterSpacing: 0px
  label:
    fontFamily: Noto Sans SC
    fontSize: 13px
    fontWeight: 500
    lineHeight: '1.4'
    letterSpacing: 0px
  caption:
    fontFamily: Noto Sans SC
    fontSize: 12px
    fontWeight: 400
    lineHeight: '1.4'
    letterSpacing: 0px
  micro:
    fontFamily: Noto Sans SC
    fontSize: 11px
    fontWeight: 500
    lineHeight: '1.3'
    letterSpacing: 0px
  numeric:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.3'
    letterSpacing: 0px
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
  page-content:
    maxWidth: 720px
  button-primary:
    height: 44px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary-action}'
    textColor: '{colors.on-primary}'
    typography: '{typography.label}'
  button-secondary:
    height: 44px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.surface-high}'
    textColor: '{colors.text}'
    typography: '{typography.label}'
  button-secondary-dark:
    backgroundColor: '{colors.surface-high-dark}'
    textColor: '{colors.text-dark}'
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
    opticalDepth: 70px
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
    backgroundColor: '{colors.primary-action}'
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
  device-identity:
    width: 52px
    height: 72px
    rounded: '{rounded.md}'
  device-identity-showcase:
    width: 84px
    height: 144px
  device-identity-compact:
    height: 44px
  device-list-item-compact:
    height: 64px
  device-list-item:
    height: 108px
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
  selection-field:
    height: 56px
    padding: '{spacing.md}'
    verticalPadding: '{spacing.xs}'
    rounded: '{rounded.md}'
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

界面采用“设备舞台”：以设备身份、真实屏幕和用户内容建立视觉中心，以悬浮的液态玻璃导航和操作建立空间层次。黑白是内容基底，功能图标使用语义亮色。设备与内容应比装饰更醒目；玻璃的记忆点来自透入内容、轮廓折射与操作反馈。

首页以 display 字级和有明确设备轮廓的平等设备卡形成识别，工作台先呈现设备身份与真实连接、能力和保留会话，再进入功能分组。远控与媒体把真实内容铺开，控制退到边缘。连接、文件、设置继续采用安静的工具结构，避免为追求设计感改变用户任务。

简约通过减少注意力竞争实现。每页先确定一个视觉重心：设备工作台的设备、文件详情的文件对象、相册的照片、通话页的当前呼叫。构图、尺度和留白围绕这个对象组织；辅助状态与操作随后展开。页面可以共享控件，同时保留各自内容的形态，不把设备、照片和通知都压成相同的列表。

## Colors

`primary` 与 `primary-action` 承担主题和主要操作：浅色外观使用黑底白字，深色外观使用浅底深字。`accent-*` 承担功能点缀，不替换黑色主题。蓝色用于一般功能入口，橙色用于文件类型，绿色用于连接或接听，珊瑚红用于危险或拒接语义；同一功能的含义跨页面保持一致。

点缀使用鲜明色与对应 soft 底色，正文、数值和操作标签保持中性文字。金色、暗红、暗绿和紫色装饰不属于本项目的点缀体系。连接、警告和失败同时提供文字或图形依据，颜色不单独承担状态区分。

Pencil `mode=light/dark` 将同名语义变量映射到对应 token；媒体遮罩及白色常量按定义使用。远端画面和媒体保留原色，不套用主控主题。媒体页局部深色控制与全局外观偏好分别处理。降低透明度或提高对比度时使用不透明表面与明确边界。

## Typography

Pencil 的中文使用 Noto Sans SC，时间和数值可使用 Inter；Flutter 使用平台中文系统字体。两者共享语义字号、字重、行高和字距，不以字体文件不同为由重新选择视觉尺度。

页面标题只保留标题，普通列表项不附解释性二级描述。必要信息按职责呈现：

| 内容 | 呈现方式 |
| --- | --- |
| 设备连接状态、最近连接时间 | 在设备身份旁形成必要状态区，可占独立行；离线时间不能伪装成实时状态 |
| 文件大小、画质当前值 | 同行状态或尾部数值，不另加一行功能介绍 |
| 通知正文、失败原因、字段校验、传输进度 | 作为真实内容保留，不因清理副描述而删除 |
| 文件来源与目标、同名文件完整路径 | 就近提供可核对信息；受限空间使用详情或提示 |
| 页面用途介绍、普通列表功能解释 | 从标题和列表项移除；仅在实际需要的首次引导中说明操作条件 |

长设备名、路径与放大文字按可用宽度换行、截断并提供完整值，或使容器增高；具体策略随内容职责选择。不能通过全局缩小字号或压低行高修复溢出。

## Layout

设备列表是首页，所有设备卡采用相同层级，不虚构主力设备或实时屏幕。设备卡以设备轮廓、名称、真实状态形成横向构图，标准高度是最小基准，长名称与辅助文字可增高。设备工作台以较大的实体设备轮廓与名称形成不对称主构图；型号与连接状态就近呈现，可用能力与保留会话在分隔线下形成摘要，再接单一黑色屏幕动作和功能分组。轮廓只是设备身份，不伪造远端画面、壁纸或电量。顶层目的地以 display 标题建立入口层级；短横屏收紧为 heading。功能分组标题使用 caption 与 secondary，通过上方 section-title 间距建立层级；普通内容行使用 body 与标准高度，依靠留白和对齐建立关系，不逐行画底线，避免整列加粗；卡片与组头区分分组，分隔仅用于摘要等明确结构边界。下钻页保持紧凑页头和内容流，文件采用列表，相册采用媒体网格。相关图标和文字共享对齐线、内容边距与行节奏，数值和尾部操作不挤占标题的必要空间。

同一设备的一组活动将设备身份提到组头，行内只呈现活动名称与该项操作；不同设备分别成组，停止操作仍归属原活动。普通菜单和选项通过一致的行高、图标槽与尾部对齐建立秩序，末行下方只保留行自身的内容余量。分隔线用于确有结构转换的地方，例如设备身份与能力摘要之间；文件浏览等密集数据视图按实际阅读需要决定相邻项分隔，末行不追加装饰底线。

纯列表的背景容器只负责材料、圆角和裁切，内边距为零；分组高度由各行的实际高度组成，不再叠加一圈上下留白。水平留白、纵向内容余量、最小高度与命中范围由行组件负责。单项与多项分组使用同一行节奏，放大文字时由行增高。包含对象标题、正文或进度的内容卡片使用自身内容内边距；其中嵌入的行显式使用紧凑内嵌变体，避免重复水平缩进。

同级方式使用同一组内的平等入口，以用户可识别的任务命名；差异条件在选择后就近说明。分组表达任务或对象归属，不使用协议代际、技术术语或额外的底部分区制造主次。具体连接名称、授权条件与入口归属由[设备与连接设计](prod/device-connection.md)维护。

### Flexible 布局

布局依据所在父容器的约束决定，不依据整块屏幕宽度放大或缩小设计稿。手机参考尺寸是审阅视口，不是运行时缩放基准。

- 普通页面以纵向 Flex 分配页头、提示和可滚动内容；正文按可用宽度增高。
- 普通页面正文、设备列表主内容与底部动作采用居中的 page-content 阅读列；maxWidth 包含页面原有左右内边距，列内卡片继续扣除该边距。高度与滚动仍使用完整可用空间；侧栏在阅读列外，远控与媒体画面不受此宽度约束。
- 窄容器、横屏、键盘和大文字状态允许换行、堆叠或滚动，末项与主要操作保持可达。
- 大屏根据可用空间呈现侧栏与单一当前内容，不把静态并排示意解释为原生多窗口能力。
- 远控画面、遮罩和浮动操作使用叠加定位；远端画面按源比例容纳，导航键占独立空间。
- 视觉紧凑与命中面积分别控制，最小触控尺寸使用组件 token。

`mobile.pen` 以主要页面、局部状态板、材料与交互板三类对象组织。只有布局或任务结构独立的页面保留完整视口；同一页的校验、进度、空态、结果与菜单在状态板呈现变化部位，不复制状态栏、标题、导航和背景。明暗与降低透明度在材料板集中对照；远控退出拖拽与吸附用局部控件和动作说明表达。状态板保留原状态 ID 与责任页面引用；一个状态 ID 不等于一条路由。标记为 `scroll-viewport` 的视口可以裁剪完整滚动内容；核对滚动终点和遮挡，不删内容制造首屏完整。画布 Frame 与产品路由的对应见[流程索引](prod/user-flows.md)。

## Elevation & Depth

Liquid Glass 的材料识别来自真实背景的透镜折射、沿形状变化的边缘光、散射与离面阴影。半透明填充与模糊只能表达磨砂材料，不能单独作为液态玻璃成像证据。光学值使用 `glass` 组件 token，不在正文、页面或 shader 使用处另建数值表。

玻璃承担内容上方的功能层，让人持续理解正在操作什么，以及控制与下方内容的空间关系。材料随背景获得颜色和深度，控件自身仍保持清楚的形状与命中范围。背景平静时允许材料安静；不靠新增纹理、彩色光斑、重复描边或叠加阴影强行展示玻璃。设备卡、长正文和表单保持稳定的中性实体面，使有限的浮动控制形成明确层次。

| 对象 | 材料与边界 |
| --- | --- |
| 浮动导航、返回、关闭、工具组、菜单与短暂上下文面板 | regular；兼顾文字保护与真实背景透入 |
| 照片、视频上的紧凑控制 | clear；配亮色前景，必要时由媒体导航区域提供局部暗化 |
| 任意远端应用上的退出控件 | regular；远端可能是白色文字界面，不能仅因属于远控就选择 clear |
| 设备卡、分组内容、表单、文件与通知列表 | 中性内容材料，保持文字和数据清晰 |
| 静态文件名、普通标题、说明文字 | 内容标识，不单独包裹玻璃 |
| 内容流程的主要按钮 | `primary-action` 实色；其强调作用不依赖透明化 |

玻璃先满足三个条件：它是实际控制，它浮在真实内容之上，它的形状与来源操作有关。静止时保持清晰薄边与适量散射；按下时局部提亮与轻微形变，释放或取消均可回到当前状态；菜单与工具面板从触发控件扩展，避免无来源地漂入。减少动态用短暂明暗反馈替代弹性位移。

regular 优先保护导航、标签和未知背景上的可读性，允许更充分的散射；clear 优先保留照片与视频，在紧凑操作周围呈现透明边缘和背景弯折。选择依据是背景和阅读任务，不能将 clear 理解为所有玻璃的升级版。明暗外观分别检查前景对比；降低透明度时保留同一形状、层级和操作位置，切换为实体材料。

相关图标动作共享一层玻璃背景，内部图标不再各包一层。文字动作单独组织；导航选中面与父导航处在同一平面，不叠完整玻璃阴影。内容下方没有图像或滚动对象时，不添加装饰图案来制造折射。

媒体控制的渐退保护用于实际可读性，不能把文字保护罩覆盖整块透镜。材料轮廓、高光和阴影使用同一形状关系，避免固定白边、镜面条纹或额外径向遮罩压住折射。普通内容保持清晰，控制层不改变远端图像本身。

评审材料时，使用照片、细线与密集文字作为背景，观察轮廓附近的背景是否连续弯折、散射是否连续、中心内容是否仍能辨认，并确认前景标签清楚。细线或文字出现离散重影时应修正采样；强白边与重模糊不能替代折射。静态稿核对光学目标，运行中再检查背景滚动或视频更新、按下与取消、来源过渡及辅助偏好。任何一项有证据缺口，都保留为未验收项。

Pencil 的 `assets/liquid-glass.glsl` 表达静态光学目标。`glass.opticalDepth` 表示透镜厚度，`refractionWidth` 表示轮廓过渡与相邻形状融合的距离，两者分别控制；更换渲染后端时重新核对 token 映射与实际成像。Flutter 的生产渲染、初始化与兼容路径由[工程契约](../docs/implementation/architecture.md)维护。静态稿、Widget 截图与真实 GPU 成像分别验证，动态交互与性能由运行证据确认。

## Shapes

内容面、上下文面板、浮动控制和缩略图使用各自语义圆角。内外形状与间距保持同心关系，胶囊用于导航和操作；图标图形大小与按钮命中区域分别定义。圆角和间距由 token 决定，普通内容行依靠留白和对齐建立关系，不逐行画底线；卡片与组头区分分组，分隔仅用于摘要等明确结构边界。

## Components

共享设备卡、页头、内容行、开关、选项、主次动作、浮动导航和侧栏均通过组件实例使用。输入框用 connection-field，已选值与标签同时显示的选择框用 selection-field；标签保留在填充面内，候选项在点击后展开，不把完整候选集铺成一排同权胶囊。普通与选项行使用 row 最小高度，依靠留白和对齐，不逐行画底线；有图标时标题从图标宽度加 row gap 后开始，无图标时贴内容左缘。卡片与组头区分分组，分隔仅用于摘要等明确结构边界。开关的轨道与拇指尺寸使用 switch token，命中区域独立达到 icon-button；选中、开关和主要动作使用黑白主题，绿色不作为所有启用状态的通用颜色。次动作使用 button-secondary 的中性实体与 label 字级，文字动作保持透明背景与同一 label 字级。图标统一为 Lucide；真实应用图标和系统画面属于被控内容，不随主控功能色改绘。

远控正常、收起、画质、资源受限和断线状态共享全屏会话结构，使用画面源、退出控件和上下文插槽表达差异。面板不恢复主控页头或内嵌手机卡片，关闭控件保持可触及；断线最后一帧与触控越界的处理按[交互规则](prod/interaction-rules.md)区分。

共享上下文外壳仅用于真实上下文面板。快捷回复等产品整页使用普通页面结构，不能因为存在可复用面板而改为抽屉。页面实例只覆盖文案、图标、启用状态和明确变体；材料或尺寸变化从母组件及对应规范修改。

## Do's and Don'ts

- 普通路由采用默认 Cupertino/iOS 返回效果；远控的返回映射与唯一关闭出口以产品规则为准，不另加装饰性返回形变。
- 外观设置只提供浅色、深色和跟随系统。文字放大、减少动态、降低透明度和高对比读取系统偏好，不新增产品设置页。
- 动效应具有即时反馈和清楚的来源关系，减少动态时减轻空间位移。动态高光、可打断形变和背景适应分别取得运行证据，不从静态设计推导通过。
- 逐页核对正常与受限状态、明暗外观、长内容和响应布局；母组件一致不替代实例检查。设计状态及运行证据见[逐页审计](../docs/implementation/ios-visual-audit.md)。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。来源与项目判断的区别见[设计研究](../docs/research/liquid-glass-design-review.md)；格式及生成规则见[工具 README](../tool/design_tokens/README.md)。
