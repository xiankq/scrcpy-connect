# DESIGN.md → Flutter tokens

`generate.mjs` 使用锁定的官方 `@google/design.md/linter` 解析模型，仅补充 Dart emitter；视觉值唯一来自 `designs/design.md`。

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
node tool/design_tokens/generate.mjs
node tool/design_tokens/generate.mjs --check
npm test --prefix tool/design_tokens
npm run lint --prefix tool/design_tokens
```

需要 Node 18+ 与 workspace Dart SDK。修改规范后提交生成输出；`--check` 精确比较且不写文件。支持字段以 emitter 为准，未知键/单位或缺失消费常量会失败。

`px` 映射 Flutter 逻辑像素。官方 0.4.0 解析器忽略数值行高，故无单位行高须写带引号字符串；spacing 同样不用裸数值。字体族仅为设计稿元数据，生成 TextStyle 继承运行平台字体。官方 lint 对项目扩展和未引用颜色的警告保留可见。
