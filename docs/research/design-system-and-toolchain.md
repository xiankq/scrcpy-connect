# 设计系统、液态玻璃与 Pencil 工具链调研

调研日期：2026-10-16，补核2026-10-17（Asia/Shanghai）。以下保留各轮修订记录；当前材质实施以本节后的固定版本决策为准，早期候选表不表示当前实现状态。

## 2026-10-17固定版本实施：共享实时折射

选用 `liquid_glass_easy: 5.0.0`，封装于 `packages/design_system` 的既有 `Glass`，不在各页面扩散库API。它只有Flutter/Dart依赖及shader资源，无新原生业务层；standalone lens使用engine提供的背景shader采样，不启用`LiquidGlassView`和自适应截图。当前颜色、光学参数及局部文字保护来自`designs/design.md`和Pencil implementation tokens。[固定发布版](https://pub.dev/packages/liquid_glass_easy/versions/5.0.0)、[发布归档](https://pub.dev/api/archives/liquid_glass_easy-5.0.0.tar.gz)

需要纠正旧平台推断：本机Flutter3.47.6；官方3.47文档明确macOS/Linux/Windows已默认启用Impeller，因此不能以“Windows必定Skia”硬编码关闭折射。实现以`ImageFilter.isShaderFilterSupported`检测后端；该检测仅表示API能力，不保证任意GPU已成功绘制。Android/iOS/macOS/Windows共用Dart/shader依赖路径，四宿主整包仍须分别验收。[官方Impeller平台说明](https://docs.flutter.dev/perf/impeller#availability)

固定归档源码核对：`render_liquid_glass_lens.dart`的layer在`addToScene`同步当前变换、调用`pushBackdropFilter`，避免滚动仅移动retained layer时采样坐标陈旧；背景先模糊再折射，`liquid_glass.frag`处理GLES采样Y方向。Windows/Linux有单独desktop shader。`LiquidGlassView`的自适应颜色路径存在`toImage/toByteData`，本项目不进入。对比的widgets1.13.0部分控件会逐帧`toImageSync`，fresnel0.1.0引入SwiftUI平台视图及26SDK符号，这两条路径未采用。

普通列表仍是内容层；玻璃只承载悬浮导航、退出和工具/上下文控制。降低透明度、highContrast与显式solid完全绕过滤镜与折射；不支持的后端保留模糊材质。当前没有为所有控件新增touch/motion或自动形变，因此尚不能宣称可打断液态形变已交付。shader尚未加载或资源加载失败时，固定版本库保留相同child的磨砂fallback；GPU pipeline创建失败不自动向Dart回报，仍需实机日志与画面验证。

fvp当前使用Flutter Texture而非PlatformView，engine会将外部纹理绘制到canvas，具备被后方控制层采样的源码路径。这是可实施性依据，实际动态视频、旋转、前后台、GPU预算和硬件兼容的结论须看[运行验收](../implementation/validation.md)，不能仅以源码判通过。含lens的滚动内容还需避免Android stretch overscroll将背景隔离；目前远控退出与主导航位于滚动内容外。

本次规范lint为0errors/31warnings：10项玻璃扩展属性（原5项加5项折射参数）不在官方标准组件子token集合，21项颜色未在标准components引用。扩展属性及Pencil实际引用保留，不隐藏警告；0errors不表示像素和动态性能通过。

## 已确认的事实

### Google DESIGN.md 是规范载体

Google 的 DESIGN.md 格式以可选 YAML frontmatter 记录机器可读 token，以 Markdown 记录设计理由。正文有规定的章节顺序；token 是规范值，正文解释如何使用。它不直接提供 Flutter 组件或液态玻璃实现，也不要求采用 Material 视觉。[官方格式](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)

官方 CLI 支持 lint、diff、导出 Tailwind 与设计 token 格式。现有导出不应被当成已提供 Flutter ThemeExtension 或 Pencil 变量生成器；本项目需要定义自己的映射，并保持 designs/AGENTS.md 所要求的单一视觉值来源。[官方工具说明](https://github.com/google-labs-code/design.md)

从仓库根目录运行以下命令校验现有规范；固定版本便于复现，`designmd` 别名也适用于 Windows：

```sh
npx --yes --package=@google/design.md@0.4.0 designmd lint designs/design.md
```

本轮重设计后已实际运行，结果为 0 个错误、26 个警告。其中 5 项是玻璃效果的扩展属性（边缘色、模糊、阴影与方向），21 项是未被规范 `components` 映射引用的颜色，涉及深色主题、状态和材质等。后者不读取 Pencil 的实际引用，警告保留。CLI 发现错误返回退出码 1；它不能替代画布、动态材质和无障碍运行验证。

### 苹果的液态玻璃主要服务导航与控制层

Apple 的材料指南将液态玻璃放在导航和控制层，内容层使用其他材料；提供 regular/clear 两种变体，并考虑减少透明度和提高对比度等设置。这与用户已确认的玻璃使用位置一致。[Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

### 液态玻璃候选库的跨平台限制不能忽略

本次查询到 pub.dev 的 liquid_glass_renderer 为 0.2.0-dev.4；其发布文档明确列出 Impeller 要求，Windows/Linux/Web 不受该版本完整实现支持，并记录纹理内存与图形数量限制。它不能直接作为满足四端支持要求的唯一必选实现。[发布版说明](https://pub.dev/packages/liquid_glass_renderer)

与此同时，上游 main 分支已是不同的 1.0.0-dev.1 实现，要求 Flutter 3.47 和 Flutter GPU，正文说明 iOS/Android/macOS 是测试平台，另有 FakeGlass 回退。发布版文档、main 源码与 Context7 摘要存在代际差异，后续必须按选定版本重新核实，不能将各版本优点混合为一个已支持的实现。[源码版本与依赖](https://github.com/whynotmake-it/flutter_liquid_glass/blob/main/packages/liquid_glass_renderer/pubspec.yaml)、[main 分支说明](https://github.com/whynotmake-it/flutter_liquid_glass/blob/main/packages/liquid_glass_renderer/README.md)

### Lucide 图形来源与 Flutter 包装库分开选择

Lucide 官方许可与某个 Flutter 包装库的许可、维护和图标覆盖不是同一件事。lucide_icons_flutter 在 pub.dev 声明 MIT、仅依赖 Flutter；可作为包装候选，但最终需锁定版本、图标名称映射及所需署名。Pencil 图标名和应用图标名仍需建立可核查映射。[Lucide 许可](https://lucide.dev/license)、[Flutter 包信息](https://pub.dev/packages/lucide_icons_flutter)

### 其他液态玻璃库确有跨 Windows 的实现路径

用户指出候选比较不足后，补查如下。平台栏是发布者提供的文档依据，不代表本项目完成跨端验证；Android 是当前运行验证重点，Q32 进一步要求四端实际可编译，不能仅凭文档将这一要求标为通过。

| 候选与研究版本 | 四端支持依据 | 关键差异 |
| --- | --- | --- |
| liquid_glass_easy 5.0.0 | 发布页列 Android、iOS、macOS、Windows | Impeller 采样实时背景；Skia 通过 LiquidGlassView 提供捕获背景，也能做折射，不是只能关闭折射。动态视频背景的采样成本仍需 Android 媒体联调 |
| liquid_glass_widgets 1.13.0 | 发布页列四端，仓库有平台说明和不同渲染路径 | 更完整的控件集合；Windows 的 premium 会限制到 standard。平台说明部分版本标记较旧，发布页宣称不能当成已验证效果完全相同 |
| fresnel 0.1.0 | 文档列 Android/macOS/Windows shader 与 iOS 原生路径 | iOS 26+ 使用原生玻璃，其他端主要 shader；较早期，需核实真实背景采样和现有 Flutter 版本适配 |

来源：[liquid_glass_easy 5.0.0 发布说明](https://pub.dev/packages/liquid_glass_easy/versions/5.0.0)、[liquid_glass_widgets 1.13.0](https://pub.dev/packages/liquid_glass_widgets/versions/1.13.0)、[widgets 平台细则](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/PLATFORM_SUPPORT.md)、[fresnel](https://pub.dev/packages/fresnel)。

因此，liquid_glass_renderer 的限制不能推广为“Flutter 没有跨四端液态玻璃方案”。目前优先进一步评估 liquid_glass_easy 的设计自由度与 Skia 折射路径，以 liquid_glass_widgets 作为控件集合对照；这仍是研究建议，不是已确认的依赖选择。

### 厂商互联的操作主线

小米妙享桌面的官方说明围绕从设备入口打开手机、操作手机应用、查看传输文件，以及把应用窗口接入主控设备的多任务流程。三星 Flow 的 Smart View 说明则把控制、旋转、全屏、息屏、截图和常用应用集中在协同窗口。它们可作为本项目的交互依据，但文档没有完整列出所有手势细节，不能据此宣称某个本地缩放或辅助操作永远不存在。[小米妙享桌面](https://os.mi.com/continuity/abilities/ab0009)、[Samsung Flow 官方操作说明](https://www.samsung.com/uk/support/mobile-devices/what-is-samsung-flow-and-how-do-i-use-it/)

用户已明确不引入“查看模式”。本产品按设备、应用、文件、通知等互联任务组织，控制画面直接交互；不能把低层坐标适配问题转化成用户必须学习的一组查看器模式。边缘返回、本机键盘和远端输入仍需按具体互联操作继续验证。

### Pencil 无头工具与后续设计交付

本机 Pencil MCP 调用返回无法连接运行中 App，按目录规则使用 pen interactive 0.3.12 的无头路径。本轮只通过对象模型、变量和组件重绘并保存 `designs/mobile.pen`，未将 .pen 当成文本读取或修改。该次重绘记录为37个手机页面、2个大屏页面与共享组件板；移除旧的回写、备份、相机、录屏和编辑版本冲突页面，新增相册多选、来电音频可用与降低透明度示例。

依据用户最新的排列要求，同一文件内每页保留独立顶层 Frame，九类页面各占一行，行前标注类别和用途，同类正常与异常状态相邻。类别为设备与工作台、连接与授权、手机与应用、文件与传输、相册与内容、通知与接续、来电与通话、偏好与恢复、平板与桌面。不再使用全局编号顺序铺排，也没有拆分成多个 .pen 文件。此前关于独立工作区 API 的调查记录不再作为本次分类排列未完成的理由。

视觉基于 [Apple HIG 与 WWDC25/26](apple-liquid-glass-redesign.md) 重新梳理：默认浅色，黑色主动作和选中态，深色仅为可选外观；媒体保留原色。普通内容与玻璃控制层分开，导航、工具和 sheet 呈现透色、方向亮边与柔和阴影。移动端手机控制页保持源画面比例并沉浸全屏，移除主控页头与外置工具栏；退出使用可拖拽、左右吸附收起的悬浮按钮。该最新纠正替代此前把远控作为页内画面呈现的方案。页面职责与用户流程见[产品设计](../../designs/prod/README.md)。静态材质不代表 Flutter 动态折射、视频采样和目标设备性能已验证。

已逐批检查代表页面截图并复核最终分组总览。该次对象模型检查为39个页面、9 个分组标题、1 个组件板，共 49 个顶层对象；90 个组件实例、144 个 implementation token。顶层对象无重叠，展开组件后的边界扫描无溢出，变量引用均来自本轮规范，已移除功能的文案扫描无命中。默认浅色、媒体控件可读性和远控／本机工具边界均通过静态视觉复核。

保存后已关闭并重新打开源文件复查：3 个组件定义、90 个实例均无断开的引用，没有缺失变量或边界溢出，默认首页仍为浅色。预览输出使用系统临时目录，临时总览对象在导出后即删除，Git 不保留导出目录；画布实际引用的照片仍保留在 designs/assets。上述检查只针对静态设计，不替代动态效果与设备运行验收。

CLI 对宽高直接使用变量引用时会错误归一为自适应尺寸；当前宽高由规范对应 token 解析后写入数值，其余颜色、间距、字体、圆角与材质使用 implementation token。解析值不构成另一套视觉规范。

## 工程推论

- 统一视觉规范与共享组件接口不必等于所有平台强制使用同一图形实现。Q35 后常规功能与实现取舍由代理依据研究负责；上述玻璃库仍需编译及媒体联调，尚未选定，不能提前认定必须降低视觉目标。
- 设计 token 的维护、Pencil implementation token 和 Flutter 主题映射应有明确生成或校验路径；仅手工复制数值会产生多个事实来源。
- 多路实时视频与动态折射共同占用 GPU。用户已确定低延迟优先，因此需要在真实控制页面测量效果，而不是仅运行静态玻璃演示。
- 更换材质等级时应保持可点击区域、语义、导航和操作反馈；不能将某种高级 shader 的可用性当成整个功能可用性的前提。

## 尚需验证

1. 视频 Texture 是否可被选定玻璃实现正确采样，旋转、尺寸变化和多个视频层是否引发额外复制或黑屏。
2. 中低端 Android 设备上玻璃、转场、多路视频同时运行的 GPU 时间、内存、耗电和热降频。
3. Windows 的完整折射路径，或满足设计目标的独立基础材质实现；当前不要求跨端实测，但要有文档/实现依据。
4. Pencil 的 implementation token 与 Google DESIGN.md token 如何映射至 Flutter，主题变体和效果等级如何表达。
5. Iconify 后备图标的风格、许可与包体影响；只在 Lucide 确无合适图标时采用。
6. 字体放大、TalkBack、横屏、分屏、降低透明度、减少动态效果及高对比度在真实页面中的表现。

## 访谈反馈

- Q19 未决定：用户要求先比较其他库。单一候选的 Windows 限制不是要求用户接受视觉降级的充分依据。
- Q20 否决查看模式：用户要求以成熟互联产品作为交互参照；触控板未确认。
- Q21 已确认：文件同名冲突默认询问，可将选择应用于当前任务后续冲突。

## 本轮需求审计后的设计状态

上述静态结构检查仍成立，但36个代表页面不等于完整流程已经覆盖。视频播放、文件管理/失败恢复、详细画质、通知认证与失效、中文输入以及多设备对象仍欠具体状态，见[覆盖表](../../designs/prod/coverage.md)。后续执行[设计任务18](../../.scratch/interop/issues/18-complete-design-state-coverage.md)与[动态玻璃/性能任务16](../../.scratch/interop/issues/16-glass-and-performance-budget.md)，不能把缺口藏在‘已完成36页’之后。

## 彩色细节与玻璃层次修订

用户最新反馈指出画面过于朴素，允许图标和小元素使用非中性色，并否定深绿色按钮。本轮保留默认浅色和黑色主动作，为消息、相册、文件等入口加入紫罗兰、珊瑚、琥珀等功能色；设备面板、导航、搜索和操作浮层加强背景透色、方向亮边与层次。接听改为浅薄荷玻璃与深色文字，拒接改为浅珊瑚玻璃，避免大面积红色压过接听。主按钮减弱内部斜向反光，避免厚塑料或金属斜面。

彩色图标的前景与正文标签分开映射：正文仍使用中性文字；玻璃选中层按实际背景合成后的对比判断，不把透明颜色当成独立实色页面。深色设备面板增加底色保护，降低透明度页移除控制层的半透明、反光与模糊。代表截图已经复核，展开组件检查结果为：36页、9组、3个共享组件、90个实例、139个token；无断开组件引用、缺失变量、边界溢出、顶层重叠或深绿色实心操作按钮。官方lint为0错误26警告，无对比度警告；警告分类见上文。

源文件通过Pencil CLI对象模型保存，导出总览位于系统临时目录，临时拼版对象导出后删除。此轮完成静态视觉修订，任务16保留动态折射/性能验证，任务18保留缺失流程状态补画，均未因本轮配色完成而关闭。

## 移动端全屏远控修订

用户要求远控体验像直接使用被控手机。整机`DtZbX`、通知接续`Q2B7mM`和移动端独立应用`aVxBi`已经移除主控标题、工具栏及缩小的手机画面，源画面覆盖整个页面；仅悬浮玻璃退出按钮叠加在远端之上。新增拖拽`D5Cjet`、右侧收起`D3HWzx`和左侧收起`P8F1YG`，均在手机与应用同一分类行中相邻排列。

默认展开按钮点击退出、按住拖动；释放吸附最近左右边缘并收起，拖拽释放不执行退出。收起保留侧边把手与独立可访问热区，点击展开后再退出。退出回设备工作台，其他连接活动继续。不同纵横比保持源画面完整，手机原有状态栏/手势属于远端内容；本机系统栏沉浸处理和触摸隔离列入任务08，不把设计示意当成运行通过。

此次对象检查为39页、9组、1组件板，49个顶层对象、90个实例、144个implementation token；无缺失变量、断开组件、边界溢出或顶层重叠。三个远控入口均为整页源画面加悬浮退出两个顶层内容元素。官方DESIGN.md lint保持0错误26警告，分类沿用上文。源文件使用CLI对象模型保存，预览位于系统临时目录，临时拼版随导出删除。

## 全屏遗漏状态修复与复核

用户指出zLQT5仍有内嵌屏幕；前一轮只改三个正常入口，遗漏了共用旧页面底层的重连、画质声音和资源不足状态。此次逐项扫描全部手机画面的对象层级，修复zLQT5、FkCjb、HjBtR为全屏源画面/最后一帧＋上下文面板，退出按钮置于面板之外；重连明确标记暂停且禁止向远端输入。nqQEb与iEvoR原横向裁切预览改为设备/会话状态卡。

九个移动远控状态（DtZbX、Q2B7mM、aVxBi、D5Cjet、D3HWzx、P8F1YG、zLQT5、FkCjb、HjBtR）均核对到与页面同尺寸的源画面，相关截图已检查。旧手机实时画面/远端手机壁纸/保持手机比例的画面区域/手机原应用画面容器在手机页面扫描中为零残留；设备入口不再显示旧横向裁切画面。总数保持39页、49个顶层对象、90实例、144token；缺失变量、断开组件、边界问题与顶层重叠均为零。DESIGN.md官方lint保持0错误26警告，分类见前文。设计源文件通过Pencil CLI保存，预览在系统临时目录，动态交互仍需实际实现验证。

## Pencil组件复用与联动验证

用户要求善用组件。原先仅三个母组件，重复远控底层仍是独立节点，本轮改为17个母组件、167个连接实例，集中于同一设计系统画布；39个页面、九类分行及页面ID保持。页面不再复制远控画面树，九个远控状态均只承载一个全屏会话实例。

| 组件组 | 母组件ID | 用法 |
| --- | --- | --- |
| 移动端全屏会话 | `JvYLh` | 九个页面共用；来源、退出、遮罩、提示与面板按显隐和位置覆盖 |
| 远端示意画面 | `VdYO7`、`pidBm` | 桌面与原应用内容源；分别用于七个和两个远控状态 |
| 悬浮退出 | `c2RYVn`、`Z0fV6l` | 展开按钮及侧边收起；左右位置与边角作为状态差异 |
| 玻璃面板外壳 | `yLJek` | 重连、画质声音、资源不足、文件冲突、快捷回复共用 |
| 面板内容 | `Gpn4e`、`h7lWL`、`GCclV`、`gg40W`、`LnT4V` | 五种内容组件，外壳的内容区通过显隐启用对应实例 |
| 系统外观 | `nvopW`、`HeXc3` | 状态栏、手势指示，各28个页面实例；远端系统外观留在源画面组件中 |
| 主/次动作 | `QXIw5`、`anf55` | 清理20个主按钮和17个次按钮实例的重复材质覆盖；降低透明度保留明确实色变体 |
| 内容行与导航 | `OuAnF`、`Ffm0s` | 保留并继续使用已有连接组件 |

复用验证实际修改母组件后读取展开实例，随后恢复原值：桌面时间修改传递至7个远控状态，退出图标色传递至7个展开状态，面板边框传递至5个活动面板，系统时间传递至28个页面。显隐、左右吸附和原应用分支保持；不是仅统计reusable标记或复制节点数量。

本机CLI在替换嵌套实例子节点后继续按原路径写覆盖曾出现状态错配；本次改用稳定子节点ID、连接实例和一次性显隐覆盖，并重新验证母组件联动。后续不要把复制后失效的子节点ID继续作为覆盖路径。视觉值仍沿用design.md与implementation token，未另建样式来源。

边界检查按活动分支执行，禁用的内容变体不参与布局验收；活动内容无溢出，组件引用无断开，变量无缺失，顶层无重叠。降低透明度与深色、照片控件、左右收起及面板截图均复核。官方DESIGN.md lint保持0错误26警告，分类见上文。导出只在临时目录；此次是设计组件整理，不表示动态交互或应用工程已实现。

保存并关闭CLI后已重新打开源文件：17个母组件、167个实例和49个顶层对象保持，九页仍各自连接JvYLh全屏会话；五个面板各仅启用一份正确内容，重连的暂停标记及退出位置保留。重新展开检查没有断开引用或活动边界问题，重连与左侧收起截图再次复核。

## 设备列表、连接表单与流程补齐（2026-10-16）

最新静态交付替代上文39页计数：源文件当前为77页（75手机、2大屏）、12个分类标题、1个组件板，共90个顶层对象；23个母组件、470个连接实例、148个implementation变量。新增38页，重构原设备首页、添加/连接、授权及工作台；设备不再设置主力/备用角色。

产品缺口分析和页面转换见[设备与连接](../../designs/prod/device-connection.md)、[完整页面目录](../../designs/prod/user-flows.md)与[32条覆盖账本](../../designs/prod/coverage.md)。本轮除了设备列表状态和真实表单，还补文件目录/重命名/删除/部分结果、视频/格式回退、通知失效/未知回复、画质选项、设备音源/剪贴板、后台活动、多设备来电及外观。剩余稿与运行验证仍公开保留，不用77页数量冒称完整产品已实现。

新增母组件为圆形图标操作（lufWX）、页面导航标题（wbM5x）、连接字段（Nrkcq）、平等设备卡（RTx0Z）、状态反馈（x5m8En）和功能入口（cX2Ni）。已临时修改母组件样式后读取展开实例并恢复：设备卡图标联动3个首页设备，连接字段底色联动3个配对输入，页面标题样式联动首页；原九个全屏页面继续各自连接JvYLh，底层没有退回内嵌画面。

通过Pencil CLI对象模型保存并关闭，随后重新打开源文件核对：上述页面/组件/实例/变量计数保持；缺失变量、断开引用、活动分支边界问题、顶层重叠和“备用手机”产品文案均为0。重新导出的首页和配对表单已目视检查，组件试验样式已恢复；四组临时拼版及工作台、目录、传输详情、视频、画质细项等代表截图完成复核。临时拼版导出后删除，导出均在系统临时目录。

官方DESIGN.md 0.4.0 lint再次执行为0错误、26警告：5项玻璃扩展属性、21项规范components没有引用的颜色；它们在Pencil的实际引用由对象扫描另行核验，无缺失变量。本轮新增字段、设备卡等规范token先写入design.md，再更新implementation变量。Markdown本地文件链接检查无缺失，需求追溯为54个唯一条目；Git空白检查通过。上述均为静态交付检查，不表示连接、二维码协议、Android输入、通知/通话能力或四端构建已经通过。
