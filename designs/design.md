---
version: alpha
name: 邻接 Interconnect
description: 黑白石墨灰的跨设备互联，以连贯内容、光学玻璃控制层和真实手机任务建立层次。
colors:
  primary: '#1B1B1F'
  primary-dark: '#F2F2F4'
  on-primary: '#FFFFFF'
  on-primary-dark: '#18181A'
  canvas: '#F5F5F7'
  canvas-dark: '#111113'
  surface: '#FFFFFF'
  surface-dark: '#202023'
  text: '#171719'
  text-dark: '#F5F5F7'
  secondary: '#67676E'
  secondary-dark: '#ABABB2'
  muted: '#DEDEE3'
  muted-dark: '#3B3B41'
  tint: '#E9E9EE'
  tint-dark: '#323237'
  glass: '#FFFFFF66'
  glass-dark: '#2B283195'
  glass-clear: '#FFFFFF33'
  glass-clear-dark: '#26232E66'
  glass-edge: '#FFFFFFF2'
  glass-edge-dark: '#FFFFFF73'
  glass-low-edge: '#75708042'
  glass-low-edge-dark: '#000000A3'
  glass-shine: '#FFFFFF66'
  glass-shine-dark: '#FFFFFF1F'
  shadow: '#37303E21'
  shadow-dark: '#00000066'
  success: '#25745C'
  success-dark: '#9BE5C9'
  warning: '#805518'
  warning-dark: '#E5C58D'
  danger: '#D34F60'
  danger-dark: '#FF9AA8'
  scrim: '#17171B4D'
  scrim-dark: '#00000080'
  white: '#FFFFFF'
  transparent: '#00000000'
  media-ink: '#111114'
  media-shade: '#00000099'
  accent-violet: '#7754C8'
  accent-violet-dark: '#C2A7FF'
  accent-violet-soft: '#EEE4FFB8'
  accent-violet-soft-dark: '#634A9059'
  accent-coral: '#C95646'
  accent-coral-dark: '#FFAA93'
  accent-coral-soft: '#FFE6DDC2'
  accent-coral-soft-dark: '#81544966'
  accent-amber: '#9F6719'
  accent-amber-dark: '#EAC17B'
  accent-amber-soft: '#FFF0C9CC'
  accent-amber-soft-dark: '#78634466'
  accent-mint: '#25745C'
  accent-mint-dark: '#9BE5C9'
  accent-mint-soft: '#E1F9EDCF'
  accent-mint-soft-dark: '#3C6C5E70'
  glass-selected: '#FFFFFFBD'
  glass-selected-dark: '#FFFFFF26'
  glass-reflection: '#918AA31A'
  glass-reflection-dark: '#FFFFFF0F'
  glass-action: '#1B1B1FEB'
  glass-action-dark: '#F2F2F4ED'
  glass-action-shine: '#FFFFFF14'
  glass-action-shine-dark: '#FFFFFF1F'
  glass-panel: '#FFFFFFB8'
  glass-panel-dark: '#202023E8'
typography:
  display:
    fontFamily: Noto Sans SC
    fontSize: 34px
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: -0.6px
  title:
    fontFamily: Noto Sans SC
    fontSize: 26px
    fontWeight: 600
    lineHeight: 1.25
  heading:
    fontFamily: Noto Sans SC
    fontSize: 19px
    fontWeight: 600
    lineHeight: 1.35
  body:
    fontFamily: Noto Sans SC
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: Noto Sans SC
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.4
  caption:
    fontFamily: Noto Sans SC
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.4
  micro:
    fontFamily: Noto Sans SC
    fontSize: 11px
    fontWeight: 500
    lineHeight: 1.3
  numeric:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 600
    lineHeight: 1.3
  clock:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: -1px
rounded:
  sm: 12px
  md: 18px
  lg: 26px
  xl: 34px
  phone: 38px
  full: 999px
spacing:
  zero: 0px
  hairline: 1px
  micro: 2px
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 40px
  section: 48px
  board: 80px
  group: 144px
