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

1. 使用导出 JSON 的 `variables` 调用 Ardot `apply_variables`，使用合并模式以保留变量 ID 和图层绑定。配色和尺寸共用规范里的键。主题选择使用「邻接界面」日间与夜间模式，固定色使用「邻接颜色」。旧变量集合仍有使用方时由同一规范同步。
2. 更换图标时，从导出 JSON 的 `icons` 找到角色和 Lucide SVG。在 G13 的 `图标 / <角色>` 母组件更新矢量层，保留母组件 ID 和 24×24 的图形坐标系。保留日夜前景、媒体亮色、选中或禁用状态的变量绑定。页面和控件引用母组件实例。
3. 使用 Ardot `fetch_variables` 读取完整变量快照，运行 `node scripts/design_tokens/ardot.mjs --check <快照 JSONL>` 检查数值。使用 `batch_read` 核对母组件 ID 与实际绑定，导出一个亮色场景和一个变体检查继承。仓库生成检查在本地运行，Ardot 同步通过已连接的设计工具执行。

`px` 映射 Flutter 逻辑像素。官方 0.4.0 解析器忽略数值行高，故无单位行高须写带引号字符串；spacing 同样不用裸数值。字体族仅为设计稿元数据，生成 TextStyle 继承运行平台字体。

项目 schema 为 maxWidth、间距、透明度、形变及玻璃光学扩展校验类型、px 单位和取值范围，仅接受通过校验的已声明扩展。其余官方规则完整保留：未知属性、断引用、对比度及未引用颜色仍报告问题，lint 在存在错误或警告时失败。直接运行上游 `designmd lint` 使用通用 schema，仍会提示项目扩展未知；仓库入口为上述 `npm run lint`。对比度须区分文字、带外部标签的装饰图形与透明叠加层，并检查真实叠加结果。
