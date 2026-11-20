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
  success: '{colors.list-icon-mint}'
  success-dark: '{colors.list-icon-mint}'
  warning: '{colors.list-icon-amber}'
  warning-dark: '{colors.list-icon-amber}'
  danger: '{colors.list-icon-coral}'
  danger-dark: '{colors.list-icon-coral}'
  scrim: '#17171B4D'
  scrim-dark: '#00000080'
  white: '#FFFFFF'
  transparent: '#00000000'
  media-ink: '#111114'
  media-shade: '#00000099'
  accent-blue: '{colors.list-icon-blue}'
  accent-blue-dark: '{colors.list-icon-blue}'
  accent-blue-soft: '#E6F2FF'
  accent-blue-soft-dark: '#1A2635'
  accent-coral: '{colors.list-icon-coral}'
  accent-coral-dark: '{colors.list-icon-coral}'
  accent-coral-soft: '#FFEBEA'
  accent-coral-soft-dark: '#332021'
  accent-amber: '{colors.list-icon-amber}'
  accent-amber-dark: '{colors.list-icon-amber}'
  accent-amber-soft: '#FFF4E6'
  accent-amber-soft-dark: '#33291C'
  accent-mint: '{colors.list-icon-mint}'
  accent-mint-dark: '{colors.list-icon-mint}'
  accent-mint-soft: '#EBF9EE'
  accent-mint-soft-dark: '#1E2E24'
  on-accent: '#FFFFFF'
  list-icon-blue: '#0A84FF'
  list-icon-amber: '#FFB340'
  list-icon-mint: '#32D67B'
  list-icon-coral: '#FF6B5E'
  list-icon-slate: '#5AC8FA'
  list-icon-purple: '#BF5AF2'
  loading-warm: '#FFBEB87A'
  loading-blue: '#7EBBFF70'
  loading-mint: '#81E8CE61'
  loading-violet: '#B8A4F56B'
  glass-selected: '#0000000A'
  glass-selected-dark: '#FFFFFF1F'
  glass-action: '#1B1B1F'
  glass-action-dark: '#F2F2F4'
  glass-action-shine: '#FFFFFF14'
  glass-action-shine-dark: '#FFFFFF1F'
  black: '#000000'
  on-danger: '#18181A'
  on-danger-dark: '#18181A'
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
    fontSize: 17px
    fontWeight: 400
    lineHeight: '1.45'
    letterSpacing: 0px
  body-emphasis:
    fontFamily: MiSans
    fontSize: 17px
    fontWeight: 600
    lineHeight: '1.45'
    letterSpacing: 0px
  body-compact:
    fontFamily: MiSans
    fontSize: 15px
    fontWeight: 400
    lineHeight: '1.4'
    letterSpacing: 0px
  label:
    fontFamily: MiSans
    fontSize: 15px
    fontWeight: 500
    lineHeight: '1.4'
    letterSpacing: 0px
  caption:
    fontFamily: MiSans
    fontSize: 13px
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
    fontSize: 17px
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
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
  sidebar-compact:
    width: 180px
  status-bar:
    height: 54px
  page-header:
    height: 56px
  remote-navigation:
    height: 56px
    padding: 67.5px
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
  app-icon-dark:
    backgroundColor: '{colors.tint-dark}'
    textColor: '{colors.text-dark}'
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
  glass-clear-dark:
    backgroundColor: '{colors.glass-clear-dark}'
    textColor: '{colors.text-dark}'
  glass-edge-dark:
    backgroundColor: '{colors.glass-edge-dark}'
  glass-low-edge:
    backgroundColor: '{colors.glass-low-edge}'
  glass-low-edge-dark:
    backgroundColor: '{colors.glass-low-edge-dark}'
  glass-highlight:
    backgroundColor: '{colors.glass-shine}'
  glass-highlight-dark:
    backgroundColor: '{colors.glass-shine-dark}'
  glass-shadow:
    backgroundColor: '{colors.shadow}'
  glass-shadow-dark:
    backgroundColor: '{colors.shadow-dark}'
  modal-scrim:
    backgroundColor: '{colors.scrim}'
  modal-scrim-dark:
    backgroundColor: '{colors.scrim-dark}'
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
    backgroundColor: '{colors.white}'
  separator:
    backgroundColor: '{colors.muted}'
  separator-dark:
    backgroundColor: '{colors.muted-dark}'
  text-action:
    backgroundColor: '{colors.transparent}'
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
    backgroundColor: '{colors.media-ink}'
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
  content-panel-low:
    backgroundColor: '{colors.surface-low}'
    textColor: '{colors.text}'
  content-panel-low-dark:
    backgroundColor: '{colors.surface-low-dark}'
    textColor: '{colors.text-dark}'
  danger-panel:
    backgroundColor: '{colors.danger-container}'
    textColor: '{colors.on-danger-container}'
  danger-panel-dark:
    backgroundColor: '{colors.danger-container-dark}'
    textColor: '{colors.on-danger-container-dark}'
  button-danger:
    backgroundColor: '{colors.danger}'
    textColor: '{colors.on-danger}'
  button-danger-dark:
    backgroundColor: '{colors.danger-dark}'
    textColor: '{colors.on-danger-dark}'
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
  status-symbol-connected:
    textColor: '{colors.success}'
  status-symbol-connected-dark:
    textColor: '{colors.success-dark}'
  status-symbol-warning:
    textColor: '{colors.warning}'
  status-symbol-warning-dark:
    textColor: '{colors.warning-dark}'
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
  glass-selection-dark:
    backgroundColor: '{colors.glass-selected-dark}'
  glass-selection-label:
    textColor: '{colors.text}'
  glass-selection-label-dark:
    textColor: '{colors.text-dark}'
  glass-action:
    backgroundColor: '{colors.glass-action}'
    textColor: '{colors.on-primary}'
  glass-action-dark:
    backgroundColor: '{colors.glass-action-dark}'
    textColor: '{colors.on-primary-dark}'
  glass-action-highlight:
    backgroundColor: '{colors.glass-action-shine}'
  glass-action-highlight-dark:
    backgroundColor: '{colors.glass-action-shine-dark}'
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
  remote-exit-handle:
    width: 2px
    height: 24px
    rounded: '{rounded.full}'
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
  connection-field-outline-dark:
    backgroundColor: '{colors.outline-dark}'
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
    backgroundColor: '{colors.media-shade}'
  feature-icon:
    size: 40px
    rounded: '{rounded.md}'
    opacity: 0.1
  list-icon:
    size: 28px
    rounded: 6px
    textColor: '{colors.on-accent}'
  list-icon-glyph:
    size: 20px
  list-icon-blue:
    backgroundColor: '{colors.list-icon-blue}'
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
  loading-flow-warm:
    backgroundColor: '{colors.loading-warm}'
  loading-flow-blue:
    backgroundColor: '{colors.loading-blue}'
  loading-flow-mint:
    backgroundColor: '{colors.loading-mint}'
  loading-flow-violet:
    backgroundColor: '{colors.loading-violet}'
  loading-orb:
    opacity: 0.32
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
    textColor: '{colors.black}'
