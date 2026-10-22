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
  canvas-label: '#808080'
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
  list-icon-blue: '#007AFF'
  list-icon-amber: '#FF9F0A'
  list-icon-mint: '#30D158'
  list-icon-coral: '#F03D32'
  list-icon-slate: '#6B7E9F'
  list-icon-purple: '#AF52DE'
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
  sidebar-compact:
    width: 180px
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
  glass-interaction:
    scale: 1.05
    stretch: 0.5
  glass-materialize:
    scale: 1.15
  sheet-handle:
    width: 36px
    height: 4px
    padding: 8px
  scroll-edge:
    opacity: 0.9
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
  navigation-lens:
    refractionIndex: 1.1
    opticalDepth: 20px
    specularIntensity: 2
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
  notification-card:
    height: 190px
  switch-track:
    width: 44px
    height: 28px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary-action}'
  switch-thumb:
    size: 20px
  file-icon:
    size: 44px
  file-document-preview:
    width: 42px
    height: 54px
    rounded: 5px
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
  type-cell:
    height: 60px
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
    textColor: '{colors.canvas-label}'
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
  media-protection:
    height: 64px
  feature-icon:
    size: 40px
    rounded: '{rounded.md}'
    opacity: 0.1
  list-icon:
    size: 28px
    rounded: 6px
    backgroundColor: '{colors.list-icon-blue}'
    textColor: '{colors.white}'
  list-icon-glyph:
    size: 20px
  list-icon-amber:
    backgroundColor: '{colors.list-icon-amber}'
  list-icon-mint:
    backgroundColor: '{colors.list-icon-mint}'
  list-icon-coral:
    backgroundColor: '{colors.list-icon-coral}'
  list-icon-slate:
    backgroundColor: '{colors.list-icon-slate}'
  list-icon-purple:
    backgroundColor: '{colors.list-icon-purple}'
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

首页以 display 字级和有明确设备轮廓的平等设备卡形成识别，工作台先集中呈现设备信息、真实连接状态与屏幕主动作，再以真实后台应用宫格和内容快捷区承接操作，设置与管理随后展开。远控与媒体把真实内容铺开，控制退到边缘。连接、文件、设置继续采用安静的工具结构，避免为追求设计感改变用户任务。

简约通过减少注意力竞争实现。每页先确定一个视觉重心：设备工作台的设备、文件详情的文件对象、相册的照片、通话页的当前呼叫。构图、尺度和留白围绕这个对象组织；辅助状态与操作随后展开。页面可以共享控件，同时保留各自内容的形态，不把设备、照片和通知都压成相同的列表。

## Colors

`primary` 与 `primary-action` 承担主题和主要操作：浅色外观使用黑底白字，深色外观使用浅底深字。`accent-*` 承担功能点缀，不替换黑色主题。蓝色用于一般功能入口，橙色用于文件类型，绿色用于连接或接听，珊瑚红用于危险或拒接语义；同一功能的含义跨页面保持一致。

列表功能图标使用 `list-icon`：28px 实色方块、6px 小圆角、20px Lucide 图形。按内容分配 `list-icon-*` 语义色：中性资料、常规设置与导航用灰蓝，画面、显示与独立应用用亮紫，网络和连接用蓝，电量、健康和活动用亮绿，亮屏、提醒、诊断及文件／硬件工具用亮橙，锁屏、断开和移除用珊瑚红；不将所有项目统一为蓝色，也不为凑颜色随机分配。所有彩色底功能图标统一使用白色图形，不因底色不同改为黑色；明暗外观沿用同一配色，不将绿色、橙色压暗。设置、功能入口与活动等同类列表统一使用，不能混入裸彩色线框或浅色透明底。行高与父组内边距不因增加底色而变化，标题按图标实际宽度加行间距对齐。

