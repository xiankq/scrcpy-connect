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
    fontFamily: MiSans
    fontSize: 28px
    fontWeight: 700
    lineHeight: '1.15'
    letterSpacing: -0.6px
  title:
    fontFamily: MiSans
    fontSize: 22px
    fontWeight: 600
    lineHeight: '1.25'
    letterSpacing: 0px
  heading:
    fontFamily: MiSans
    fontSize: 17px
    fontWeight: 600
    lineHeight: '1.35'
    letterSpacing: 0px
  body:
    fontFamily: MiSans
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.45'
    letterSpacing: 0px
  body-emphasis:
    fontFamily: MiSans
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.45'
    letterSpacing: 0px
  body-compact:
    fontFamily: MiSans
    fontSize: 14px
    fontWeight: 400
    lineHeight: '1.4'
    letterSpacing: 0px
  label:
    fontFamily: MiSans
    fontSize: 13px
    fontWeight: 500
    lineHeight: '1.4'
    letterSpacing: 0px
  caption:
    fontFamily: MiSans
    fontSize: 12px
    fontWeight: 400
    lineHeight: '1.4'
    letterSpacing: 0px
  micro:
    fontFamily: MiSans
    fontSize: 11px
    fontWeight: 500
    lineHeight: '1.3'
    letterSpacing: 0px
  numeric:
    fontFamily: MiSans
    fontSize: 14px
    fontWeight: 600
    lineHeight: '1.3'
    letterSpacing: 0px
  clock:
    fontFamily: MiSans
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

以设备身份、真实画面与用户内容为视觉中心，黑白内容层上悬浮玻璃控制。产品行为见[产品规格](prod/README.md)。数值以 frontmatter token 为准，Flutter 常量由[工具](../tool/design_tokens/README.md)生成；`px` 对应逻辑像素。

## Colors

主要动作浅色黑底白字、深色浅底深字。功能点缀遵循语义：常规资料／设置灰蓝，画面紫，连接蓝，电量／活动绿，提醒／诊断／文件工具橙，锁屏／移除红。`list-icon` 使用实色底、白色 Lucide 图形，明暗不改配色；空态用 `feature-icon` 淡底。真实应用图标、设备轮廓和缩略图保留自身角色。

主控导航、图标与分隔绑定主题语义色，远端画面不重着色。状态同时有文字或图形依据。降低透明度／提高对比度使用实体面。

## Typography

设计稿统一 MiSans；运行代码继承框架与平台默认字体，不指定家族或打包设计字体。字号、字重、行高与字距仍沿用 token；生成字体家族元数据仅描述稿件。

页头只保留标题，普通列表不加用途说明；真实状态、通知正文、错误、校验、进度及来源目标保留。文件大小／当前值就近放同行，长值允许换行、增高或提供全文，不能全局缩字修复溢出。

## Layout

- 设备卡平等，以轮廓、名称和真实状态为中心，状态图标放轮廓内。工作台名称只在顶栏，摘要放型号、连接、电量与端点并进入设备数据；快捷操作在活跃应用前，两者用 `app-icon` 尺度，固定设置随后分组。
- 顶层标题由 display 随滚动收至 heading，栏高不跳；短横屏直接紧凑。分组用 caption/secondary 与留白，普通行用 body，不逐行加粗或画底线。
- 动态列表开放滚动、逐项构建；固定设置用 `content-panel` 实体卡，`row` 负责内距、最小高度与命中。组头在卡外，末行不追加装饰底线。通知各自成卡，来源、时间、正文自然排布。
- 文件页用 surface，缩略区用 surface-low；搜索及通知用 canvas。类型入口两列，无重复标题；文件夹／文件默认自适应四列，同类排序连续排列，条目不套外卡。网格名与元数据居中，列表复用 row；长内容增高，缩略失败仅在缩略区提供紧凑重试。搜索结果保持列表。视图／排序菜单从页头展开，按视图、排序、顺序分组，当前项对勾，选择即生效。
- 传输紧凑列表每批一次，body 文件名、caption 方向／设备／状态，活动项提供细进度；同设备活动在组头标设备。
- 添加与连接配置共用外壳：四种方式等宽图文 Tab，功能色保留，前景与短线表达选中。发现仅在添加页顶端进入二级页，配置隐藏并收起空间；私钥来源在 Tab 后，专属输入就地展开，配置只读。字段正文 body，辅助 caption/secondary，无重复大标题；大字可增高／滚动。
- 连接及画面首帧等待用低饱和色雾与三枚漂移光点，无中心文字；保留取消。减少动态冻结构图。