---

# 邻接 · iOS 27 设计规范

## Overview

以设备身份、真实画面与用户内容为视觉中心，瓷白／炭黑内容层上悬浮具有可感知连续折射的玻璃控制。产品行为见[产品规格](prod/README.md)。数值以 frontmatter token 为准，Flutter 常量由[工具](../scripts/design_tokens/README.md)生成；`px` 对应逻辑像素。

frontmatter 的 maxWidth、gap、verticalPadding、opacity、scale、stretch 及玻璃光学属性属于项目扩展。生成与正式 lint 共用项目 schema，检查扩展类型、单位及取值范围，并保留官方的未知属性、断引用、对比度和未引用颜色检查。校验入口见[工具说明](../scripts/design_tokens/README.md)。颜色引用应对应实际组件或绘制层，透明层与图标的可读性按真实叠加关系核验。

## 设计依据与原则

以 iOS 27 和当前 Apple HIG 为基线，核对日期 2026-11-14。项目采用其层级、交互与适配原则；普通玻璃保留清楚的背景透视、连续折射与离面层次。系统标准组件随系统玻璃外观偏好变化；Flutter 自绘玻璃使用 `liquid_glass_widgets` 的 iOS 27 regular/clear 预设，不读取未公开的 clear/tinted 偏好值，必须在系统外观和辅助偏好组合下做真机验收。frontmatter 中的配色、圆角和光学数值是邻接的设计选择，不是 Apple 官方参数。

