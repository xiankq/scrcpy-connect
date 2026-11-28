---
version: beta
name: 邻接 Interconnect
description: 近场工作台。以 Prism UI 的分层实体面、连续圆角与液态玻璃为基础，品牌亮蓝标记主操作，功能色帮助识别入口。
colors:
  primary: '#4C88FF'
  primary-dark: '#5C91FF'
  on-primary: '#FFFFFF'
  on-primary-dark: '#001945'
  primary-container: '#D9E2FF'
  primary-container-dark: '#19438F'
  on-primary-container: '#19438F'
  on-primary-container-dark: '#D9E2FF'
  page: '#F0EDF0'
  page-dark: '#131315'
  card: '#FCF8F9'
  card-dark: '#252628'
  block: '#F0EDF0'
  block-dark: '#323235'
  inset: '#E4E2E5'
  inset-dark: '#404042'
  text: '#191B23'
  text-dark: '#F6F6FF'
  text-secondary: '#424654'
  text-secondary-dark: '#C2C6D6'
  separator: '#191B2324'
  separator-dark: '#F6F6FF24'
  outline: '#737785'
  outline-dark: '#8C909F'
  disabled: '#191B2361'
  disabled-dark: '#F6F6FF61'
  disabled-container: '#191B231F'
  disabled-container-dark: '#F6F6FF1F'
  pressed: '#BCBCBC66'
  pressed-dark: '#CCCCCC40'
  scrim: '#00000033'
  scrim-dark: '#0000007A'
  error: '#BA1A1A'
  error-dark: '#FFB4AB'
  error-container: '#FFDAD6'
  error-container-dark: '#93000A'
  on-error-container: '#93000A'
  on-error-container-dark: '#FFDAD6'
  destructive: '#FF383C'
  destructive-dark: '#FF4245'
  success: '#006E1C'
  success-dark: '#78DC77'
  success-container: '#D5E8CF'
  success-container-dark: '#3B4B38'
  on-success-container: '#005313'
  on-success-container-dark: '#94F990'
  warning: '#8B5000'
  warning-dark: '#FFB870'
  warning-container: '#FFDCBE'
  warning-container-dark: '#59422C'
  on-warning-container: '#693C00'
  on-warning-container-dark: '#FFDCBE'
  glass-regular: '#FDFDFD8A'
  glass-regular-dark: '#3435379E'
  glass-pill: '#F4F4F494'
  glass-pill-dark: '#3435377A'
  glass-menu: '#FCF8F98C'
  glass-menu-dark: '#343537A1'
  glass-clear: '#FFFFFF1F'
  glass-fill: '#00000021'
  glass-fill-dark: '#FFFFFF21'
  glass-rim: '#FFFFFF'
  dock-platter: '#D9E2FFD9'
  dock-platter-dark: '#000D2AD9'
  shadow: '#0000001E'
  shadow-dark: '#0000002D'
  shadow-dock: '#00000014'
  shadow-dock-dark: '#0000003D'
  media-scrim: '#00000099'
  on-media: '#FFFFFF'
  viewport: '#000000'
  accent-blue: '{colors.primary}'
  accent-green: '#20C451'
  accent-indigo: '#596FF1'
  accent-teal: '#00ADC1'
  accent-orange: '#F57529'
  accent-red: '#F3483F'
  accent-amber: '#F7B418'
  accent-purple: '#9266E5'
  accent-gray: '#8799AC'
  device-screen: '#171F27'
  call-stage: '#141D32'
  call-key: '#2B3A57'
  call-text-secondary: '#B8C6E2'
typography:
  large-title:
    fontFamily: MiSans
    fontSize: 34px
    fontWeight: 700
    lineHeight: 41px
  title1:
    fontFamily: MiSans
    fontSize: 28px
    fontWeight: 700
    lineHeight: 34px
  page-title:
    fontFamily: MiSans
    fontSize: 24px
    fontWeight: 600
    lineHeight: 30px
  title3:
    fontFamily: MiSans
    fontSize: 20px
    fontWeight: 600
    lineHeight: 25px
  headline:
    fontFamily: MiSans
    fontSize: 17px
    fontWeight: 600
    lineHeight: 22px
  body:
    fontFamily: MiSans
    fontSize: 17px
    fontWeight: 400
    lineHeight: 22px
  subheadline:
    fontFamily: MiSans
    fontSize: 15px
    fontWeight: 400
    lineHeight: 20px
  label:
    fontFamily: MiSans
    fontSize: 15px
    fontWeight: 600
    lineHeight: 20px
  footnote:
    fontFamily: MiSans
    fontSize: 13px
    fontWeight: 400
    lineHeight: 18px
  caption:
    fontFamily: MiSans
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
  caption-emphasis:
    fontFamily: MiSans
    fontSize: 12px
    fontWeight: 600
    lineHeight: 16px
  caption2:
    fontFamily: MiSans
    fontSize: 11px
    fontWeight: 600
    lineHeight: 13px
  tab-label:
    fontFamily: MiSans
    fontSize: 11px
    fontWeight: 500
    lineHeight: 14px
rounded:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 20px
  xl: 24px
  xxl: 28px
  alert: 34px
  full: 999px
spacing:
  hairline: 1px
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  xxl: 24px
  xxxl: 32px
  jumbo: 40px
  section: 48px
  board: 80px
  group: 160px