components:
  phone:
    width: 402px
    height: 874px
    padding: '{spacing.lg}'
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
    height: 76px
  page-body:
    height: 632px
  button-primary:
    height: 52px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary}'
    textColor: '{colors.on-primary}'
    typography: '{typography.label}'
  button-primary-dark:
    backgroundColor: '{colors.primary-dark}'
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
    height: 72px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass}'
    padding: '{spacing.xs}'
  navigation-dark:
    backgroundColor: '{colors.glass-dark}'
    textColor: '{colors.text-dark}'
  glass:
    backgroundColor: '{colors.glass}'
    borderColor: '{colors.glass-edge}'
    blur: 20px
    shadowBlur: 24px
    shadowOffset: 8px
    angle: 45
    refractionIndex: 1.02
    refractionWidth: 16px
    dispersion: 0
    magnification: 1
    saturation: 1
  glass-clear:
    backgroundColor: '{colors.glass-clear}'
    textColor: '{colors.text}'
  chip:
    height: 32px
    rounded: '{rounded.full}'
    padding: '{spacing.sm}'
  row:
    height: 64px
    padding: '{spacing.md}'
  row-large:
    height: 76px
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
    height: 84px
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
    textColor: '{colors.success}'
  status-connected-dark:
    textColor: '{colors.success-dark}'
  status-warning:
    textColor: '{colors.warning}'
  status-warning-dark:
    textColor: '{colors.warning-dark}'
  status-danger:
    textColor: '{colors.danger}'
  status-danger-dark:
    textColor: '{colors.danger-dark}'
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
  accent-violet:
    backgroundColor: '{colors.accent-violet-soft}'
    textColor: '{colors.text}'
  accent-violet-dark:
    backgroundColor: '{colors.accent-violet-soft-dark}'
    textColor: '{colors.text-dark}'
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
  icon-violet:
    textColor: '{colors.accent-violet}'
  icon-violet-dark:
    textColor: '{colors.accent-violet-dark}'
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
    height: 144px
    rounded: '{rounded.lg}'
    padding: '{spacing.md}'
    backgroundColor: '{colors.glass-panel}'
    textColor: '{colors.text}'
  connection-field:
    height: 52px
    rounded: '{rounded.md}'
    padding: '{spacing.md}'
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
  field-block:
    height: 104px
  pairing-qr:
    size: 176px
    backgroundColor: '{colors.surface}'
    textColor: '{colors.text}'
---

# 邻接 · 中性液态玻璃设计规范

## Overview

“邻接”是工作名。黑、白、石墨灰构成产品主体；设备画面、照片和文件是视觉中心。主动作与选择保持黑色主题，通过光学表面、明度、字重和位置表达。图标、小图形、应用快捷入口与局部反光允许紫罗兰、珊瑚、琥珀和浅薄荷点缀；不将中性主题理解为全界面灰度。取消蓝色品牌基调。

依据 Apple HIG 与 WWDC25/26 的 Liquid Glass 理念，内容构成连续工作画布，导航与控制形成独立光学层。玻璃靠背景透色、渐变边缘光、扩散和离面阴影建立厚度，不把每一段内容包装成白卡或玻璃卡。静态稿表现材料的一帧，不宣称动态折射与平台性能已经验证。

## Colors

浅色使用中性画布、清晰正文与黑色主动作；深色同时调整画布、文字、材料边缘和阴影，主动作反转为浅色。Pencil 的 mode=light/dark 将同名语义颜色映射到其 -dark 值。没有深色后缀的媒体遮罩和白色常量保持定义值。

默认采用浅色外观。黑色是主动作与选择的主题色，不意味着默认深色模式；深色作为用户可选外观独立展示。照片等沉浸媒体上的控制可按背景选择深浅材质，不改变全局外观偏好。

媒体保留原色，不以蓝色界面染色。消息和接续使用紫罗兰、相册使用珊瑚、文件使用琥珀，连接和来电等适当使用浅薄荷。彩色主要用于小面积图形与局部透色，不覆盖全页。接听按钮改用浅薄荷透色玻璃和深色文字，禁止沿用厚重的深绿色实色按钮；拒接/挂断保留清楚的红色语义。连接、警告、失败必须同时有文字或图形。降低透明度时使用 surface，增加对比时保留明确边界；颜色变化不改变操作含义。

## Typography