| 原则 | 邻接的决定 |
| --- | --- |
| Purpose／目的 | 首屏选设备，再完成远控、取用内容或接续应用；不加营销页与概览仪表盘 |
| Agency／自主 | 退出、取消、停止始终可达；保留操作对象与输入，未知结果先核对 |
| Responsibility／责任 | 及时解释权限用途；不把通知清除说成已读，不把请求接受说成完成 |
| Familiarity／熟悉 | 稳定的设备／传输／设置目的地、返回路径、选择入口与危险动作样式 |
| Flexibility／灵活 | 系统字体偏好、玻璃外观、减少动态、降低透明度、提高对比度分别适配 |
| Simplicity／简洁 | 只去掉重复解释，保留设备来源、真实阶段、影响与恢复入口 |
| Craft／工艺 | 明暗可读、触控可靠、连续可打断反馈；不以昂贵折射牺牲响应 |
| Delight／愉悦 | 屏幕连接与画面启动通过柔和渐变和三球动效建立连续感；装饰运动不代表实际进度 |

## Colors

项目配色以瓷白 `#F2F2F7`／白色内容面、炭黑 `#1B1B1F`／深色 `#1C1C1E` 为基础。主要动作浅色黑底白字、深色浅底深字；不把黑白等同于所有操作权重相同。

点缀色采用高明度、鲜明饱和的色块，浅深色模式都保留色彩活力；功能图标底不使用棕黄、墨绿或灰紫。彩色背景统一搭配白色图形；功能名称与状态文字使用独立前景，保留明亮点缀色。

| 点缀角色 | 色值 | 用途 |
| --- | --- | --- |
| 连接亮蓝 | `#0A84FF` | 连接、发现与通知功能图标 |
| 画面亮紫 | `#BF5AF2` | 画面与媒体功能图标 |
| 活动薄荷绿 | `#32D67B` | 活动、能力及通话功能图标 |
| 资料橙黄 | `#FFB340` | 文件、剪贴板与诊断功能图标 |
| 珊瑚红 | `#FF6B5E` | 设备管理与高影响功能入口图标 |
| 资料青蓝 | `#5AC8FA` | 普通设置与设备数据功能图标 |

`list-icon` 实色底统一配 `on-accent` 白色 Lucide 图形，浅深色模式一致。彩色图标与色块外的清楚文字标签成组呈现，功能不单靠图形传达；独立无标签控件须另行核验至少 3:1 的图形对比。色块内的说明文字采用深色前景，不复用图标前景 token。success／warning／danger 及 accent-mint／amber／coral／blue 直接引用上述亮色，明暗主题使用相同基色，不再维护另一套偏暗状态色或点缀色。普通正文及状态说明使用 text／secondary；亮色用于状态符号、色块及明确的风险动作，不把亮橙黄、薄荷绿用于浅色背景上的小字。危险实色按钮搭配 on-danger 深色文字，并以文字说明风险。熄屏、关闭画面及断开按真实影响选择样式。品牌色主要进入内容、状态及有意义的动作，不给整条导航染品牌底。空态用 `feature-icon` 淡底。真实应用图标、设备轮廓和缩略图保留自身角色。

`list-icon` 定义尺寸与白色图形，`list-icon-blue` 等定义独立底色层；其中 textColor 是导出器沿用的图形前景字段，不用于文字。`glass-selection` 是叠加在现有内容面上的选中层，`glass-selection-label` 是独立标签；黑色标签需在浅色底合成后检查，不能把透明黑选中层当作不透明黑底。白色图形及实体、透明图层均保留真实色值，不为通过普通文字的4.5:1检查而改暗亮色底。

主控导航、图标与分隔绑定主题语义色，远端画面不重着色。状态同时有文字或图形依据。降低透明度／提高对比度使用实体面。

## Typography

设计稿使用 MiSans，字体资源及许可随稿件保存。App 使用各宿主当前的系统界面字族及中文回退，并监听系统字体设置变化；稿件字体不作为运行字体。Apple 系统字体按最终字号选择光学角色，不打包 SF 字体。生成字体家族元数据仅描述稿件。