### Flexible 布局

依据父容器约束，手机稿不是缩放基准。普通页面及底部动作居中于 `page-content` 阅读列，列宽含原左右边距；远控和媒体不受限。窄屏、横屏、键盘及大字可换行、堆叠、滚动，末项可达；大屏侧栏加单一内容，短横屏用紧凑侧栏。

正文滚入透明页头与浮动导航背后，首屏避让放滚动内容内。顶部保护只覆盖安全区及实际栏高，末段以 spacing.lg 渐退，在工具栏底部透明；位于玻璃采样前，不加实体 AppBar。底部避让导航／键盘，遮挡区阻止误点且将纵向拖动交回正文。远控等叠加内容单独定位。

Pencil 独立顶层 Frame：规范／组件在左，完整页面居中按类型排列每行最多八张，局部状态在右。状态板只画变化部位，保留原状态 ID 与页面引用；`scroll-viewport` 保留完整内容。说明用 canvas-label，规范底板用 canvas，产品页面保留自身配色。

## Elevation & Depth

玻璃承载浮于真实内容上的操作或短暂反馈，光学识别来自连续背景折射、散射、边缘光及离面阴影；模糊和透明填充不能代替。平静背景无需装饰图案、彩斑或额外固定描边。

| 对象 | 材料 |
| --- | --- |
| 导航、工具、菜单、提示、弹窗、抽屉、恢复面板、任意远端背景退出控件 | regular，保护未知背景上的标签 |
| 照片／视频上的紧凑控制 | clear，亮色前景及媒体渐退保护 |
| 设备卡、正文、表单、文件与通知 | 中性实体内容面 |
| 主要按钮 | primary-action 实色 |

相关动作共享玻璃面，内部不重复包层；同页同平面共用折射层，背景先绘制，菜单保留独立浮层。材料参数统一用 `glass` token。按压即时局部提亮及轻微形变，释放／取消弹簧归位，再次操作承接当前速度；工具组不抢内部手势。菜单从触发点展开，抽屉保留可打断拖拽，贴底仅圆上角。减少动态关闭空间形变与弹性，降低透明度保留轮廓／焦点／位置并切实体。

底栏保留上游目的地、语义与横拖；静止选中镜片通过公开光学组件与交互镜片交接，不重复外栏。镜片包含父栏采样，保持上游克制折射与边缘光，不用固定填充或额外描边代替；`navigation-lens` 仅记静态投影参数。受控选择对应实际页面，辅助偏好用实体清楚选中面。

媒体 `media-shade` 覆盖控制实际高度及安全区，再按 `media-protection.height` 渐退，先于玻璃绘制、不拦触摸。背景滚动／视频、按下／取消和辅助偏好需运行验证；静态稿仅核对材料目标。用照片、细线及密集文字检查连续折射和可读性，离散重影须修正采样。

`assets/liquid-glass.glsl` 是 Pencil 静态目标；opticalDepth 为厚度，refractionWidth 为边缘过渡及形状融合距离。生产后端与初始化见[架构](../docs/implementation/architecture.md)。

## Shapes

内容面、面板、控制与缩略图用各自语义圆角，内外形状同心；胶囊用于导航／操作。图标图形与命中区域分别使用 token。

## Components

共享卡片、页头、行、开关、动作、导航和侧栏使用母组件实例。输入用 connection-field，保留已选值与标签的选择用 selection-field；候选点击展开。开关命中独立于轨道，选中及主要动作用黑白，次动作用中性实体，文字动作透明，均用 label。图标统一 Lucide，应用原图不改绘。

远控各状态共用全屏结构，快捷工具及上下文插槽表达差异；熄屏／锁定提供直接点亮，退出可触及。应用打开弹层只含应用名、两种动作与取消，动作纵排复用主次按钮，间距 12px；整页不因复用面板改成抽屉。

## Do's and Don'ts

普通路由使用 Cupertino 返回，远控按[交互规则](prod/interaction-rules.md)。系统文字、减少动态、透明度与对比偏好不另设产品开关。修改母组件同步核对实例与明暗、窄屏长文；token 更改运行生成漂移检查。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。