components:
  phone:
    width: 402px
    height: 874px
  safe-area:
    height: 62px
    verticalPadding: 34px
  tablet:
    width: 1194px
    height: 834px
  desktop:
    width: 1440px
    height: 960px
  page:
    backgroundColor: '{colors.page}'
    textColor: '{colors.text}'
    padding: 16px
    maxWidth: 720px
  page-bar:
    height: 72px
    padding: 4px
    gap: 4px
    typography: '{typography.title3}'
  page-bar-root:
    typography: '{typography.page-title}'
  bar-button:
    size: 44px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass-regular}'
  bar-glyph:
    size: 24px
  section-button:
    size: 36px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.block}'
    textColor: '{colors.text}'
  section-glyph:
    size: 20px
  compact-button:
    size: 32px
  button-filled:
    height: 48px
    padding: 24px
    gap: 8px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary}'
    textColor: '{colors.on-primary}'
    typography: '{typography.label}'
  button-tonal:
    height: 48px
    padding: 24px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.block}'
    textColor: '{colors.text}'
    typography: '{typography.label}'
  button-destructive:
    backgroundColor: '{colors.block}'
    textColor: '{colors.error}'
    typography: '{typography.label}'
  button-text:
    height: 40px
    padding: 12px
    textColor: '{colors.primary}'
    typography: '{typography.label}'
  button-disabled:
    backgroundColor: '{colors.disabled-container}'
  disabled-label:
    textColor: '{colors.disabled}'
  destructive-filled:
    backgroundColor: '{colors.destructive}'
  control-focus:
    size: 2px
    borderColor: '{colors.primary}'
  list-group:
    rounded: '{rounded.xl}'
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
  list-row:
    height: 56px
    padding: 16px
    verticalPadding: 10px
    gap: 16px
    typography: '{typography.body}'
  list-row-pressed:
    backgroundColor: '{colors.pressed}'
  list-row-subtitle:
    textColor: '{colors.text-secondary}'
    typography: '{typography.subheadline}'
  list-header:
    height: 36px
    padding: 16px
    textColor: '{colors.text-secondary}'
    typography: '{typography.headline}'
  list-footer:
    textColor: '{colors.text-secondary}'
    typography: '{typography.footnote}'
  list-section:
    gap: 24px
  separator:
    height: 1px
    backgroundColor: '{colors.separator}'
  chevron:
    size: 18px
    textColor: '{colors.outline}'
  icon-tile:
    size: 30px
    rounded: '{rounded.sm}'
    textColor: '{colors.on-media}'
  icon-tile-glyph:
    size: 18px
  icon-tile-device:
    backgroundColor: '{colors.accent-blue}'
  icon-tile-connection:
    backgroundColor: '{colors.accent-green}'
  icon-tile-file:
    backgroundColor: '{colors.accent-indigo}'
  icon-tile-media:
    backgroundColor: '{colors.accent-teal}'
  icon-tile-transfer:
    backgroundColor: '{colors.accent-orange}'
  icon-tile-notification:
    backgroundColor: '{colors.accent-red}'
  icon-tile-display:
    backgroundColor: '{colors.accent-amber}'
  icon-tile-archive:
    backgroundColor: '{colors.accent-purple}'
  icon-tile-utility:
    backgroundColor: '{colors.accent-gray}'
  card:
    rounded: '{rounded.md}'
    padding: 16px
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
  hero-card:
    rounded: '{rounded.xxl}'
    padding: 20px
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
  device-tile:
    size: 52px
    rounded: '{rounded.md}'
    backgroundColor: '{colors.primary-container}'
    textColor: '{colors.on-primary-container}'
  device-screen:
    backgroundColor: '{colors.device-screen}'
  status-dot:
    size: 12px
    backgroundColor: '{colors.success}'
  input:
    height: 48px
    padding: 12px
    rounded: '{rounded.md}'
    backgroundColor: '{colors.inset}'
    textColor: '{colors.text}'
    typography: '{typography.body}'
  input-error:
    textColor: '{colors.error}'
    typography: '{typography.footnote}'
  search-field:
    height: 44px
    padding: 12px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.inset}'
    textColor: '{colors.text}'
    typography: '{typography.body}'
  chip:
    height: 36px
    padding: 16px
    gap: 6px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
    typography: '{typography.label}'
  chip-selected:
    backgroundColor: '{colors.primary}'
    textColor: '{colors.on-primary}'
  tag:
    padding: 6px
    rounded: '{rounded.sm}'
    backgroundColor: '{colors.block}'
    textColor: '{colors.text-secondary}'
    typography: '{typography.caption-emphasis}'
  tag-success:
    backgroundColor: '{colors.success-container}'
    textColor: '{colors.on-success-container}'
  tag-warning:
    backgroundColor: '{colors.warning-container}'
    textColor: '{colors.on-warning-container}'
  tag-error:
    backgroundColor: '{colors.error-container}'
    textColor: '{colors.on-error-container}'
  segmented:
    height: 44px
    padding: 4px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.block}'
    textColor: '{colors.text-secondary}'
    typography: '{typography.subheadline}'
  segmented-thumb:
    backgroundColor: '{colors.primary}'
    textColor: '{colors.on-primary}'
    typography: '{typography.label}'
  switch:
    width: 52px
    height: 32px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary}'
  switch-off:
    backgroundColor: '{colors.inset}'
  switch-thumb:
    size: 24px
    backgroundColor: '{colors.on-primary}'
  switch-thumb-off:
    backgroundColor: '{colors.outline}'
  selection-mark:
    size: 22px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary}'
    textColor: '{colors.on-primary}'
  progress:
    height: 3px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.primary}'
  navigation-dock:
    width: 274px
    height: 62px
    padding: 4px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass-pill}'
  dock-item:
    width: 86px
    size: 28px
    gap: 2px
    textColor: '{colors.text-secondary}'
    typography: '{typography.tab-label}'
  dock-platter:
    backgroundColor: '{colors.dock-platter}'
    textColor: '{colors.on-primary-container}'
  navigation-rail:
    width: 72px
  sidebar:
    width: 220px
    rounded: 10px
    height: 40px
    backgroundColor: '{colors.card}'
  foot-bar:
    height: 64px
    padding: 8px
    rounded: '{rounded.full}'
    backgroundColor: '{colors.glass-pill}'
    typography: '{typography.caption-emphasis}'
  glass-regular:
    backgroundColor: '{colors.glass-regular}'
    borderColor: '{colors.glass-rim}'
    blur: 2.5px
    saturation: 2.08
    opticalDepth: 60px
    refractionWidth: 20px
    specularIntensity: 0.28
    specularThickness: 1.2px
  glass-pill:
    backgroundColor: '{colors.glass-pill}'
    blur: 15.6px
    saturation: 2.1
    opticalDepth: 60px
    refractionWidth: 20px
    specularIntensity: 0.6
    specularThickness: 1.3px
    shadowBlur: 24px
    shadowOffset: 8px
  glass-menu:
    backgroundColor: '{colors.glass-menu}'
    blur: 12px
    saturation: 2.0
    opticalDepth: 60px
    refractionWidth: 20px
    specularIntensity: 0.16
    shadowBlur: 29px
    shadowOffset: 8px
  glass-alert:
    backgroundColor: '{colors.glass-menu}'
    blur: 16px
    saturation: 2.0
    opticalDepth: 60px
    refractionWidth: 20px
    specularIntensity: 0.16
    shadowBlur: 29px
    shadowOffset: 8px
  glass-clear:
    backgroundColor: '{colors.glass-clear}'
    blur: 1px
    opticalDepth: 60px
    refractionWidth: 20px
    specularIntensity: 0.4
  glass-on-glass:
    backgroundColor: '{colors.glass-fill}'
  glass-interaction:
    scale: 1.16
    stretch: 0.5
    glowIntensity: 0.16
  floating-shadow:
    backgroundColor: '{colors.shadow}'
    shadowBlur: 29px
    shadowOffset: 8px
  dock-shadow:
    backgroundColor: '{colors.shadow-dock}'
    shadowBlur: 24px
    shadowOffset: 8px
  menu:
    width: 240px
    padding: 8px
    rounded: '{rounded.xl}'
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
  menu-item:
    height: 44px
    padding: 12px
    size: 20px
    rounded: '{rounded.md}'
    typography: '{typography.subheadline}'
  alert:
    width: 348px
    padding: 30px
    rounded: '{rounded.alert}'
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
  alert-actions:
    height: 48px
    padding: 16px
    gap: 8px
  modal-scrim:
    backgroundColor: '{colors.scrim}'
  sheet:
    padding: 16px
    rounded: '{rounded.xxl}'
    backgroundColor: '{colors.page}'
    textColor: '{colors.text}'
  sheet-handle:
    width: 28px
    height: 4px
    backgroundColor: '{colors.text-secondary}'
  form-sheet:
    width: 440px
    rounded: '{rounded.alert}'
  banner:
    height: 52px
    padding: 18px
    rounded: '{rounded.xl}'
    backgroundColor: '{colors.card}'
    textColor: '{colors.text}'
    typography: '{typography.label}'
  empty-state:
    width: 320px
    padding: 32px
    size: 160px
  skeleton:
    rounded: '{rounded.full}'
    backgroundColor: '{colors.inset}'
  thumbnail:
    rounded: '{rounded.sm}'
    backgroundColor: '{colors.block}'
  media-protection:
    height: 64px
    backgroundColor: '{colors.media-scrim}'
  remote-viewport:
    backgroundColor: '{colors.viewport}'
  remote-navigation:
    height: 48px
  remote-handle:
    width: 12px
    height: 52px
  call-stage:
    backgroundColor: '{colors.call-stage}'
    textColor: '{colors.on-media}'
  call-stage-secondary:
    textColor: '{colors.call-text-secondary}'
  call-key:
    size: 64px
    backgroundColor: '{colors.call-key}'
  call-primary-key:
    size: 72px
  canvas-label:
    textColor: '{colors.outline}'
    typography: '{typography.footnote}'