正文、数值和操作标签保持中性文字；空状态等较大说明图标继续使用 `feature-icon` 的低透明语义底。设备轮廓、真实应用图标、文件缩略图、导航和尾部操作保留各自角色，不套列表图标方块。不使用金色、暗红或暗绿替代语义亮色，紫色仅用于对应功能图标，不扩散为页面装饰。连接、警告和失败同时提供文字或图形依据，颜色不单独承担状态区分。

Pencil `mode=light/dark` 将同名语义变量映射到对应 token；媒体遮罩及白色常量按定义使用。主控页面导航、全局底部导航和远端底部三键导航的背景、图标与分隔线必须绑定 `surface`、`text`、`muted` 等主题语义变量，不得写死为固定黑底白字或白底黑字。远端画面和媒体保留原应用内容，不随主控明暗主题重着色；媒体页局部深色控制与全局外观偏好分别处理。降低透明度或提高对比度时使用不透明表面与明确边界。

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

设备列表是首页，所有设备卡采用相同层级，不虚构主力设备或实时屏幕。设备卡以设备轮廓、名称、真实状态形成横向构图，状态图标居中放在手机轮廓内，右侧只保留状态文字；在线、连接中、离线和待授权分别使用对应图形与语义色，设备工作台与大屏沿用同一规则，标准高度是最小基准，长名称与辅助文字可增高。设备工作台的名称只在顶栏呈现；首卡用小型实体设备轮廓与型号、连接方式和真实状态形成紧凑摘要，轮廓与右侧摘要居中对齐，实时电量和充电状态、地址与连接端口也在摘要列内呈现，长值换行并使卡片增高，再接单一黑色屏幕或连接动作。摘要可点击进入设备数据页，Android版本等详细数据只在该页展示。字段值使用 body，辅助信息使用 caption；长地址与大字自然换行，不把地址另移到图标下方，不在下方重复设备信息。“活跃应用”区域采用 app-icon 与自适应宫格，取自目标设备的原始图标保持原貌，不染色；“快捷操作”位于活跃应用之前，快捷入口与活跃应用共用 app-icon 的 52px 外框尺度，功能图形使用 icon-large 的 32px，保留语义实色底；窄屏与大字时按可用宽度换行。下方依次为设备设置、连接能力和设备管理，固定设置行均有 list-icon 左图标，设备名称、连接配置、转为IP连接归入设备设置，画面设置以独立行展示当前值；职责见[信息架构](prod/information-architecture.md#设备工作台)。轮廓只是设备身份，不伪造远端画面、壁纸或电量。顶层目的地以 display 标题建立入口层级，滚动后收紧为 heading，栏高与视口保持稳定；短横屏直接使用紧凑标题。功能分组标题使用 caption 与 secondary，通过上方 section-title 间距建立层级；普通内容行使用 body 与标准高度，依靠留白和对齐建立关系，不逐行画底线，避免整列加粗；组头与留白区分列表分组，分隔仅用于摘要等明确结构边界。下钻页保持紧凑页头和内容流；文件页从可回溯路径与页头工具直接开始，共享存储首页不重复设备归属，目录内以紧凑设备来源行标明对象；类型入口只在共享存储首页出现，文件夹与目录内文件默认共用紧凑网格，可切换为同一列表模式，相册继续使用媒体网格。相关图标和文字共享对齐线、内容边距与行节奏，数值和尾部操作不挤占标题的必要空间。

文件管理页使用 `surface` 页面内容底，文件缩略区使用 `surface-low`，保持页面与内容承载面可辨；文件搜索页和实时通知页继续使用 `canvas` 页面底，使白色输入字段和通知卡片保持明确边界。文件类型入口直接以两列自适应宫格开始，不另加“文件类型”标题或范围说明，单项最小高度 60px，采用 list-icon 与 body 标签；文档、媒体等类别使用既有语义色，不把整块入口改成彩色卡片。名称搜索由页头放大镜进入独立文件搜索页；搜索页始终以列表呈现结果，不跟随文件页的网格／列表视图切换，也不在结果区提供视图切换。查询条件中，名称输入与文件类型选择并排在同一行且同高，类型控件只显示当前选值，不重复字段标签。文件页的视图与排序入口固定在页头工具组，不长期占用一整行内容空间；视图、排序键和方向作为本机偏好持久化，下次进入或重启后继续沿用。手机参考宽度使用四列自适应网格，文件夹和文件按当前排序连续呈现，不显示“文件夹”“文件”分组标题或组计数，二者共用缩略区、名称与元数据关系；文件夹使用目录图形，文件使用真实预览或类型图形。网格条目在缩略区下方的名称、日期与大小统一居中对齐，长名称换行后仍以缩略区中线为中心；条目高度由内容决定，不强制文件夹与文件使用同一固定高度。列表模式复用 row 的 56px 基准高度、16px 水平内容边距、28px 语义图标槽与尾部进入箭头；文件夹在尾部显示完整修改日期，文件以月/日和最多两位小数的大小合并在同一尾部信息区，不增加解释行。搜索页复用同一内容行，名称与完整父目录用于区分同名结果，大小和进入箭头位于尾部。网格名称、日期与大小形成清晰的三层信息，名称或元数据增长时增高而非全局缩字。文件页不逐项套外层卡片，网格缩略区只承载内容预览；缩略图失败时在预览区内只显示紧凑重试入口，不重复文件名或说明。

传输以单一紧凑列表呈现，每行使用 body 常规文件名、caption 收发方向与设备和真实状态，活动项提供细进度与百分比；批次只出现一次，点击查看逐项结果。尾部菜单提供移除记录或停止并移除，行高随文字增长，不使用多层大卡堆叠摘要。浅色底栏保留单一玻璃面，以既有 glass-low-edge 的细内轮廓和 glass 阴影分离浅底，保留折射与亮边；深色和降低透明度各自保留对应材料。

同一设备的一组活动将设备身份提到组头，行内只呈现活动名称与该项操作；不同设备分别成组，停止操作仍归属原活动。普通菜单和选项通过一致的行高、图标槽与尾部对齐建立秩序，末行下方只保留行自身的内容余量。分隔线用于确有结构转换的地方，例如设备身份与能力摘要之间；文件浏览等密集数据视图按实际阅读需要决定相邻项分隔，末行不追加装饰底线。文件视图与排序菜单使用生产 `GlassMenu` 的 regular 液态玻璃后端，从页头触发控件展开并保留可识别的透明采样、边缘光和离面层次；按“视图／排序／顺序”分组并使用玻璃分隔。每项最小 44px 命中高度，当前值以尾部对勾表达，选择后立即更新当前目录与本机偏好，不另加“应用”按钮。文件页处于子目录时，顶部返回按钮和系统返回先返回上一级目录；到达共享存储根目录后才退出文件管理路由。

固定数量的设置、能力和选项按任务放入分组卡片：surface 实体白底（深色为 surface-dark）、content-panel 的 lg 圆角，组内上下使用 spacing.xxs 余量，行沿用 row 的 56px 最小高度、16px 水平内距与 12px 图文间距；组头置于卡片外。设备设置、连接能力、设备管理、外观和画面设置选项均使用此结构。动态的应用、文件、传输、活动与发现结果按项延迟构建，不把完整结果集合装入一张总卡片；独立对象的卡片不受此限制。全部应用使用 list-icon 的 28px 原始应用图标，每行保留 row 内距，项间增加 spacing.xxs，列表上下使用 spacing.xs，避免图标相贴；活跃应用宫格继续使用 52px 原始图标。水平留白、纵向内容余量、最小高度与命中范围由行组件负责，放大文字时由行增高。设备身份摘要等独立对象使用自身内容卡片。实时通知参考手机下拉通知栏：每条为独立中性圆角卡片，真实应用图标与名称形成来源行，时间安静右对齐，标题和正文在其下自然换行；整卡可点击，已读（清除）就近提供，不叠加进入原应用按钮、快捷回复或外层总卡片。

添加设备使用单一页面外壳：固定高度的“发现设备”入口行放在上方，使用标准 `row` 组件，点击进入发现二级页；结果列表、空态和进度由二级页呈现，不嵌入添加表单。入口下方使用一条连续图文 Tab 切换配对码、扫码、USB、IP：四项等宽，每项上方为 `icon` 图标、下方为 `caption` 小文字，间距使用 `spacing.xxs`，标准高度复用 `navigation.height`；去除逐项胶囊背景；配对码、扫码、USB、IP 图标分别使用 `accent-blue`、`accent-mint`、`accent-amber`、`accent-coral` 功能色，未选中时仍保留颜色，文字与底部短线以黑白前景强度标明当前项。表单或授权内容原位替换；大字时允许整条增高或横向滚动，标签不缩小命中区域，当前方式保持可见。共享外壳与入口由母组件维护，各模式只替换内容插槽；扫码、USB 和 IP 的完整 Frame 表示同页形式，不建立各自的表单层级。具体默认形式、字段与取消规则见[设备与连接设计](prod/device-connection.md#添加与无线连接)。

连接尝试，以及手机屏幕、独立应用窗口等新画面在请求提交后尚未取得首个可信画面时，均以整页环境场承接等待：低饱和蓝、薄荷、紫色与珊瑚色雾缓慢移动，三枚小光点沿独立椭圆轨道漂移并呼吸，中心不显示任务文字。环境场只表示请求仍在进行，不表示百分比、授权成功或应用已打开；连接页保留顶部返回和底部“取消本次尝试”，画面启动保留底部“取消打开”，系统返回在等待期同样取消本次打开。减少动态效果时冻结在清晰可读的静态构图，不循环播放；不把该系统偏好解释为取消操作。

添加表单在方式 Tab 之后使用共享的“ADB 私钥”来源选择字段，默认显示“全局私钥”；选择“设备专属私钥”时就地展开多行 PEM 输入和从文件选择，复用全局私钥输入组件，提交仍使用当前表单的主动作。连接配置页与添加设备共用同一外壳、四种方式 Tab、私钥来源、方式内容与连接帮助，隐藏发现设备入口并自动收起其空间，私钥来源置灰仅查看，不提供切换、PEM编辑或导入；其余已知字段显示原设备的可复用值。连接配置不另画一套连接方式下拉和地址表单，诊断和能力页不重复放置这些编辑入口。发现页只呈现结果列表与发现状态，空态或错误仅提供重新查找，页头左侧返回、右侧刷新；每项按名称、IP:端口、信任状态三行排列，IP位于中间一行，IPv6采用[地址]:端口。添加表单随后直接进入字段或必要步骤，不再重复使用 display、title 或 heading 描述当前表单。输入值、字段标签和授权步骤使用 body 常规字重；浮动标签、字段辅助、校验和简短条件说明使用 caption，按钮沿用 label。USB 的两端操作用同级正文标明对象，不另配重复功能大图标或加粗标题；二维码只保留短指令与码本身，“重新生成”使用全宽黑色圆角主按钮。四表单辅助文字统一使用caption与secondary，内容到主动作、主动作到连接帮助的间距由共享外壳统一。完整教程与网络条件放入“连接帮助”，动态错误和真实进度按当前状态呈现。

发现设备、配对结果、二维码失效、USB 授权进度、重新授权和连接诊断沿用上述正文与辅助字级。状态图标、简短状态文字及就近的恢复动作共同表达当前结果，不再在正文重复页面任务标题；诊断说明紧邻对应检查项，不把多项原因集中堆在列表末尾。主动取消使用中性反馈，真实失败保留错误语义。实际系统授权示意保留系统自身的层级。相关页面的连接方式与动作名称保持一致，原位切换仍使用同一添加表单，不重新引入独立的连接方式表单页。

同级方式使用同一组内的平等入口，以用户可识别的任务命名；差异条件在选择后就近说明。分组表达任务或对象归属，不使用协议代际、技术术语或额外的底部分区制造主次。具体连接名称、授权条件与入口归属由[设备与连接设计](prod/device-connection.md)维护。

### Flexible 布局

布局依据所在父容器的约束决定，不依据整块屏幕宽度放大或缩小设计稿。手机参考尺寸是审阅视口，不是运行时缩放基准。

- 普通页面的滚动视口延伸到透明页头及浮动导航背后；首屏避让放在滚动内容内部，随内容一起离开。页头背景透明；内容层的顶部保护限定在安全区与实际标题栏高度内，末段以 spacing.lg 渐退并在工具栏底部完全透明，避免覆盖静止时第一项正文。保护位于玻璃采样层之后，不给 AppBar 添加实体底色。恢复提示置于同一内容流；加载与失败状态保留安全阅读区域。正文按可用宽度增高。
- 普通页面正文、设备列表主内容与底部动作采用居中的 page-content 阅读列；maxWidth 包含页面原有左右内边距，列内卡片继续扣除该边距。高度与滚动仍使用完整可用空间；侧栏在阅读列外，远控与媒体画面不受此宽度约束。
- 窄容器、横屏、键盘和大文字状态允许换行、堆叠或滚动，末项与主要操作保持可达。
- 大屏根据可用空间呈现侧栏与单一当前内容；短横屏使用紧凑侧栏，让大字、安全区与首个设备同时可见，不让底部导航占满正文。侧栏保留目的地文字与独立命中，不把静态并排示意解释为原生多窗口能力。
- 远控画面、遮罩和浮动操作使用叠加定位；远端画面按源比例容纳，导航键占独立空间。
- 视觉紧凑与命中面积分别控制，最小触控尺寸使用组件 token。

设计稿分组、规范板与状态板的说明标题使用固定的 `canvas-label` 中灰色，在编辑器浅色与深色画布上均保持可见；它们属于稿件标注，不随产品页面的明暗文字色切换。 规范、组件、材料对照与局部状态的大画布载体统一使用 `canvas` 浅灰底，衬托白色组件并看清边界；这是稿件展示背景，组件自身、材料样本内容及完整产品页面沿用各自配色。

`mobile.pen` 按三块区域组织：最左侧的规范、共享组件与材料板纵向排列；中间完整屏幕按页面类型分行，每行最多八张，超出后续行；右侧集中弹窗、反馈与其他非屏幕细节。规范与细节的独立底板加宽并保留更大的内部左边距，细节板的标准局部组件每行可容纳至少五个，组件保留自然尺寸。主要页面、局部状态板、材料与交互板分别表达内容归属。只有布局或任务结构独立的页面保留完整视口；同一页的校验、进度、空态、结果与菜单在状态板呈现变化部位，不复制状态栏、标题、导航和背景。明暗与降低透明度在材料板集中对照；远控退出拖拽与吸附用局部控件和动作说明表达。状态板保留原状态 ID 与责任页面引用；一个状态 ID 不等于一条路由。标记为 `scroll-viewport` 的视口可以裁剪完整滚动内容；核对滚动终点和遮挡，不删内容制造首屏完整。画布 Frame 与产品路由的对应见[流程索引](prod/user-flows.md)。

## Elevation & Depth

Liquid Glass 的材料识别来自真实背景的透镜折射、沿形状变化的边缘光、散射与离面阴影。半透明填充与模糊只能表达磨砂材料，不能单独作为液态玻璃成像证据。光学值使用 `glass` 组件 token，不在正文、页面或 shader 使用处另建数值表。

玻璃承担内容上方的功能层，让人持续理解正在操作什么，以及控制与下方内容的空间关系。材料随背景获得颜色和深度，控件自身仍保持清楚的形状与命中范围。背景平静时允许材料安静；不靠新增纹理、彩色光斑、重复描边或叠加阴影强行展示玻璃。设备卡、长正文和表单保持稳定的中性实体面，使有限的浮动控制形成明确层次。

| 对象 | 材料与边界 |
| --- | --- |
| 浮动导航、返回、关闭、工具组、菜单、提示、确认/编辑弹窗、底部抽屉与远控恢复面板 | regular；兼顾文字保护与真实背景透入，路由外壳透明，实际内容由同一片材料承载 |
| 照片、视频上的紧凑控制 | clear；配亮色前景，必要时由媒体导航区域提供局部暗化 |
| 任意远端应用上的退出控件 | regular；远端可能是白色文字界面，不能仅因属于远控就选择 clear |
| 设备卡、分组内容、表单、文件与通知列表 | 中性内容材料，保持文字和数据清晰 |
| 静态文件名、普通标题、说明文字 | 内容标识，不单独包裹玻璃 |
| 内容流程的主要按钮 | `primary-action` 实色；其强调作用不依赖透明化 |

玻璃先满足三个条件：它承载实际操作或短暂反馈，它浮在真实内容之上，它的形状与来源操作有关。静止时保持清晰薄边与适量散射；按下时立即响应触点，产生局部提亮与轻微轴向形变，释放或取消后以弹簧归位，再次按压从当前形状与速度继续，不能重置跳帧。共享工具组观察交互，不夺取内部按钮、滚动和拖拽的手势归属。菜单围绕触发控件展开；对话框采用材质化出入场，抽屉保留可打断的路由拖拽与内容滚动。减少动态保留明暗反馈，关闭空间形变与弹性位移；降低透明度保留相同轮廓、操作与焦点，改用实体材料。贴底抽屉只圆化上角，实体分支不额外圆化下角。

regular 优先保护导航、标签和未知背景上的可读性，允许更充分的散射；clear 优先保留照片与视频，在紧凑操作周围呈现透明边缘和背景弯折。选择依据是背景和阅读任务，不能将 clear 理解为所有玻璃的升级版。明暗外观分别检查前景对比；降低透明度时保留同一形状、层级和操作位置，切换为实体材料。

相关图标动作共享一层玻璃背景，内部图标不再各包一层。正文必须确实滚入控制后方，不能只给栏涂透明色而把正文起点固定在栏下。顶部渐退保护覆盖安全区与实际栏高，放在透镜采样前；底部留白计入导航与键盘，末项能完整滚到操作层上方。顶部非操作区域阻止误点被遮住的内容，同时将纵向拖动交还正文滚动。

同页、同材质、同平面的前景控制共用折射层；内容背景先绘制，不能把不透明页面背景混入该层。菜单浮层保持自己的空间与生命周期。文字动作单独组织。底部导航保留原版控件的目的地、语义和手势；静止选中镜片使用库公开的光学组件，与交互镜片交接，不重复绘制外栏。静止选中项也呈现可辨的镜片轮廓、边缘光与轻微离面阴影，浅色背景下仍可识别选中位置；按压、横向拖动和归位延续 clear 镜片反馈。库默认的静止填充不能代替实际镜片；验收需确认松手并稳定后的光学成像。镜片保留上游基线的克制折射、光照与交互，不以更高折射率或更强透明度作为验收目标。`navigation-lens` 仅记录该基线的静态投影参数。原版的镜片采样包含父栏，不能将静态稿画成完全绕过外栏底色与散射的窗口。外轮廓来自曲面折射、明暗与离面阴影，不额外叠加整圈固定描边，也不在整栏外重复包玻璃。受控选择始终对应真实目的地；减少动态关闭弹性位移与缩放，降低透明度或提高对比度切换为实体导航与清楚选中面。内容下方没有图像或滚动对象时，不添加装饰图案来制造折射。

媒体控制使用控制区下方的渐退保护：`media-shade` 覆盖实际控制高度及对应安全区，再以 `media-protection.height` 的距离渐退。保护区随大字和内容高度增长，先于玻璃绘制，不在透镜上方涂黑或拦截触摸。材料轮廓、高光和阴影使用同一形状关系，避免固定白边、镜面条纹或额外径向遮罩压住折射。普通内容保持清晰，控制层不改变远端图像本身。

评审材料时，使用照片、细线与密集文字作为背景，观察轮廓附近的背景是否连续弯折、散射是否连续、中心内容是否仍能辨认，并确认前景标签清楚。细线或文字出现离散重影时应修正采样；强白边与重模糊不能替代折射。静态稿核对光学目标，运行中再检查背景滚动或视频更新、按下与取消、来源过渡及辅助偏好。任何一项有证据缺口，都保留为未验收项。

Pencil 的 `assets/liquid-glass.glsl` 表达静态光学目标。`glass.opticalDepth` 表示透镜厚度，`refractionWidth` 表示轮廓过渡与相邻形状融合的距离，两者分别控制；更换渲染后端时重新核对 token 映射与实际成像。Flutter 的生产渲染、初始化与兼容路径由[工程契约](../docs/implementation/architecture.md)维护。静态稿、Widget 截图与真实 GPU 成像分别验证，动态交互与性能由运行证据确认。

## Shapes

内容面、上下文面板、浮动控制和缩略图使用各自语义圆角。内外形状与间距保持同心关系，胶囊用于导航和操作；图标图形大小与按钮命中区域分别定义。圆角和间距由 token 决定。

## Components

共享设备卡、页头、内容行、开关、选项、主次动作、浮动导航和侧栏均通过组件实例使用。输入框用 connection-field，已选值与标签同时显示的选择框用 selection-field；标签保留在填充面内，候选项在点击后展开，不把完整候选集铺成一排同权胶囊。普通与选项行使用 row 最小高度；有图标时标题从图标宽度加 row gap 后开始，无图标时贴内容左缘。内容分组和分隔规则见 Layout。开关的轨道与拇指尺寸使用 switch token，命中区域独立达到 icon-button；选中、开关和主要动作使用黑白主题，绿色不作为所有启用状态的通用颜色。次动作使用 button-secondary 的中性实体与 label 字级，文字动作保持透明背景与同一 label 字级。图标统一为 Lucide；真实应用图标和系统画面属于被控内容，不随主控功能色改绘。

远控正常、侧边收起、快捷展开、熄屏／锁定、资源受限和断线状态共享全屏会话结构，使用画面源、可展开悬浮快捷控件和上下文插槽表达差异。画面背景延伸至视口顶部，主控工具独立遵循安全区；熄屏／锁定时下部自动出现单击直接亮屏图标，不用模态提示、重新检查或二次确认。面板不恢复主控页头或内嵌手机卡片，关闭控件保持可触及；断线最后一帧与触控越界的处理按[交互规则](prod/interaction-rules.md)区分。

应用打开方式弹层仅保留应用名称、两种打开动作和取消；两个动作纵向排列，使用12px间距，取消另行留白。不用固定坐标的按钮底板与独立文字层拼接，复用主／次动作组件并随容器宽度排布。

共享上下文外壳仅用于真实上下文面板。从通知接续原应用等产品整页使用普通页面结构，不能因为存在可复用面板而改为抽屉。页面实例只覆盖文案、图标、启用状态和明确变体；材料或尺寸变化从母组件及对应规范修改。

## Do's and Don'ts

- 普通路由采用默认 Cupertino/iOS 返回效果；远控的返回映射与唯一关闭出口以产品规则为准，不另加装饰性返回形变。
- 外观设置只提供浅色、深色和跟随系统。文字放大、减少动态、降低透明度和高对比读取系统偏好，不新增产品设置页。
- 动效应具有即时反馈和清楚的来源关系，减少动态时减轻空间位移。动态高光、可打断形变和背景适应分别取得运行证据，不从静态设计推导通过。
- 逐页核对正常与受限状态、明暗外观、长内容和响应布局；母组件一致不替代实例检查。设计状态及运行证据见[设计还原记录](../docs/implementation/design-fidelity.md)。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。来源与项目判断的区别见[设计研究](../docs/research/liquid-glass-design-review.md)；格式及生成规则见[工具 README](../tool/design_tokens/README.md)。