手机普通正文与输入为 17 点，紧凑辅助正文与动作标签 15 点，元数据 13 点，11 点仅用于非关键微型标注；导航短标签可用 13 点，不能把关键状态缩成微字。大标题 28 点，页面／面板标题 22 点，紧凑页头 17 点。正文不全局缩小迁就信息密度，中文正文不沿用拉丁标题的负字距。

普通文字对比至少 4.5:1，大字与有意义图形至少 3:1；玻璃必须在实际采样背景上核验，透明度数值不能证明对比合格。支持至少 200% 文字放大：行、按钮、菜单、页头随内容增高，横排可堆叠，网格减少列数；关键动作与来源不截断。普通触控目标采用至少 44×44 点，视觉图形可以更小。

页头只保留标题，普通列表不加用途说明；真实状态、通知正文、错误、校验、进度及来源目标保留。文件大小／当前值就近放同行，长值允许换行、增高或提供全文，不能全局缩字修复溢出。

## Layout

- 远控画面下方的三键导航栏中，返回为指向左侧的实心三角形，主屏幕为空心圆，最近任务为圆角空心方形。三个按钮使用 44×44 点命中区；栏内左右各留 67.5 点，命中区之间等距。402 点宽时中心距左缘分别为 89.5、201、312.5 点，浅深主题共用位置，导航栏独立占高 56 点。
- 设备卡以轮廓、名称和真实状态为中心，状态图标放在轮廓内；工作台顶栏显示当前设备名称，摘要使用 caption 承载连接、电量与端点，型号及参数留在独立详情页。工作台使用无标题列表组承载设备信息和任务入口，主动作与快捷入口沿用 `app-icon` 尺度。
- 顶层标题由 display 随滚动收至 heading，栏高不跳；短横屏直接紧凑。分组用 caption/secondary 与留白，普通行用 body，不逐行加粗或画底线。
- 动态列表开放滚动、逐项构建；固定设置用 `content-panel` 实体卡，`row` 负责内距、最小高度与命中。组头在卡外，末行不追加装饰底线。通知各自成卡，来源、时间、正文自然排布。
- 文件页用 surface，缩略区用 surface-low；搜索及通知用 canvas。类型入口两列，无重复标题；文件夹／文件默认自适应四列，同类排序连续排列，条目不套外卡。网格名与元数据居中，列表复用 row；长内容增高，缩略失败仅在缩略区提供紧凑重试。搜索结果保持列表，视图与排序菜单从页头展开并按组组织。
- 文件选择态保持同一内容几何：列表尾部共用 24 点固定槽，16 点箭头与 20 点选择圆框均在槽内居中，选中对勾 14 点；仅替换槽内绘制，不改变行高、内距、左右图形、名称与元数据的可用宽度、基线、换行或截断。宫格使用同样的 20 点圆框，叠放于缩略区正中，不挤压原图、文件名或元数据。标记用中性实体面／outline，选中用 primary-action 实色与 on-primary 对勾；缩略图上始终有清楚轮廓。可见标记与命中范围分离：命中至少 44 点，条目整体可切换选择；不得为扩大命中新增占位或挤压内容。相同屏宽、字体与滚动位置下，进入／退出选择态仅改变状态绘制与浮动操作，不对条目做缩放、横移或高度动画；底栏仅增加滚动末尾的避让空间。
- 选择页头沿用 page-header：左侧 ×、中间计数、右侧图标动作；全选两态使用 22 点前景色图标和 44 点圆形命中区，固定在尾槽内，不挪动标题。底部使用一个 regular 液态玻璃胶囊承载成组操作，图标与短标签等宽排列；底栏遵循 navigation 的高度和安全留白，大字时自然增高，正文末尾同步避让。
- 传输紧凑列表每批一次，body 文件名、caption 方向／设备／状态，活动项提供细进度；同设备活动在组头标设备。
- 添加与连接配置共用外壳：图文 Tab 等宽排列，图标、标签起始基线和指示线对齐；选中由前景、字重与短线共同表达。窄屏与大字时标签区增高或允许横向滚动，选中项保持可见。字段使用 body，辅助信息使用 caption/secondary，不重复大标题。
- 工作台快捷区使用文件、相册、通知、电话四个等宽入口；电话使用明亮薄荷图标底和白色听筒，窄屏或大字时改为两列两行并自然增高。电话页保持标准导航、来源设备、真实阶段和底部动作，完整行为见[电话接力](prod/calls.md)。
- 连接诊断使用平铺检查项，设备详情和设置使用独立页；当前活动区分进行中与待核对。行为和恢复规则由[产品规格](prod/README.md)及其责任文档维护。
- 添加、配对及普通连接使用中性页面和标准进度反馈；屏幕连接与首帧等待使用下方唯一“全屏加载”渐变与三球组件，异常在原页使用无背景文字反馈。