---

# 邻接 · 设计规范

邻接以当前设备、文件、来电或画面为焦点。界面沿用 [Prism UI 0.1.3](https://github.com/chen08209/prism_ui/tree/v0.1.3) 的视觉语言：灰色页面上的白色内容面、连续圆角、所有控件为胶囊，液态玻璃只用于浮在内容上的操作层。行为见[产品规格](prod/README.md)，过渡与触点反馈见[页面交互与动效](interaction-motion.md)，画板见 [Ardot《邻接 · 近场工作台》](https://ardot.tencent.com/file/749360133997361?node_id=2%3A14)。

## 设计系统

| 对象 | 唯一来源 | 使用方式 |
| --- | --- | --- |
| 颜色、字号、圆角、间距、组件尺寸、玻璃参数 | 本文 frontmatter | Flutter 生成 `DesignTokens`；Ardot 由 [ardot.mjs](../scripts/design_tokens/ardot.mjs) 导出「邻接 · 主题」「邻接 · 固定色」「邻接 · 尺寸」三个变量集合 |
| 界面图标 | [图标角色登记表](icons.json) | 全部使用 Lucide。Flutter 生成 `AppIcons`；Ardot 图标库按 Lucide 名称命名（`图标 / chevron-left`），角色到图形的对照以登记表为准 |
| 控件外形、状态与材质 | Ardot 母组件集及 Flutter 共享控件 | 页面只提供文案、图标角色和状态，尺寸、材质、间距和交互由母组件决定 |

- `-dark` 后缀是同一角色的夜间值，无此后缀的颜色在明暗主题下相同。
- 页面不直接写色值，也不直接写尺寸。Ardot 中每个填充、描边、文字色都绑定变量；固定媒体色和功能色绑定「邻接 · 固定色」。
- 同步步骤见[生成与同步](../scripts/design_tokens/README.md)。

## 颜色

- 主色是亮蓝 `#4C88FF`，按 Prism `vivid` 风格生成整套色调。深色模式主色为 `#5C91FF`，主色上的文字为深蓝 `#001945`。
- 对比度例外：浅色主按钮的白字对比 3.35:1，卡片上的主色文字 3.18:1，都低于正文要求的 4.5:1。因此主色底白字只用于 15 点以上、600 字重的标签和图形，按大字标准 3:1 校验；主色文字只用于同样字重的文字按钮，说明性正文不用主色。
- 表面、文字和分隔线取自同一套 Prism 色调。品牌主色只用于主操作、选中和进度。
- 改用黑白主题时，只需把 `primary` 和 `on-primary` 换成 Prism `monochrome` 的值，其他角色不变。

### 表面层级

| 层级 | 浅色 | 深色 | 用于 |
| --- | --- | --- | --- |
| `page` | `#F0EDF0` | `#131315` | 页面底、抽屉底 |
| `card` | `#FCF8F9` | `#252628` | 分组列表、卡片、浮层的实体回退 |
| `block` | `#F0EDF0` | `#323235` | 卡片上的次要按钮、分段轨道、缩略占位 |
| `inset` | `#E4E2E5` | `#404042` | 输入框、搜索框、关闭的开关轨道、骨架 |

层级只靠色调区分，页面内的卡片不加阴影。每升一层就用下一级颜色：页面上的卡片用 `card`，卡片里的按钮用 `block`。浅色模式下 `block` 与 `page` 同色。深色模式只会越往上越亮。浮层的实体回退在浅色下用 `card`，深色下用 `block`。

### 文字与状态

- 文字只分两级：正文 `text`，次要信息、组头和图标用 `text-secondary`。不再设第三级灰。
- 分隔线是 `separator`（正文色 14%）。禁用前景为正文色 38%，禁用底为正文色 12%。行按压用 `pressed` 覆盖整行。
- `primary` 用于主按钮、分段选中、开关打开、选择标记、进度、文字按钮和导航选中的图形与标签。同一屏只放一个主按钮。
- 状态色各有容器色，用于标签和横幅：成功 `success`，警告 `warning`，错误 `error`。`destructive` 只用于不可逆动作的图形和实色确认按钮。危险动作的文字用 `error`，以保证 4.5:1 对比。
- 状态图形单独出现时必须有读屏名称；状态文字沿用正文色，旁边的图形负责着色。

### 功能色

功能入口用 30 点圆角方块加白色 Lucide 图形，名称写在色块外。明暗主题共用同一组功能色。

| 功能 | 组件 | 颜色 |
| --- | --- | --- |
| 设备、远控、窗口比例、导航键 | `icon-tile-device` | `accent-blue`（品牌主色） |
| 连接、授权、电话 | `icon-tile-connection` | `accent-green` |
| 文件与目录 | `icon-tile-file` | `accent-indigo` |
| 照片、视频、清晰度、帧率 | `icon-tile-media` | `accent-teal` |
| 传输与交付 | `icon-tile-transfer` | `accent-orange` |
| 通知、清空与重置类入口 | `icon-tile-notification` | `accent-red` |
| 显示、外观、点亮与熄屏 | `icon-tile-display` | `accent-amber` |
| 归档、记录与恢复 | `icon-tile-archive` | `accent-purple` |
| 通用设置、日志、诊断、关于、保持唤醒 | `icon-tile-utility` | `accent-gray` |

- 色块上的图形一律为白色 `on-media`，任何主题都不随正文色变化。
- 文件格式沿用同一组色：文件夹和压缩包 `accent-amber`，PDF `accent-red`，文档 `accent-indigo`，图片和视频 `accent-purple`，音频 `accent-teal`。列表、宫格、搜索结果和传输缩略占位使用同一格式色。
- 添加设备的五种方式使用彩色线形图标，不加色块：附近 `accent-teal`，配对码 `accent-green`，扫码 `accent-purple`，USB `accent-orange`，IP `accent-blue`。

## 文字

设计稿使用 MiSans（Regular、Medium、Semibold、Bold）。App 使用宿主系统字体及中文回退，并跟随系统字号；稿件字体不打包。字号沿用 iOS Dynamic Type 的默认档，字距为 0。

| 角色 | 字号／行高 | 字重 | 用于 |
| --- | --- | --- | --- |
| `large-title` | 34/41 | 700 | 来电姓名、连接过程标题 |
| `title1` | 28/34 | 700 | 工作台设备名、通话计时 |
| `page-title` | 24/30 | 600 | 根页（设备、传输、设置）页头标题 |
| `title3` | 20/25 | 600 | 子页页头、抽屉和表单标题 |
| `headline` | 17/22 | 600 | 列表组头、卡片标题、确认框标题、空态标题 |
| `body` | 17/22 | 400 | 列表行标题、输入、搜索、确认框按钮 |
| `subheadline` | 15/20 | 400 | 行副标题、行尾值、菜单项、说明正文 |
| `label` | 15/20 | 600 | 所有带文字的按钮、chip、分段选中项、横幅 |
| `footnote` | 13/18 | 400 | 列表脚注、字段说明、错误提示、时间 |
| `caption` / `caption-emphasis` | 12/16 | 400 / 600 | 元数据；状态标签与底栏标签用 600 |
| `caption2` | 11/13 | 600 | 角标、计数 |
| `tab-label` | 11/14 | 500 | 底部导航标签 |

- 强调只用 600；700 只出现在 28 点及以上。
- 正文与背景对比至少 4.5:1，大字及有意义图形至少 3:1，玻璃上的对比在实际采样背景上测量。
- 支持 200% 文字：行、按钮和页头随内容增高，横排可改为纵排，网格减少列数，关键动作和来源不截断。普通触控目标至少 44×44 点。

## 形状与间距

- 所有圆角都是连续圆角（Ardot `cornerSmoothing` 0.6）。圆角取 `xs 4`、`sm 8`、`md 16`、`lg 20`、`xl 24`、`xxl 28`、`alert 34`、`full`，不使用其他值。
- 按钮、chip、搜索框、分段、导航、底栏和页头按钮一律为胶囊。
- 嵌套圆角同心：外角 = 内角 + 内距（菜单 24 = 项 16 + 8）。小元素取不超过短边三分之一的最大档：30 点色块为 8，52 点设备块为 16。
- 分组列表和内容卡片用 `xl 24`，小卡片和输入框用 `md 16`，工作台概览卡用 `xxl 28`，缩略图用 `sm 8`。
- 间距只用 2、4、8、12、16、20、24、32、40、48。页面左右边距 16；组与组之间 24；卡片内距 16；同组元素间 8 或 12。

## 材质

### 实体与玻璃的分工

| 对象 | 材质 |
| --- | --- |
| 页面、卡片、分组列表、表单、抽屉、侧栏、设备概览 | 实体 |
| 页头的图标按钮与按钮组、远控画面工具、远控把手 | `glass-regular` |
| 底部导航、文件与相册底栏 | `glass-pill` |
| 锚点菜单、弹出选项 | `glass-menu` |
| 确认框 | `glass-alert` |
| 照片与视频预览上的返回和底栏 | `glass-clear`，配亮色图形，按画面亮度加 `media-protection` |
| 页面底部的通栏主按钮 | 实体 `button-filled` |

- 「液态玻璃」设为关闭、玻璃渲染初始化完成前、系统开启降低透明度或提高对比度时，所有玻璃回退为实体浮层面（浅色 `card`，深色 `block`）加 `dock-shadow`，尺寸、位置、焦点不变。
- 「极致」在平台不支持完整折射时，按「标准」渲染。各平台默认档位见[设置与本地数据](prod/information-architecture.md#设置与本地数据)。
- 设计稿为每个玻璃组件同时提供玻璃与实体两种外观。

### 玻璃配方

Prism 的玻璃之所以“活”，靠的是以下五层叠加，单独提高透明度做不到：

1. **边缘折射带**：宽约 min(20, 高/4) 的边缘把背后内容向内压缩、镜像。内容滚到玻璃下方才看得出，所以设计稿中的列表、照片必须延伸到页头和底栏下方。
2. **上下高光**：1.2–1.3 点的白色内高光只出现在上下边缘，到圆端逐渐消失。没有光源方向，也不随手势转动。
3. **两侧深色细线**：0.67 点外缘线，左右两侧约 22% 黑，上下约 4–7%，用来勾出形状。
4. **饱和度提升**：背后内容饱和度提高 100–180%。
5. **底色**：浅色接近白，深色为 `#343537`。

| 预设 | 底色（浅／深） | 模糊 σ | 高光强度／宽度 | 阴影 |
| --- | --- | --- | --- | --- |
| `glass-regular` | 白 54% ／ `#343537` 62% | 2.5 | 0.28 / 1.2 | 无 |
| `glass-pill` | `#F4F4F4` 58% ／ `#343537` 48% | 15.6（雾化 72%） | 0.6 / 1.3 | 8% blur 24 y8 + 4% blur 3 y1 |
| `glass-menu` | 卡片色 55% ／ `#343537` 63% | 12 | 顶部内光 16% | 11.8% blur 29 y8 |
| `glass-alert` | 同 menu | 16 | 同 menu，两侧细线 35% | 同 menu |
| `glass-clear` | 白 12% | 1 | 0.4 / 1.2 | 无 |

玻璃上的二级填充（例如确认框里的非主按钮）用 `glass-on-glass`：浅色黑 13%，深色白 13%。

### Ardot 中的表达

Ardot 的 `GLASS` 效果配合描边可以还原以上五层。所有玻璃母组件使用同一结构，只换参数：

| 预设 | 填充 | GLASS（lightIntensity / lightAngle / refraction / depth / dispersion / radius / splay） | 描边 |
| --- | --- | --- | --- |
| regular | `邻接 · 主题/glass-regular` | 0.6 / 90 / 0.9 / min(20, 高/4) / 0.05 / 5 / 0.2 | 高光 + 细线 |
| pill | `glass-pill` | 0.7 / 90 / 0.9 / 20 / 0.05 / 14 / 0.2 | 高光 |
| menu、alert | `glass-menu` | 0.5 / 90 / 0.6 / 20 / 0 / 24（alert 32）/ 0.15 | 高光 + 细线 |
| clear | `邻接 · 固定色/glass-clear` | 0.8 / 90 / 0.9 / min(20, 高/4) / 0.1 / 2 / 0.25 | 高光 |

- 高光描边：内描边 1.2，纵向线性渐变，白色 70% → 0（30%）→ 0（70%）→ 70%。
- 细线描边：内描边，横向线性渐变，黑 22% → 4%（15%）→ 4%（85%）→ 22%。
- 阴影按上表加在同一节点。媒体上的 clear 不加阴影。

### 底部导航

- 胶囊高 62，内距 4，每项宽 86，三项总宽 274。底边距取 21 与底部安全区中的较大值，水平居中。
- 图形 28、标签 `tab-label`，未选中为 `text-secondary`；选中项标签加重到 600，侧栏、导航轨道与竖向导航同此。
- 选中项是宽 ≥ 84 的实色托盘：浅色 `#D9E2FF` 85%，深色 `#000D2A` 85%，图形和标签为 `on-primary-container`（主色在托盘上对比不足 3:1）。
- 按住时托盘化为透明放大镜：各边外扩 8，内容放大 1.16 倍，边缘有约 3 点红蓝色散，阴影 5.5% blur 5 y8。设计稿在分镜中表达这一帧。

## 控件

### 按钮

按钮的填充表示它的角色，尺寸由所在位置决定。同一种角色在任何页面都长一样。

| 角色 | 填充 | 前景 | 用于 |
| --- | --- | --- | --- |
| 主要 `button-filled` | `primary` | `on-primary` | 每屏唯一的主动作：页面底部提交、确认框最后一项、工作台「打开手机屏幕」 |
| 次要 `button-tonal` | 所在面的下一层（页面上 `card`，卡片上 `block`） | `text` | 与主动作并列的动作、行尾动作、卡片内动作 |
| 危险 `button-destructive` | 同次要 | `error` | 断开、移除、删除、清空。确认框中危险动作放在主位置时用 `destructive` 实色、白字 |
| 文字 `button-text` | 无 | `primary` | 帮助、编辑、全部应用、查看更多等轻量入口 |
| 图标按钮（页头） | `glass-regular` | `text` | 返回、关闭、搜索、添加、更多、设置 |
| 图标按钮（卡片内） | `block` | `text` | 卡片标题行尾的操作 |

| 尺寸 | 高度 | 图形 | 位置 |
| --- | --- | --- | --- |
| 停靠 | 48 | 24 | 页面底部、确认框、工作台主次按钮 |
| 页头 | 44 | 24 | 页头与 Duo 竖栏 |
| 区块 | 36 | 20 | 列表行尾、卡片标题行、组头 |
| 紧凑 | 32 | 20 | 密集工具、宫格角落 |

- 所有带文字的按钮用 `label`（15/20 600），图标在文字前，间距 8。
- 页面上独立的危险动作（清理可释放的暂存、重置身份、清空日志、清空导入记录等）不做成列表行：用整宽停靠尺寸的危险按钮，放在页面底上（`card` 底、`error` 文字），图形在前、文字居中，与上一组相隔 24，说明文字放在按钮下方作组脚。执行前仍用确认框确认。
- 页头相邻的两个及以上图标按钮合成一个玻璃胶囊（按钮组），每项保留独立命中区，组内间距 0、项宽 44。单个按钮是 44 点正圆。
- 返回一律是页头起始侧的 44 点玻璃圆键加 `back` 图标。照片与视频预览上改用 `glass-clear`。没有裸箭头返回。
- 行尾文字导航（如「配对码帮助」）是 `button-text`，不加箭头。可点进入下一页的整行用列表行加 `chevron`。
- 按压反馈见[触点反馈](interaction-motion.md#触点反馈)。
- 禁用：前景 `disabled`，底 `disabled-container`；确认框中的禁用动作保留原填充。焦点环为 2 点 `primary`，在实色或玻璃上外移 1 点。

### 列表

- 分组列表是一张 `list-group`：外圈圆角 24，行与行之间不留间隙，用 `separator` 分隔。分隔线从标题文字的起点开始，到右缘前 16 结束；最后一行、按压行及其相邻行下方不画分隔线。
- 行最小高 56，左右内距 16，上下至少 10，前导与标题间距 16。标题 `body`，副标题 `subheadline` + `text-secondary`。行尾值用 `subheadline` + `text-secondary`，导航行尾加 18 点 `chevron`。
- 前导可以是功能色块（30 点）、设备块（52 点）、文件格式图标或应用原图标，同一组内前导类型一致。
- 组头在卡片外，`headline` + `text-secondary`，内距左右 16、上 24、下 8；组脚用 `footnote`。根页标题下的第一组省略上 24。
- 动态列表（设备、文件、通知、传输任务）同样用分组卡片。只有当条目带有独立操作区或缩略图时，才拆成彼此相隔 12 的独立 `card`（圆角 24）。
- 选择态在行尾用 22 点圆形 `selection-mark`：未选为 `outline` 1.5 点空心圆，选中为 `primary` 实心加白色对勾。列表里选择标记与箭头共用 22 点尾槽，切换选择态时文字宽度不变。宫格（文件与相册）的选择标记叠在缩略图区域正中，用叠放样式 `selection-mark-overlay`：直径 26，白色 1.5 圆环；未选时内部为 28% 黑底，已选时为 `primary` 实心加白色对勾。叠放标记明暗模式下都用白色，不随 `on-primary` 变化。

### 输入与选择

- 输入框 `input`：高 48，圆角 16，`inset` 底，无描边；聚焦时加 2 点 `primary` 内描边。标签在框上方，用 `footnote` + `text-secondary`，间距 8；错误提示在框下方，用 `footnote` + `error`。
- 搜索框 `search-field`：高 44 胶囊，`inset` 底，起始 20 点搜索图形，尾部清除按钮。
- 开关 52×32：打开为 `primary` 轨道和白色滑块，关闭为 `inset` 轨道和 `outline` 滑块，滑块 24。命中区覆盖整行。
- 分段 `segmented`：高 44，轨道为所在面的下一层，内距 4，选中项是 `primary` 胶囊加 `on-primary` 600 标签，其他项 `text-secondary`。设置的外观、传输的「传输中／已结束」、添加设备的连接方式都用这一个组件。添加设备的分段项是图标在上、标签在下的高 64 变体。
- chip：高 36 胶囊，未选 `card` 底，选中 `primary` 底。筛选与范围一律用 chip，同一行 chip 的样式必须一致；带下拉的 chip 在尾部加 16 点向下箭头。
- 状态标签 `tag`：圆角 8，`caption-emphasis`，成功、警告、错误各用对应容器色。
- 单选弹层：每项为列表行，当前项行尾为 `primary` 对勾，不另加底色。

### 菜单、确认框与抽屉

- 锚点菜单 `menu`：宽 160–280，外角 24、内距 8，项高 44、项角 16、项内距 12，图形 20 在文字前、间距 12。危险项用 `error`。菜单最多显示 7 项，多出时露出半项提示滚动。
- 确认框 `alert`：宽 348，圆角 34。标题 `headline`，内距 30/21/30/0；正文 `subheadline` + `text-secondary`，内距 30/6/30/20。动作区内距 16/0/16/16，按钮高 48、间距 8：横排放得下时并排，主动作在右；放不下时纵排，取消在最下。遮罩浅色黑 20%，深色黑 48%。
- 抽屉 `sheet`：底为 `page`，顶角 28，把手 28×4 居中距顶 6，标题栏高 48。宽窗改用居中的 `form-sheet`（宽 440，圆角 34）。
- 横幅 `banner`：最小高 52，圆角 24，内距 18/12，`label` 字，最多 3 行。信息用浮层面或玻璃，成功、警告、错误用容器色。

### 空态、加载与进度

- 空态：居中略偏上（纵向 40%），最宽 320。插图 160：`primary-container` 柔形底（圆、波浪圆或超椭圆）上放 64 点 `primary` 线形图形；下方 16 为 `headline` 标题，8 为 `subheadline` 说明，24 为主按钮。
- 整页加载：三枚 `primary` 形状（圆、12 波浪圆、超椭圆）各 20 点，间距 52，依次跳起 30 点，地面为 44×6 的 `primary-container` 胶囊。出现时机和节奏见[等待与状态切换](interaction-motion.md#等待与状态切换)。
- 骨架：`inset` 胶囊，沿真实内容的几何排列；占位不接收焦点，每个加载区域提供一个读屏状态。
- 进度条：高 3 胶囊，`primary` 前景，`primary-container` 轨道。页头下方的整页进度贴住页头底边。不定进度用 24 点 `primary` 环形指示器。

## 页面结构

- 手机画板 402×874，顶部安全区 62，底部 34。状态栏和 Home 指示条用「系统 / 状态栏」「系统 / Home 指示条」组件，明暗各一。
- 页头 `page-bar`：安全区下高 72，背景透明，底部有一段页面色 90% → 0 的渐隐，延伸到页头下 16。正文从页头下 12 开始，并能滚到页头和底部导航下方。
- 根页（设备、传输、设置）：无返回，标题 `page-title` 起始距边 16，尾部为页头按钮或按钮组，距边 8。
- 子页：起始为 44 点玻璃返回键，距边 8；标题 `title3` 紧跟其后，间距 8；尾部操作同上。标题过长时单行截断，完整标题由读屏提供。
- 选择态复用同一页头：起始为关闭，中间是所选数量（`title3`），尾部为全选或取消全选。
- 底部固定动作：通栏 `button-filled`，左右 16，底边留出安全区和 8 点。正文最后一项可滚到按钮上方。与底部导航同时出现时，固定动作在导航上方。
- 文件与相册底栏 `foot-bar`：高 64 胶囊，左右 16，各项等宽，24 点图形在上、`caption-emphasis` 标签在下。菜单从动作向上展开。
- 远控画面铺满视口，三键导航栏高 48、背景为 `viewport`；返回为朝左的圆角空心三角，主屏幕为空心圆，最近任务为圆角空心方形。
- 远控把手吸附时是 12×52 的玻璃竖条，外侧贴齐当前窗口的安全侧边，中央画一条 2×24 的握条；命中区从边缘向内 44×52，不挤压画面。点按后从同侧展开 `glass-regular` 工具面板：图形在上、标签在下，三列等宽；「关闭画面」是面板底部通栏的 `button-destructive`，底色取玻璃上的 `glass-on-glass`。

## 页面模式

### 设备与工作台

- 设备列表是一张分组卡片。每行：52 点 `device-tile`（手机或平板线形图形）+ 12 点 `status-dot` 叠在设备块右下，外圈 2 点 `card` 描边；标题为设备名，副标题为状态 · 连接方式或最近在线时间。行尾为区块尺寸的 `button-tonal`（打开屏幕、连接、重试），所有设备行的行尾按钮样式相同。
- 状态点：已连接 `success`，离线为 `outline` 空心环，连接中为 `primary` 线弧，需要处理用 `warning`，失败用 `destructive`。同时提供状态文字和读屏状态。
- 搜索：点按页头搜索后，标题和页头按钮原位替换为 `search-field` 加关闭按钮。
- 首次添加：空态插图为设备靠近的线稿（`primary` 与 `primary-container`），标题「添加第一台设备」，下方 `button-filled`。
- 工作台概览 `hero-card`：左侧设备名（`title1`）、系统版本、电量与连接方式；右侧手机轮廓（外框 `outline`，屏面 `device-screen`）中央显示连接状态。下方「打开手机屏幕」`button-filled` 与「设备详情」`button-tonal` 等宽并排。连接中、未连接、失败共用同一布局，只换主按钮文案与状态图形。
- 快捷入口：文件、相册、通知、电话四个 52 点功能色块（圆角 16）加下方 `footnote` 标签，放在一张卡片内等宽排列。未连接时色块保留功能色，降到 38% 不透明并禁用。
- 「常用应用」「正在运行」各一张卡片：标题行为 `headline` 加尾部 `button-text`（编辑、全部应用），内容为应用原图标宫格，图标 48、标签 `caption`。

### 添加设备与连接

- 「附近设备」是页面顶部的单行列表卡片，下方是连接方式分段（图标在上的 64 高变体）。
- 表单字段沿 16 点边距排列，底部通栏主按钮。帮助入口为左对齐的 `button-text`。
- USB 状态卡居中显示线缆、状态槽和手机，状态槽用状态点规则。
- 连接过程全屏、无页头，中央为本机与手机的连线，下方 `large-title` 标题和 `subheadline` 阶段文字，底部为「取消连接」`button-tonal`。失败时连线断开，原位置显示原因和恢复动作。

### 手机屏幕与应用

- 首帧等待：画面区为 `page`，页头起始侧为关闭按钮。168×332 手机示意（`device-screen` 底、圆角 34）身后为主色光晕，屏内是整页加载形状；下方 `title3` 标题、`subheadline` 设备名，再下为阶段卡片（`card`、圆角 24，行高 44）：完成为 `success` 勾，进行中为旋转的 `primary` 圈与加粗正文，待开始为虚线圈。失败时示意屏中央换成 72 点 `error-container` 警示标记，原因居中，失败步骤为 `error` 叉与加粗文字，底部固定「重试」`button-filled`，其余动作为次要胶囊。内容最宽 400 居中；矮而宽的窗口示意在起始侧、文字与阶段在另一侧。
- 熄屏：黑色视口中央为 `glass-clear` 的「点亮屏幕」胶囊按钮。暂停提示用横幅，位于最后一帧上方安全区。
- 画面与控制、应用接续等设置页沿用分组列表；选择类设置在行尾显示当前值和 `chevron`，点按打开单选弹层。

### 文件与相册

- 文件首页：类型入口为两列小卡片（功能色块 + 名称），下方是目录宫格。宫格缩略区为 `block` 底的 `card`，文件夹为 `accent-amber` 线形图形。
- 目录列表用分组卡片，行前导为文件格式色块，副标题为日期与大小，行尾 `chevron`；选择态把 `chevron` 换成 `selection-mark`，行不位移。
- 路径与搜索：搜索框在上，路径用 chip 行，当前目录 chip 选中。
- 相册按日期分组，缩略图三列（手机）、间距 2、圆角 0，视频右下角叠时长标签。
- 预览页为黑色媒体底，返回和底栏用 `glass-clear`，顶部、底部按亮度加 `media-protection` 渐变。

### 传输

- 根页标题下方为「传输中／已结束」分段。
- 每个任务一张 `card`（圆角 24，间距 12）：左侧 48 点缩略或格式图标，中间文件名、方向与来源 → 目标（`footnote`），下方 `progress` 与已传／总量；右上角显示百分比或状态 `tag`。
- 待处理、失败用 `tag-warning` / `tag-error`，完成用 `tag-success`。

### 通知与电话

- 通知按日期分组，每条为独立 `card`：36 点应用原图标、标题一行、正文最多两行，右上时间，右下 32 点紧凑清除按钮（`block` 底）。页头尾部为「清除全部」图标按钮。
- 电话页为通话舞台：`call-stage` 底上三团静态模糊彩光（`primary`、`accent-teal`、`accent-indigo`）。页头为 `glass-clear` 返回键与居中的 `glass-clear` 来源胶囊（高 32，「设备名 · 声音位置」）。联系人居中：头像 120、白色 2 描边，姓名 `large-title` 白色，阶段 `body` 白色 72%；响铃时头像外有 256/208/160 三道淡白同心环，通话中头像身后为主色光晕并显示声波，读取中断时头像变暗并带 `accent-amber` 断开徽标，画面待核对为 160 虚线环。没有通话时头像 112、`call-key` 底与电话图形。有通话时打开手机画面为 `glass-clear` 胶囊；没有通话或待核对时为 `button-filled`；读取中断的说明与「检查通话状态」放在圆角 34 的 `glass-clear` 托盘内。拒接、接听、静音、声音等 72/64 点圆键只在能力支持时出现。

### 设置

- 根页「设置」分为「使用偏好」和「本机数据」两组，每行功能色块 + 标题；即时生效的偏好在行尾直接放开关或分段，其余为导航行。外观分段在窄窗或大字下移到行内下一行。
- 「关于与更新」行尾显示版本号。更新弹窗沿用 `alert` 结构，宽而矮的窗口左右排列版本信息和更新说明。

## 文案与反馈

- 用用户正在使用的功能名称说明发生了什么，再给一个可执行的下一步。表单在字段旁指出要改的内容，页面读取失败在原处提供重试。系统错误原文、代码和内部路径不出现在普通提示中。
- 失败与待核对用不同文案，复用[提交反馈](prod/interaction-rules.md#内容保护与提交反馈)中的下一步。仍显示旧内容时注明时效。
- 页头只保留任务标题与必要操作。容量、来源、路径和状态跟随所属数据呈现；跨设备操作就近标明来源与目标。
- 进度和失败靠近受影响的条目、分区或触点。先出现页头、路径、页签和导航，骨架只放在受影响的列表或网格。

## 自适应窗口与形态

以当前窗口的安全可用矩形为准：先扣除宿主窗口边框、安全区和系统保留区，再测量宽 W、高 H。W 在分配应用自己的导航和窗格之前测量；铰链把视口分成多块时，分别测量每块。[Apple 布局指南](https://developer.apple.com/design/human-interface-guidelines/layout)

| 窗口 | 结构 | 说明 |
| --- | --- | --- |
| W < 600 | 单列 + 底部导航 | 列表点入详情。桌面上应用页头在标题栏下方，见[桌面窗口标题栏](#桌面窗口标题栏) |
| 600 ≤ W < 840 | 72 点图标导航轨道 + 单窗格 | 详情原位替换窗格，返回恢复列表 |
| 840 ≤ W < 1080 | 220 点文字侧栏 + 单窗格 | 表单与详情居中在 720 阅读列内，宫格随宽度变化 |
| W ≥ 1080 | 文字侧栏 + 列表／详情双栏 | 两窗格各至少 360 点、各自滚动。设备与工作台、传输与任务详情用此结构 |
| H < 480 或键盘占据操作区 | 优先保证正文可滚动、固定动作可达 | 更新弹窗左右排列；弹层按剩余高度滚动 |

- 侧栏：实体 `card` 底，项高 40、圆角 10、项间距 4，图形 24 + `subheadline` 标签；选中项为正文色 8% 底加 3×16 的 `primary` 指示条。
- 跨越阈值时保留当前设备、选中项、任务、草稿、弹层、焦点和各窗格的滚动位置。双栏收为单栏时保留当前详情，返回回到原列表位置。[响应式画板](https://ardot.tencent.com/file/749360133997361?node_id=9%3A1779)

### 远控窗口

- 设备页和工作台提供「远控窗口」入口，画面工具提供「切换窗口」。弹层内按设备分组的宫格：手机屏幕在本组首格，独立应用显示应用原图标和名称，当前画面用 `primary-container` 底。由画面进入时，标题下方提供「返回工作台」。
- 桌面远控子窗口的标题为「设备名 · 手机屏幕」或「设备名 · 应用名」，标题栏样式见[桌面窗口标题栏](#桌面窗口标题栏)。画面区按打开时手机屏幕的比例设置，手机旋转后调整。
- 普通屏的应用内窗口在 W ≥ 840 且两侧安全宽度均至少 360 点时可并排，间隔 8。折叠屏把铰链留空，按两侧实测宽度判断。[远控窗口画板](https://ardot.tencent.com/file/749360133997361?node_id=19%3A1) · [两路并排画板](https://ardot.tencent.com/file/749360133997361?node_id=20%3A1)

### 桌面窗口标题栏

Windows 和 Linux 主窗口：

- 隐去系统标题栏，改用应用自绘的标题栏：高 40，卡片底，应用名居左。
- 右侧依次为最小化、最大化（最大化后变为还原）、关闭：三个 28 点圆键，间隔 6，距右缘 6，块面底，图形为 1.5 描边圆头线条。
- 悬停时底色加深一档；关闭键悬停时为 `destructive` 底配白色图形。
- 在空白处拖动可移动窗口，双击切换最大化。窗口四边仍可拖动缩放，Windows 保留贴靠布局。[桌面标题栏组件](https://ardot.tencent.com/file/749360133997361?node_id=41%3A1357)

macOS 主窗口：

- 宽度 ≥ 600 时，页面和侧栏延伸到窗口顶边，保留左上角交通灯；页头和侧栏在交通灯高度下方再留 12。
- 宽度 < 600 时，显示独立的标题栏。[macOS 窗口画板](https://ardot.tencent.com/file/749360133997361?node_id=24%3A2)

通用：

- 标题栏里的窗口标题用 13/18 600，这是 `footnote` 唯一的加重用法。
- 沉浸状态下，页名和空白处可拖动窗口。
- 远控子窗口在各平台都使用系统原生标题栏和边框。

### iPhone Duo 专项

以 iOS 27.1 SDK 及以上的全显示区域和竖向栏行为为目标。外屏（竖、横）与内屏横向时，页头按钮和主导航沿系统指定外缘纵向排列；内屏竖向回到上下横栏。系统分屏时两侧窗口各用自己的外缘。[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

| 姿态 | 布局 |
| --- | --- |
| 外屏竖向与横向 | 单窗格。竖栏从上到下为系统相机区、页头按钮、主导航 |
| 内屏横向全展开 | 竖向栏。设备列表与工作台在两个各至少 280 点的安全窗格内并排，不足时只显示当前窗格 |
| 内屏竖向全展开 | 横向页头和底部导航；工作台用居中阅读列 |
| 书本半折 | 列表与详情分列铰链两侧；相机启用时只调整与保留区相交的内容 |
| 桌面半折 | 远控画面放上部安全窗格，画面工具放下部；只能容纳一个窗格时保留画面和工具入口 |
| 系统分屏与内屏弹层 | 按各窗口实际宽度分配窗格；弹层落在当前操作的安全窗格内 |

竖栏使用与页头相同的 44 点玻璃按钮，按钮组改为纵向胶囊；返回与关闭在顶部，读屏保留动作名称。阈值验证覆盖 599/600、839/840、1079/1080、479/480 两侧，以及开合、分屏、键盘、明暗、200% 字号、减少动态和降低透明度。[Duo 专项画板](https://ardot.tencent.com/file/749360133997361?node_id=9%3A1786)

## 应用图标

邻接的标记是一块屏幕与一部手机贴边相邻：亮蓝 `#4C88FF` 的横向屏幕，右下角叠一部深蓝 `#19438F` 的竖向手机，两者之间留出等宽白缝。默认外观为纯白底；深色外观为 `#131315` 底、`#5C91FF` 屏幕与 `#D9E2FF` 手机；单色外观沿用完整轮廓。白缝在 16–32 像素下仍可分辨两块形状。

iOS 与 iPadOS 使用出血方形，由系统加遮罩，提供默认、深色和着色外观。Android 分离前景、底色和单色层，前景放在 108 dp 画板的安全区中央。macOS Dock 使用带外缘留白的版本，Windows 使用多分辨率 ICO，Linux 应用菜单与窗口共用同一 SVG。[图标源文件](assets/app-icon.svg) · [Ardot 标识稿](https://ardot.tencent.com/file/749360133997361?node_id=12%3A985)

## Ardot 画布约定

- 文件分三页：「规范与组件」放变量说明、母组件集和图标库；「邻接 · 产品设计」放产品画板，按业务流程自上而下分区，区内从左到右按操作顺序排列，每行最多八张；「README 插画」放 README 配图，中英文各一套，以 0.625 倍导出为 JPEG 到 `docs/assets/readme/`。配图由产品画板复制拼成，画板改版后重新复制并导出。
- 画板命名「编号  页面 · 状态」，同页状态、就地面板、深色、200% 字号和分镜紧跟主稿，命名为「编号 · 类型  说明」。移动或重做画板时保留节点 ID，以免文档链接失效。
- 母组件都是组件集，用变体表达尺寸、状态和明暗（例如「按钮」：角色 × 尺寸 × 状态）。同一控件只保留一个组件集；页面只放实例，不脱离组件。
- 所有容器使用自动布局。只有叠放关系（状态点、玻璃浮层、媒体保护）使用绝对定位。
- 明暗主题通过在画板上切换「邻接 · 主题」的日间／夜间模式实现，不复制一套深色组件。
- 说明文字用 `canvas-label`，放在画板外；画板内只放真实界面。

## 改稿验收

改稿后的检查项只写在[设计规则 · 验证](AGENTS.md#验证)。本文的校验与 Ardot 变量核对命令见[生成与同步](../scripts/design_tokens/README.md)。

依据：[Prism UI 0.1.3](https://github.com/chen08209/prism_ui/tree/v0.1.3)、[Apple 材料指南](https://developer.apple.com/design/human-interface-guidelines/materials)、[Apple 无障碍指南](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Apple 字体指南](https://developer.apple.com/design/human-interface-guidelines/typography)、[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)。
