# HarmonyOS 窗口适配与 Flutter Liquid Glass 研究

更新时间：2026-11-14

本笔记只记录官方一手资料和当前仓库依赖的公开文档，用于后续右侧栏、多窗口和材质重构。代码仍需在真实设备/模拟器上验证。

## HarmonyOS 开发套件与可验证环境

- [DevEco Studio 安装指南](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-software-install/)说明：DevEco Studio 集成 HarmonyOS SDK、Node.js、Hvigor、ohpm 和 Emulator；Windows 需要 64 位 Windows 10/11、至少 16 GB 内存和 100 GB 磁盘，macOS 支持 Intel/Apple Silicon，至少 8 GB 内存和 100 GB 磁盘。HarmonyOS SDK 随 DevEco Studio 提供，不需要单独下载；OpenHarmony SDK 在 IDE 的 OpenHarmony SDK 设置中下载。
- [DevEco Studio 下载页](https://developer.huawei.com/consumer/en/deveco-studio)是官方入口，并提供多设备预览、构建分析和调试工具。
- 当前仓库环境没有 `ohpm`、`hvigorw`、`hdc` 或 `ohos/` 宿主工程，因此不能把鸿蒙原生窗口截图或构建结果伪装成已验证。下一步应在可安装 DevEco Studio 的 macOS/Windows 环境导入单独的 Harmony 宿主，先验证窗口回执，再接入 Flutter 容器。

## HarmonyOS 窗口模式和身份

- [Window Mode Overview](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/window-mode-overview/)把窗口状态区分为 full-screen、floating、split-screen、maximize/minimize 等；窗口模式是单个窗口的属性。应用应查询当前状态并监听变化；`windowStatusDidChange` 在窗口尺寸 Rect 更新后触发，适合读取新的可用窗口边界。
- 同一文档说明：freeform 浮窗可移动、调整大小、组合为分屏；主窗口默认有系统标题栏和三个控制按钮。应用内容不应再绘制一个与系统标题栏重复的顶部状态条。split-screen 当前是双窗并可拖动分隔线。
- 窗口模式支持应在 `module.json5` 的 `supportWindowMode`、启动参数或运行时 `setSupportedWindowModes()` 中声明；运行时设置优先级最高。默认支持值可包含 `fullscreen`、`split`、`floating`。
- [Introduction to Multi-Window](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/multi-window-intro/)说明：折叠设备展开态和部分平板支持最多三个 multitask view 窗口；滑动侧窗可能不可见，应监听 `windowVisibilityChange`。多窗口尺寸由系统决定，不能假设固定宽度。
- [FoldSplitContainer API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V14/ohos-arkui-advanced-foldsplitcontainer-V14/)和[半折叠最佳实践](https://developer.huawei.com/consumer/en/doc/best-practices/bpta-folded-hover/)说明：`FoldSplitContainer` 为双栏或三栏折叠布局提供 `primary`、`secondary`、`extra` 区域，并在半折叠状态自动避开折痕。其区域比例由 layout options 控制，不能在 Flutter 侧把折痕当成普通 padding 猜测。
- [Window FAQ](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/window-faqs/)给出 `getWindowStatus()`、`windowStatusChange` 和 `windowStatusDidChange` 的查询/监听方式，并展示 `supportWindowMode` 配置。Flutter 宿主应把窗口身份、模式、Rect、insets 和折痕/保留区作为一个原子环境投影发送给 Dart，避免只发送宽度导致右侧栏 stale。

### 对当前右侧栏的直接结论

1. 右侧栏不能用“设备类型 = 平板/折叠屏”作为唯一条件；应由当前窗口的可用 Rect、方向、分隔区和模式决定。
2. 在 Harmony freeform/floating 窗口，右侧栏需要能在窗口缩小时变成紧凑操作 rail 或移入工具栏；不能保持固定宽度而挤压正文。
3. 在 split-screen 或折叠分区，侧栏与详情必须先对可用 pane 做约束，避开系统分隔线、折痕和 insets；窗口尺寸更新后要重新测量。
4. 系统 freeform 标题栏已经承担窗口控制，应用右侧栏只放页面级导航/上下文操作，不复制窗口控制。

## Flutter `liquid_glass_widgets` 官方用法

当前 `app/pubspec.yaml` 声明 `liquid_glass_widgets: ^1.17.3`。官方包资料：

- [pub.dev 包页](https://pub.dev/packages/liquid_glass_widgets)
- [GitHub README](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/README.md)
- [LiquidGlassSettings 源码](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/lib/src/engine/liquid_glass_settings.dart)
- [平台支持](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/PLATFORM_SUPPORT.md)
- [Liquid Morph Engine](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/LIQUID_MORPH_ENGINE.md)

### 组件边界

- 官方建议把 `GlassScaffold`、`GlassAppBar`、`GlassTabBar` 作为导航 chrome 的主模式；自定义布局使用 `GlassPage`，局部浮动面板/卡片才使用 `GlassContainer` 或局部 `AdaptiveLiquidGlassLayer`。
- `GlassTabBar.bottom` 是当前底部导航入口，旧的 `GlassBottomBar` 已删除。底栏应由一个组件实例持续持有，路由/键盘/透明度变化不能重建它的状态。
- `GlassMenu` 是从触发按钮形变出来的菜单。菜单必须使用 `triggerBuilder`/`trigger`、`items`、`autoAdjustToScreen` 和合适的 `settings`/`quality`；嵌套菜单使用 `GlassMenuItem(submenu: [...])`，不要在 `onTap` 中再打开第二个 `GlassMenu`。
- 同一区域并排的玻璃应放进一个 `GlassBackdropGroup` 或 `AdaptiveLiquidGlassLayer`，避免每个按钮都复制一次背景读取；不要把整个 Navigator 或长期 offstage 的 tab stack 放进同一个组。
- 官方明确要求避免 glass-in-glass：不要把 `GlassButton`、`GlassIconButton` 或 `GlassChip` 直接嵌入另一个玻璃卡片；需要实体内容卡片时使用 solid surface，再让短暂交互镜片浮在卡片外层。

### 材质、质量和平台

- iOS 27 规范预设是 `LiquidGlassSettings.ios27Light` / `ios27Dark`，应优先使用预设而不是手工拼接 blur、frost、rim、lens 参数。预设设计为 premium；standard/web 是近似路径。
- `GlassQuality.premium` 依赖 Impeller 的 shader pipeline；Skia 下会被限制为 standard。可用 `ui.ImageFilter.isShaderFilterSupported` 判断，不应把 premium 当成所有平台都能得到同样像素结果。
- `GlassQuality.standard` 是默认生产档；`minimal` 适合低端设备、非 shader 路径或大量重复背景卡。材质质量应按平台能力和玻璃区域重要性选择，不能为了“更像玻璃”全屏 premium。
- `LiquidGlassWidgets.initialize()` 应在启动时预热 shader；`LiquidGlassWidgets.wrap()` 负责主题和辅助偏好桥接。`GlassAccessibilityScope` 可测试或强制 `reduceTransparency`，系统辅助偏好应保留最高优先级之外的默认路径。
- 官方文档把 reduce transparency 近似为增加对比度/实体化 fallback；仓库当前 `opaque` 分支应继续用于系统要求降低透明度、shader 不可用或对话框/正文等不应透视的场景。

## Apple Liquid Glass 设计边界

[Apple Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials)把 Liquid Glass 定义为动态材料，用于呈现控件和导航而不遮挡底层内容；standard materials 用于更大面积的背景和内容承载。由此得到的实现边界：

- 玻璃优先用于导航、工具栏、按钮集合、菜单和短暂浮动 chrome；正文、表单、确认弹窗、错误反馈和大面积内容面使用实体 surface。
- 不要叠加多层半透明玻璃。重叠会让采样、对比度和层级不可读；相关内容应合并为一个局部玻璃组，或退回实体面。
- 玻璃应通过背景内容建立层级，不能只用白色半透明填充模拟；阴影、rim、frost 和动态亮度要由库的官方 material settings 统一控制。
- 动效必须可打断且尊重 reduce motion；菜单/按钮的反馈在按下时发生，底栏和工具栏不能在状态切换时随机消失或被重新挂载。

## 需要在代码中复核的项目

- 重新测量右侧栏：compact、medium、expanded、freeform、split、fold/tabletop、Duo reserved region 逐一验证，不能复用手机宽度阈值。
- 将侧栏和正文的布局输入统一为当前 `WindowEnvironment` 的可用区域；窗口模式/Rect/insets/displayFeatures 的任一变化都要让右侧栏重新布局。
- 复核 `GlassMaterial.settings()` 是否应改为官方 iOS 27 预设，并检查当前自定义 `Glass` 是否重复创建采样层、是否存在 glass-in-glass。
- 对所有右侧栏操作集合做真实截图：普通平板、折叠展开、tabletop、Harmony freeform、Harmony split、桌面窄窗口和 Duo；同时测试大字、reduce motion、reduce transparency。
