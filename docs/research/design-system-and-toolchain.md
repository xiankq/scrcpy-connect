# 设计系统与 Pencil 工具链依据

本报告说明格式、工具和候选比较的边界。当前视觉角色以 [design.md](../../designs/design.md)为准，实际组件与后端契约见[架构](../implementation/architecture.md)，生成命令和受支持 token 由[工具 README](../../tool/design_tokens/README.md)维护。画布清点、截图版本和光学证据统一见[视觉审计](../implementation/ios-visual-audit.md)，不在研究中缓存另一组页数或组件数。

## DESIGN.md 格式与生成职责

Google DESIGN.md 的机器可读 token 位于 YAML frontmatter，正文解释视觉角色及用途。格式不要求采用 Material 外观，也不直接提供 Flutter 组件或液态玻璃实现。[官方格式](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)

官方工具提供 lint、diff 和部分导出格式。当前锁定工具没有直接 Dart 导出，DTCG 导出也不覆盖本项目使用的全部 component token；项目在官方 `lint().designSystem` 解析模型后提供 Dart emitter，不另行解析 YAML 或手工抄写数值。[官方工具](https://github.com/google-labs-code/design.md)

frontmatter 是视觉值来源，生成的 Dart 常量和 Pencil implementation 变量是不同环境的映射。字段、单位或解析模型升级需按 emitter 契约核对。官方 lint 的扩展属性和未引用颜色警告保留并分类说明；lint 成功不证明画布、实时成像或动态交互通过。

## Liquid Glass 的来源与选型

Apple 将 Liquid Glass 用于内容上方的导航与控制，regular/clear 的用途、内容材料、文字保护和辅助偏好分别处理；具体原则与本项目推论见[官方设计复核](liquid-glass-design-review.md)。主控的黑白主题与亮色功能图标是项目选择，不是 Apple 要求所有应用采用的配色。[Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

以下为研究时点核对的候选；不同发布版或 main 分支的功能不能合并为一个支持承诺。

| 候选与研究版本 | 来源与边界 |
| --- | --- |
| liquid_glass_renderer 0.2.0-dev.4 | 发布文档的 Impeller 与 Windows/Linux/Web 限制不能推广为其他库的限制；main 的不同版本另行核对。[发布说明](https://pub.dev/packages/liquid_glass_renderer)、[源码](https://github.com/whynotmake-it/flutter_liquid_glass) |
| liquid_glass_easy 5.0.0 | 提供独立 lens 与背景采样等接口；本项目实际使用独立 lens，具体初始化和降级见工程契约。[发布说明](https://pub.dev/packages/liquid_glass_easy) |
| liquid_glass_widgets 1.13.0 | 提供控件和不同平台路径，不能将发布页平台列表解释为所有模式效果一致。[发布说明](https://pub.dev/packages/liquid_glass_widgets) |
| fresnel 0.1.0 | shader、模糊与平台限制需按指定版本核对，候选文档不构成本项目运行结果。[发布说明](https://pub.dev/packages/fresnel) |

Flutter/Pencil 的自定义材料不等同于原生 `UIGlassEffect`。支持位、参数和 shader 编译说明所用路径；背景移动时的真实折射、前景可读性、交互反馈及性能分别取得证据。诊断背景仅用于测试，不加入产品装饰。

## Pencil 源稿维护

源稿通过 Pencil 对象 API 维护；MCP 不可用时使用 `pen interactive`。`.pen` 不按文本解析或编辑。页面分类行、母组件和实例职责见[设计工作约束](../../designs/AGENTS.md)。

母组件保存材料、几何和共享子结构；实例覆盖业务内容、显隐及明确变体。复制或替换节点会产生新 ID，后续覆盖使用工具返回的实际 ID；实例移动后核对覆盖是否仍生效。活动分支与禁用插槽分别检查，有意滚动裁剪通过 `scroll-viewport` 标识。

`assets/liquid-glass.glsl` 使用实际 backdrop/SDF 表达静态透镜。Pencil 编译路径与 Flutter shader 是不同实现；当前 Pencil 转译器的纹理采样使用双参数 `texture2D`，不能据 GLSL 语法推定其支持显式 bias。该工具限制属于画稿实现，不扩展为产品材料规则。

文件名和普通内容不因组件可用而包裹玻璃；快捷回复整页与上下文面板的选择依产品流程。普通页头与列表移除解释性副描述，实际状态正文保留；完整文字规则在视觉规范维护。

## 图形与素材

Lucide 图形来源与 Flutter 包装库分别核对许可、名称和覆盖范围，Pencil 与 Dart 使用各自环境中的同一语义图标。[Lucide 许可](https://lucide.dev/license)、[包装库](https://pub.dev/packages/lucide_icons_flutter)

相册示例照片保存来源与用途，见[素材说明](../../designs/assets/README.md)。预览导出放系统临时目录，仓库保留源稿、规范及实际引用的素材。
