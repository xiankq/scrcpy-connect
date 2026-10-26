# DESIGN.md → Flutter tokens

`generate.mjs` 使用锁定的官方 `@google/design.md/linter` 解析模型，结合项目扩展 schema 及 Dart emitter；视觉值唯一来自 `designs/design.md`。生成与 lint 共用 `lint.mjs`。

```sh
npm ci --ignore-scripts --prefix scripts/design_tokens
node scripts/design_tokens/generate.mjs
node scripts/design_tokens/generate.mjs --check
npm test --prefix scripts/design_tokens
npm run lint --prefix scripts/design_tokens
```

需要 Node 18+ 与 workspace Dart SDK。修改规范后提交生成输出；`--check` 精确比较且不写文件。支持字段以 emitter 为准，未知键/单位或缺失消费常量会失败。

`px` 映射 Flutter 逻辑像素。官方 0.4.0 解析器忽略数值行高，故无单位行高须写带引号字符串；spacing 同样不用裸数值。字体族仅为设计稿元数据，生成 TextStyle 继承运行平台字体。

项目 schema 为 maxWidth、间距、透明度、形变及玻璃光学扩展校验类型、px 单位和取值范围，仅接受通过校验的已声明扩展。其余官方规则完整保留：未知属性、断引用、对比度及未引用颜色仍报告问题，lint 在存在错误或警告时失败。直接运行上游 `designmd lint` 使用通用 schema，仍会提示项目扩展未知；仓库入口为上述 `npm run lint`。对比度须区分文字、带外部标签的装饰图形与透明叠加层，并检查真实叠加结果。
