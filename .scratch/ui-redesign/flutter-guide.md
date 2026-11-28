# Flutter 还原手册

目标：让 `app/` 的界面与 Ardot 设计稿（文件 749360133997361）及 `designs/design.md` 一致。不改业务逻辑、状态、路由行为与能力层；只改视觉与布局，以及为此必需的控件接口。

## 先读

- `designs/design.md`：颜色、文字、形状与间距、材质、控件、列表、输入与选择、菜单确认框抽屉、空态加载与进度、页面结构、页面模式、自适应窗口、远控窗口。
- `designs/interaction-motion.md`：时长、曲线、按压与玻璃反馈。
- `app/lib/AGENTS.md`：目录与命名规则。`scripts/check_architecture.dart` 会校验。
- `.scratch/ui-redesign/ardot-guide.md`：Ardot 母组件与画板 ID。用 `mcp__ardot__capture_screenshot`（screenShotDir 用 /tmp/shots）截母组件或画板作视觉参照，用 `mcp__ardot__batch_read` 读精确尺寸、内距、颜色变量。Ardot 变量 `$37:xx` 对应 design.md 的颜色角色（ardot-guide「变量」一节）。
- Prism UI 参考：`/tmp/prism_ref/PRISM_DESIGN_LANGUAGE.md`，源码 `/tmp/prism_ref/prism_ui/lib`（控件尺寸、玻璃、按压与动效的原始实现）。

## 主题入口（app/lib/styles/theme.dart）

- `AppColors.of(context)`：随明暗切换的颜色角色（primary、onPrimary、primaryContainer、onPrimaryContainer、page、card、block、inset、text、textSecondary、separator、outline、disabled、disabledContainer、pressed、scrim、error*、destructive、success*、warning*、glassRegular/Pill/Menu/Fill、dockPlatter、shadow、shadowDock）。
- `AppTypography.of(context)`：13 个文字角色 largeTitle、title1、pageTitle、title3、headline、body、subheadline、label、footnote、caption、captionEmphasis、caption2、tabLabel，已带字族与正文色，用 `.copyWith(color: …)` 换色。
- `DesignTokens`（styles/generated/design_tokens.g.dart，由 design.md 生成，不手改）：明暗相同的颜色（accent*、onMedia、viewport、mediaScrim、callStage…）、`spacing*`、`rounded*`、`component*` 尺寸。`AppIcons`：图标角色。
- `styles/motion.dart`：时长与曲线。

## 迁移规则

- 旧令牌迁移桥已删除；只用 `AppColors`、`AppTypography`、`DesignTokens`。
- 不写硬编码颜色：`Colors.*`、`Color(0x…)`、`Color.fromARGB/RGBO` 会被 `node scripts/design_tokens/generate.mjs --check` 拒绝。透明用 `AppColors.of(context).page.withAlpha(0)` 之类派生值。
- 尺寸优先用 `DesignTokens` 的 spacing/rounded/component 值；design.md 没有对应 token 而又确需的数值，就近定义为具名常量并注明出处（Ardot 母组件或 design.md 段落），不要散落魔数。圆角只用档位 4/8/16/20/24/28/34/全圆。
- 形状用 `RoundedSuperellipseBorder`（连续圆角），胶囊用 `StadiumBorder`。按下不缩小（见 interaction-motion「触点反馈」）。
- 保持公开控件的类名与构造参数，内部重写；确需改接口时同步修改全部调用点，并在报告里列出。新增控件放 `app/lib/widgets/`，按职责命名文件。
- 文案、业务状态、回调与读屏语义保持不变。
- 只改分配给你的文件；需要别人负责的文件配合时，在报告中写明，不要直接改。

## 验证

- `cd app && flutter analyze --no-pub` 对你负责的文件零问题（其他代理同时在改别的文件，只看你的文件）。
- `cd app && flutter test --no-pub test/widgets`（及与你文件相关的测试）。测试里断言旧尺寸/旧颜色的，按新规范更新断言；断言行为的不要放宽。
- `node scripts/design_tokens/generate.mjs --check` 不报你文件里的违规。
- `dart format` 你改过的文件。
- 不提交 git。