### 全屏加载的主题与动效

普通页面及局部操作的未知时长等待使用紧凑、中性语义色的 Cupertino activity indicator，放在所属内容区域；横向条只用于已知完成比例的传输进度及容量占用。具体等待、取消和恢复行为见[交互规则](prod/interaction-rules.md)与[内容与传输](prod/content-and-transfer.md)。

屏幕连接及首帧等待状态使用唯一“组件 / 屏幕连接加载 · 渐变与三球”背景组件；“页面 / 03 添加设备 / 连接中 · 浅色”设备连接页使用中性背景和标准进度指示。屏幕等待跟随系统主题，颜色不绑定业务阶段。浅深两套只切换 canvas 底色（浅色 #F2F2F7、深色 #000000）。暖粉、雾蓝、薄荷与浅紫的流动渐变共用上述 RGBA 色值；三球使用 list-icon-mint、list-icon-coral、list-icon-purple 三种明亮基色，统一使用 `loading-orb.opacity` 的 0.32 透明度，Ardot 变量按百分比 32 绑定。渐变与三球的颜色、透明度、位置、尺寸、轨迹、速度及缩放在两种主题完全一致，通过半透明叠加自然形成深浅差异，不设深色专用动效覆盖。关闭和必要提示沿用标准语义色保持可读。

以可用视口为坐标，球群中心在横向 50%、纵向 45.3%；402 宽稿的轨道半径为 52×38 点，绿／珊瑚／紫球基准直径分别 32／28／22 点，初始相位 −35°／85°／205°。三球以 4.2 秒一周连续绕行，各自按 2.8／3.4／3.9 秒周期在 0.7–1.6 倍之间平滑放大缩小，错开相位；按屏宽收敛轨道，不随文字放大。背景三层渐变分别以 16／20／18 秒连续漂移，位移不超过各层尺寸 8%，缩放 1–1.12，并预留出血避免露边和亮度脉冲。静态源稿定义外观和轨迹参数，状态切换与生命周期见[交互规则](prod/interaction-rules.md)。

### Flexible 布局

依据父容器约束，手机稿不是缩放基准。普通页面及底部动作居中于 `page-content` 阅读列，列宽含原左右边距；远控和媒体不受限。窄屏、横屏、键盘及大字可换行、堆叠、滚动，末项可达；大屏侧栏加单一内容，短横屏用紧凑侧栏。窗口状态与能力边界见[平台与能力](prod/compatibility.md)。

正文可滚入页头与浮动导航背后，首屏避让放滚动内容内；可读性优先，系统玻璃外观或辅助偏好改变后，材料可加厚至实体，不强制始终透明。顶部保护只覆盖安全区及实际栏高，末段以 spacing.lg 渐退，在工具栏底部透明；位于玻璃采样前，不加实体 AppBar。底部避让导航／键盘，遮挡区阻止误点且将纵向拖动交回正文。远控等叠加内容单独定位。

Ardot 独立顶层画板：规范／组件在左，完整页面居中按产品流程分组、每行最多八张，局部状态在右。分组标题与图层树使用相同阅读顺序。每种独有结构只保留一处完整示意：同一外壳切换表单，只展示一次完整页面，其余方式由对应内容组件表达；加载、空态、错误、菜单只展示变化部位。状态仅文案或示例数据不同则合并，用上下文注明实际原因；行为、动作或恢复路径不同才保留独立状态。共享母组件保留唯一原件，不另加无覆盖的展示副本；从未启用且没有实例使用的旧节点直接删除。