Noto Sans SC 承担中文；Inter 仅承担时间、数值等。标题通过字重、紧凑行距与内容尺度建立层级，正文保持清晰可读。实现阶段使用对应平台的合适中文系统字体，不为模仿苹果牺牲中文可读性。

设备名、正文、按钮和说明分别使用语义文字角色。大文字状态允许换行与容器增高，不能把字号缩小作为溢出修复。

## Layout

手机在安全区内保留大标题、主要内容和悬浮操作，内容可在滚动时经过控制层背后；重要文字和最终操作不能永久被导航遮挡。设备首页突出真实手机预览，文件用列表，相册用媒体网格，通话以联系人和状态为中心。

同一 mobile.pen 按页面类型组织：设备与工作台、连接与授权、手机与应用、文件与传输、相册与内容、通知与接续、来电与通话、偏好与恢复、平板与桌面。每类使用带标题的一整行，行内安排正常、操作中与异常状态；不再按全局编号机械填充网格。各页面保留独立顶层 Frame，分组标题只作画布导航。

平板与桌面延续对象和任务关系，扩展为侧栏、工作区与详情。参考 2026 修订，大屏侧栏可延伸至窗口边缘，顶部工具栏更有结构；不机械放大手机布局。

## Elevation & Depth

regular 玻璃用于标签栏、导航按钮、控制工具、菜单和弹层；clear 仅用于具有丰富媒体背景且能保证文字对比的控制。正文与列表使用普通内容材料。选中胶囊与父导航处于同一控制平面，不叠完整阴影玻璃。

实时折射使用 glass 的光学参数：折射率 1.02、边缘宽度 16px，不附加色散、放大或饱和度变化。底层采用 glass 透色，文字区域以 glass-panel 局部保护，保护层按组件长宽形成椭圆渐退至 glass-reflection，避免多段渐变形成可见条纹；边缘保留背景透入，不以提高整块不透明度遮住所有折射。运行后端支持 shader 背景滤镜时启用，未支持时保留磨砂材质；降低透明度与高对比时直接使用不透明表面，跳过模糊、折射和反光。具体渲染实现与四端构建证据在技术文档维护。

实时通知使用连续内容行，来源、正文与原应用动作就近呈现；仅标题和正文均为空的系统汇总项不单独占位，有实际内容的汇总继续展示。普通通知未提供预览时明确说明，保留在原手机查看入口，不能把内容受限误判成没有通知。

Pencil 材料由更透明的底、可辨背景色、随方向变化的亮暗边缘、底部反射与柔和阴影共同表达。主要动作使用带亮边和反光的石墨玻璃；设备信息控制层、快捷入口、导航选择、搜索、状态操作与弹层共享光学语言，增加有效的玻璃使用面积。设备预览的真实图像为控制层提供透色依据。大弹层更厚、更扩散，小按钮轻盈。滚动边缘仅出现于实际有内容进入控件后方的区域，文字密集顶栏使用更明确的分离。

动态实现需呈现即时按下反馈、可打断的形变、控件来源关系与内容变化下的对比适配。减少动态效果时保留反馈并减轻空间位移；降低透明度时转实色。这些属于后续运行验证，静态图不能证明其通过。

## Shapes

形状与屏幕、窗口边缘保持同心关系；大内容区、控件、图标与媒体缩略图使用不同语义圆角。胶囊服务导航和操作，图标大小不等于点击区域。内容行靠对齐、空白与必要分隔建立关系。

## Components

- Device hero：真实手机预览、设备名、连接状态与打开动作构成视觉主线。
- Floating navigation：设备、传输、设置为稳定目的地；当前区域使用一体选中胶囊，图标与文字同时可辨。
- Glass control：渐变亮边、背景透入与阴影共同说明可操作性；不对每个普通内容行加玻璃。
- Content list：文件与通知保持连续内容节奏，状态与动作就近显示。
- Media controls：相册预览与远控画面保留内容，边缘悬浮工具不污染实际远端触控区域。
- Context sheet：设备切换、质量与同名冲突保留来源上下文；主动作、取消和破坏性动作含义明确。
- Capability state：受限、离线、失效与恢复具有可执行下一步，不以灰按钮代替解释。