## 共用控件（app/lib/widgets，已按新设计重建）

页面只用这些控件拼装，不再自绘同类外观。

- 按钮 `buttons.dart`：`AppButton(label:, onPressed:, role: AppButtonRole.primary|secondary|secondaryOnPage|secondaryOnGlass|destructive|destructiveOnPage|destructiveOnGlass|text|destructiveFilled|glass（媒体/舞台上的 glass-clear 胶囊）, size: AppButtonSize.dock(48)|section(36), icon:, busy:, expand:)`；`AppButton.styleOf(context, role:, size:)` 给仍用 Material 按钮的地方；`SolidIconButton(icon:, tooltip:, onPressed:, compact:, onPage:)` 卡片内圆形图标键。同一屏只有一个 primary。
- 列表 `list_row.dart`：`AppListRow(title:, subtitle:, leading:, value:, trailing:, chevron:, onTap:, destructive:, selected:)`；`grouped_list.dart`：`SettingsGroup(children:)` 自带卡片、圆角 24 和分隔线（页面不要再加 Divider）；按需构建的长列表用 `GroupedListSegment.at(index:, count:, separatorIndent:)`，`ConnectSwitchRow(subtitle:)`；`ActionRow(subtitle:)`、`ChoiceRow`。组头 `SectionTitle(title, action:, first:)`、组脚 `SectionFooter(text)`。
- 功能色块 `ListIconBadge(icon, backgroundColor: FunctionTone.device|connection|file|media|transfer|notification|display|archive|utility)`，图形恒为白色；`FeatureIcon` 同规格，`FeatureIcon.detailSize` 为 56 详情尺寸。应用原图标用 `PhoneAppIcon`，自带按尺寸的圆角裁切。
- 输入与选择：`ConnectSwitch`、`SelectionMark`、`ConnectSegmentedControl(icons:, onPage:, onGlass:)`、`AppChip(label:, selected:, dropdown:)`、`StatusTag(label, tone:)`、`AppSearchField(readOnly:, onTap:)`（只读为打开搜索页的入口）、`AppTextField(label:, errorText:, helperText:, validator:, sensitive:)`、`ChoiceField`。
- 设备：`DeviceBlock(state: DeviceBlockState.connected|offline|connecting|needsAction|failed, tablet:)`、`DeviceIdentity(showcase:)`、`DeviceStatus`。
- 覆盖层：`AppAlertDialog(glass: true)`（动作里 TextButton/OutlinedButton→次要胶囊，FilledButton→主要；危险确认用 `destructiveFilledStyle(context)`）、`showAppDialog`、`showAppModalSheet` + `SheetHeader`/`SheetHandle`、`showChoicePicker`、`confirm` / `confirmConnectionChange`。
- 状态：`PageLoader(message:, detail:, stopped:, action:)` 整页加载（400ms 后出现）、`AsyncContent`、`EmptyContent`、`LoadingSkeleton`/`SkeletonRows`、`ContentLoadingIndicator`、`AppBanner(tone:)` 与 `feedback`/`appSnackBar(tone:)`、`AppProgressBar(value:)`、`StateNote`。
- 页面框架：`PageFrame`（页头 72 高：根页 `pageTitle` 标题 + 右侧玻璃按钮组；子页 44 玻璃返回 + `title3`；设置 `leading` 时为选择模式居中标题），不要再传 `titleStyle` 覆盖；`PageChromeProtection` 顶部渐隐；`NavigationScaffold`（底部导航 / 轨道 / 侧栏）；玻璃：`Glass`/`GlassMaterial(variant: GlassVariant.regular|pill|menu|clear|alert)`、`GlassToolbarIconButton`、`GlassToolbarGroup`、`GlassMenuButton(label:, controller:)`（锚点菜单；带 label 为底栏按钮）、`GlassActionBar`（底栏）、`GlassRim`。

## 命令行注意

后台 shell 里运行 dart/flutter 要加 `< /dev/null`，否则会挂起。