局部状态按来源归入所属状态板，不为补充示例另开同主题画布。合并时保留独有交互和必要的明暗、大字、窄屏、辅助偏好示例，以当前页面与状态名称定位，删除失效说明与空容器。局部裁片的计数与可见示例保持一致；200% 大字示例同时放大字号与行高。入口提供三分区导览；画布整理不缩放完整页面，`scroll-viewport` 保留完整内容。说明用 canvas-label，规范底板用 canvas，产品页面保留自身配色。

## Adaptive Windows & Form Factors

适配依据当前窗口的可用宽高、方向、系统保留区与输入方式，不依据设备名称或固定屏幕尺寸猜测；布局只改变可见结构与操作密度。窗口状态、会话保留和能力边界见[平台与能力](prod/compatibility.md)。

| 窗口状态 | 页面结构 | 交互与材料 |
| --- | --- | --- |
| compact（通常 <600dp / vp） | 单列内容；底部导航；弹窗按可滚动实体面限制宽度 | 44 点触控目标；底栏可用 regular 玻璃；正文和弹窗实体面 |
| medium（约 600–839） | 导航侧栏或 rail + 主内容；列表与详情按宽度切换 | 鼠标、键盘、触控和手写笔均可操作；菜单从触发点展开 |
| expanded（≥840） | 侧栏沿可用窗口高度铺开 + 双栏工作区；桌面使用可移动、可缩放的独立控制窗口 | 不绘制手机式顶部状态条；标题、连接状态与当前窗口操作进入工作区工具栏 |
| 折叠／双屏 | 外屏单列；展开双栏；半折避开铰链／折痕保留区 | 折叠只做最小必要移动；跨折叠连续内容不放置关键文字、输入或按钮 |
| 鸿蒙浮窗／分屏 | 按实时窗口宽高重算单列、上下或左右双栏 | 不假定全屏；弹窗宽度受窗口约束，分隔线拖动后内容仍可达 |

桌面、平板、折叠屏和移动端的独立窗口沿用控制会话的窗口视觉；系统不支持额外窗口时退回同页分栏。窗口最小尺寸保证标题、画面、退出与恢复动作可达，调整大小只改变布局。

折叠屏状态覆盖外屏、完全展开、书本半折、桌面半折与旋转后展开；每种状态核对铰链／折痕避让、方向、安全区、长文字、减少动态和降低透明度。外屏单列、内屏双栏，横向姿态让工具栏、导航和标签栏贴合系统侧边垂直栏，内屏竖向姿态保留横向栏；重要内容不跨中间铰链。平台窗口合同与能力限制见[平台与能力](prod/compatibility.md)。

桌面工作区不提供默认顶部状态条；操作系统标题栏与窗口菜单由宿主负责，应用内容从工作区工具栏开始。移动端和折叠外屏可保留系统安全区与页面导航，平板及桌面不复制手机顶部状态条。

iPhone Duo 横向垂直导航胶囊贴合物理屏幕边缘，保留 24 点外边距；系统状态簇占用的完整 lateral inset 只用于页面内容避让，不重复施加到导航胶囊。

适配验证同时覆盖真实窗口状态和视觉状态：浅／深色、200% 字体、键盘、安全区、鼠标／键盘／触控、降低透明度与减少动态。

## Elevation & Depth

玻璃仅用于按钮、底部栏和紧凑的弹出按钮集合，光学识别来自可感知的连续折射、背景透视、散射与离面分离；控制标签保持清楚。普通玻璃在浅深模式中都保留可辨的通透感，实体控制用于降低透明度等辅助偏好。静态光学参数只定义目标，系统材料在可用时优先采用，不能为追逐光学强度降低帧率或标签可读性。平静背景无需装饰图案、彩斑或额外固定描边。

| 对象 | 材料 |
| --- | --- |
| 图标按钮、按钮工具组、底部导航／操作栏、紧凑弹出操作菜单、远端退出控件 | regular，保护未知背景上的标签 |
| 照片／视频上的紧凑控制 | clear，亮色前景及媒体渐退保护 |
| 确认／输入／帮助弹窗、应用打开方式面板、内容抽屉、恢复面板、侧栏、文字提示、设备卡、正文、表单、文件与通知 | 中性不透明实体内容面，浅深主题均无背景模糊或折射 |
| 主要按钮 | primary-action 实色 |