图标统一使用 Lucide；远端应用图标在静态稿中用功能图形示意，不绘制第三方商标。录屏、备份、自动编辑回写、专用相机页与独立短信中心不再出现。短信等通知进入手机原应用，通话、文件与相册保留专用页面。

## Do's and Don'ts

- 每页说明当前设备、内容归属和下一步动作；删除、断开和关闭窗口使用不同语义。
- 保持黑白石墨灰主基调，允许彩色图标与小元素点缀；使用明确的色彩角色，避免全灰或大面积品牌染色。
- 内容与控制分层，避免纯白空卡堆叠、全界面玻璃和玻璃叠玻璃。
- 主控不要求调试；连接引导中的调试设置发生在被控手机。
- 唤醒指打开远控画面，不强制点亮实体屏幕，不绕过手机锁屏。
- 预览导出到系统临时目录；Git 只保留设计源文件、规范与必要素材。
- 不以静态设计宣称动态折射、四端编译或真机能力已验收。

依据：[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[WWDC25 Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)、[WWDC26 修订](https://developer.apple.com/videos/play/wwdc2026/101/)。详见[研究记录](../docs/research/apple-liquid-glass-redesign.md)。格式：[Google DESIGN.md](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)。行为：[产品设计](prod/README.md)。

彩色图标与标签分工明确：accent 组件的正文使用中性文字，icon 组件映射功能色；透明选中层的文字对比需按实际背景合成后验证。主动作保留稳定的黑色主体，只用低强度边缘反光，不做宽幅金属斜面。来电拒接使用浅珊瑚玻璃与深色文字，接听使用浅薄荷玻璃，避免大面积红色压过接听；通话中的结束动作保留明确危险语义。设备玻璃面板随外观提高底色保护，深色下避免白亮壁纸透入后使文字失去对比。降低透明度关闭控制材质的半透明、反光和背景模糊，保留功能图标色。

移动端控制会话默认沉浸全屏：远端画面占据整个内容区域，移除主控页面标题、外置工具栏、额外手机边框和重复系统状态栏。不同屏幕比例保持源画面完整，不拉伸或裁掉远端系统控件；空余区域使用媒体底色，不能恢复为带页头的内嵌播放器。唯一常驻主控控件是液态玻璃退出按钮。按钮拖动连续跟手，松手吸附最近左右边缘并收起，保留侧边把手；点击把手展开、点击展开按钮退出。拖拽释放不能触发退出，退出返回互联工作台，设备连接与其他活动按各自规则继续。收起态使用独立可访问热区，语义为展开退出按钮，按钮信息与触摸均不发送给远端；位置随旋转和安全区域重新约束。降低透明度使用实色按钮，减少动态保留即时定位与反馈。

全屏会话规则同样适用于画质/声音面板、资源不足和断线重连等叠加状态。面板底层仍为整个屏幕的远端内容，不重新插入主控页头、卡片画面或底部工具栏。断线时底层明确为最后一帧，标记画面暂停并停止远端输入；退出按钮始终位于面板之外可触及的位置。工作台和会话列表使用设备/会话状态卡，点击后进入全屏操作，不用裁切的横向屏幕模拟可操作会话。

Pencil 复用规则：移动端远控页面使用同一全屏会话组件，通过画面源、展开/侧边退出、遮罩与上下文面板插槽表达状态；重连、画质、资源不足、文件冲突和回复共用玻璃面板外壳，业务内容作为嵌套组件。主/次按钮、内容行、导航、系统状态栏与手势指示使用组件实例。页面仅覆盖文案、图标、启用状态、位置与有语义的变体，不复制通用材质和尺寸；降低透明度的实色样式属于明确变体。源组件集中在设计系统画布，变更后检查正常、收起、异常、深色与低透明度实例。

首屏是设备列表，单台和多台设备使用同一种设备卡，不设置主手机、备用手机或默认主次层级。在线、离线、检查中、主动断开和需要授权分别呈现；旧状态附时间，电量只在在线可确认时作为当前值。设备工作台在选择设备后进入。连接表单使用可编辑地址、端口及配对码字段，字段错误在原位说明；配对端口与连接端口分开，输入完整才启用提交。二维码由主控出示、被控手机系统扫描。设备卡、表单字段、页头和流程状态优先复用共享组件，页面保留清楚的返回、取消和替代路径。
