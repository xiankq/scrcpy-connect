# 设计系统生成与同步

视觉值来自 [design.md](../../designs/design.md)，共享图标角色来自 [icons.json](../../designs/icons.json)。`generate.mjs` 使用锁定的官方 `@google/design.md/linter` 和项目扩展 schema，生成 Flutter 的 `DesignTokens` 与 `AppIcons`。生成与 lint 共用 `lint.mjs`。

```sh
npm ci --ignore-scripts --prefix scripts/design_tokens
node scripts/design_tokens/generate.mjs
node scripts/design_tokens/generate.mjs --check
npm run lint --prefix scripts/design_tokens
node scripts/design_tokens/ardot.mjs > /tmp/interconnect-ardot-design-system.json
```

需要 Node 18.17 及以上与 workspace Dart SDK。修改规范后提交生成输出。`--check` 检查生成漂移、应用视觉代码中的硬编码颜色和可直接识别的共享操作图标。支持字段以 emitter 为准，未知键、未知单位或缺失消费常量会失败。

## 更新 Ardot

1. 用导出 JSON 的 `variables` 调用 Ardot `apply_variables`（合并模式，保留变量 ID 与绑定）。三个集合：「邻接 · 主题」有日间、夜间两个模式，收录带 `-dark` 夜间值的颜色；「邻接 · 固定色」收录明暗相同的颜色；「邻接 · 尺寸」只收间距、圆角、字号和行高。组件几何由母组件承载，不进变量。
2. 更换图标时，从导出 JSON 的 `icons` 取 Lucide SVG，把各子路径合并为单条路径后更新「规范与组件」页图标库中 `图标 / <Lucide 名>` 的矢量，矢量名保持「图形」、描边绑定 `text`。保持名称一致，实例替换图标时颜色覆盖才会保留。
3. 用 `fetch_variables` 读取变量快照，运行 `node scripts/design_tokens/ardot.mjs --check <快照 JSONL>` 核对数值；再用 `batch_read` 抽查母组件绑定，并截一张浅色、一张深色画板确认继承。

`px` 映射 Flutter 逻辑像素。官方 0.4.0 解析器忽略数值行高，故无单位行高须写带引号字符串；spacing 同样不用裸数值。字体族仅为设计稿元数据，生成 TextStyle 继承运行平台字体。

项目 schema 为 maxWidth、间距、透明度、形变及玻璃光学扩展校验类型、px 单位和取值范围，仅接受通过校验的已声明扩展。其余官方规则完整保留：未知属性、断引用、对比度及未引用颜色仍报告问题；`<角色>-dark` 视为同一角色的夜间值，基础角色被组件引用即可，lint 在存在错误或警告时失败。直接运行上游 `designmd lint` 使用通用 schema，仍会提示项目扩展未知；仓库入口为上述 `npm run lint`。对比度须区分文字、带外部标签的装饰图形与透明叠加层，并检查真实叠加结果。