紧凑弹出操作菜单只承载按钮集合；含正文、表单、确认说明或长内容的弹窗及抽屉使用实体面，不因浮于页面之上而使用玻璃。文字 Tooltip 与短暂消息同样使用实体面。相关玻璃动作共享材料，内部不重复包层；同页同平面共用折射层，背景先绘制，菜单保留独立浮层。材料参数统一用 `glass` token；不为同层每个小控件添加独立高光与重影。渲染后端不能仅因缺少 Impeller 图像过滤能力就改用实体材料，应使用生产玻璃库提供的适配路径；辅助偏好独立决定是否不透明。按压即时局部提亮及轻微形变，释放／取消弹簧归位，再次操作承接当前速度；工具组不抢内部手势。顶部工作区和媒体预览工具栏按钮不使用投影阴影，避免被标题栏或媒体渐变采样边界裁切；底部栏使用官方单一 `GlassTabBar` 渲染实例，交互、选中面与释放状态由同一实例持续管理，不叠加或卸载重挂载。操作菜单从触发点展开；实体抽屉保留可打断拖拽，贴底仅圆上角。减少动态关闭空间形变与弹性，降低透明度保留轮廓／焦点／位置并切实体。

底栏保留上游目的地、语义与横拖；官方 `GlassTabBar` 同时持有轨道、选中面与交互状态，不重复外栏或自绘静态镜片。选中状态同时由文字／图形权重及清楚的选中面表达，不依赖折射或高光；受控选择对应实际页面，辅助偏好用实体清楚选中面。

媒体 `media-shade` 覆盖控制实际高度及安全区，再按 `media-protection.height` 渐退，先于玻璃绘制、不拦触摸。背景滚动／视频、按下／取消和辅助偏好需运行验证；静态稿仅核对材料目标。用照片、细线及密集文字检查连续折射和可读性，离散重影须修正采样。

玻璃光学参数中 opticalDepth 为厚度，refractionWidth 为边缘过渡及形状融合距离。生产后端与初始化见[应用入口](../app/lib/main.dart)。

## Shapes

内容面、面板、控制与缩略图用各自语义圆角，内外形状同心；胶囊用于导航／操作。图标图形与命中区域分别使用 token。

## Components

共享卡片、页头、行、开关、动作、导航和侧栏使用母组件实例。输入用 connection-field，保留已选值与标签的选择用 selection-field；候选点击展开。开关命中独立于轨道，选中及主要动作用黑白，次动作用中性实体，文字动作透明，普通动作使用 label；危险动作使用风险色并说明影响，取消保持普通样式。图标统一 Lucide，应用原图不改绘。

远控各状态共用全屏结构，快捷工具及上下文插槽表达差异；熄屏／锁定提供直接点亮，退出可触及。应用打开弹层只含应用名、两种动作与取消；手机主控首次推荐手机屏幕，独立窗口为次选，之后沿用用户明确选择，动作纵排复用主次按钮，间距 12px；整页不因复用面板改成抽屉。

## Do's and Don'ts

普通路由使用 Cupertino 返回；文件选择态先按[选择规则](prod/content-and-transfer.md#文件选择与批量操作)退出选择，远控按[交互规则](prod/interaction-rules.md)。系统文字、减少动态、玻璃外观、透明度与对比偏好不另设产品开关；标准 Apple 组件跟随系统玻璃外观变化，Flutter 自绘层不伪造未公开的透明／着色状态，统一使用已验收的 iOS 27 regular/clear 预设。修改母组件同步核对实例与明暗、窄屏长文；token 更改运行生成漂移检查。

依据：[iOS 27 官方设计更新](https://www.apple.com/os/ios/)、[Principles of great design · WWDC26](https://developer.apple.com/videos/play/wwdc2026/250/)、[Communicate your brand identity on iOS · WWDC26](https://developer.apple.com/videos/play/wwdc2026/251/)、[Apple 无障碍指南](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Apple 字体指南](https://developer.apple.com/design/human-interface-guidelines/typography)、[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)。
