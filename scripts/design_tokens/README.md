# 设计 token 生成与同步

- 输入：视觉数值来自 [design.md](../../designs/design.md) 的 front matter；共享图标角色来自 [icons.json](../../designs/icons.json)。
- 输出：Flutter 的 `DesignTokens` 和 `AppIcons`（`app/lib/styles/generated/`），以及给 Ardot 用的变量 JSON。
- `generate.mjs` 和 `lint.mjs` 共用同一套校验：锁定版本的官方 `@google/design.md` linter（0.4.0）加本项目的扩展 schema。

需要 Node 18.17 及以上和仓库 workspace 的 Dart SDK。

```sh
npm ci --ignore-scripts --prefix scripts/design_tokens
# 重新生成 Flutter 代码
node scripts/design_tokens/generate.mjs
# 检查：生成文件是否过期、应用视觉代码里有没有硬编码颜色、有没有可直接识别的共享操作图标没走 AppIcons
node scripts/design_tokens/generate.mjs --check
# 检查 design.md 本身
npm run lint --prefix scripts/design_tokens
# 导出 Ardot 变量和图标
node scripts/design_tokens/ardot.mjs > /tmp/interconnect-ardot-design-system.json
```

改了 design.md 或 icons.json 后，把生成的文件一起提交。

## 写 design.md 时的规则

- 支持哪些字段以 `generate.mjs` 的输出逻辑为准。出现未知键、未知单位，或缺少应用代码必需的 token（报 `Missing required DESIGN.md token`）时，命令失败。
- `px` 对应 Flutter 的逻辑像素。
- 无单位的行高写成带引号的字符串（如 `"1.4"`），因为官方 0.4.0 解析器会忽略数字形式的行高。spacing 同样不要写裸数字。
- 字体族只是设计稿元数据。生成的 TextStyle 使用运行平台的系统字体。
- 颜色名 `<角色>-dark` 是该角色的夜间值。只要基础角色被组件引用，夜间值就不算"未引用颜色"。

## lint 检查什么

- 项目扩展 schema 检查 maxWidth、间距、透明度、形变和玻璃光学参数的类型、`px` 单位和取值范围。只接受已声明且通过校验的扩展字段。
- 官方规则全部保留：未知属性、断开的引用、对比度不足、未引用的颜色都会报出。有任何错误或警告时 lint 失败。
- 只用 `npm run lint --prefix scripts/design_tokens`。直接运行上游的 `designmd lint` 用的是通用 schema，会把项目扩展字段报为未知。
- 检查对比度时分清三种情况：文字、旁边有文字标签的装饰图形、透明叠加层。叠加层要按实际叠加后的颜色检查。
- 唯一的放宽：`primary` 底上的 `on-primary` 按大字标准 3:1 检查，因为规范只在它上面放 15 点以上、600 字重的标签和图形。

## 更新 Ardot

1. 用导出 JSON 里的 `variables` 调用 Ardot `apply_variables`，选合并模式，保留已有变量 ID 和绑定。共三个变量集合：
   - 「邻接 · 主题」：日间、夜间两个模式，收录有 `-dark` 夜间值的颜色。
   - 「邻接 · 固定色」：明暗相同的颜色。
   - 「邻接 · 尺寸」：只收间距、圆角、字号和行高。组件尺寸由母组件决定，不做成变量。
2. 换图标时，从导出 JSON 的 `icons` 取 Lucide SVG，把各子路径合并成一条路径，替换「规范与组件」页图标库里 `图标 / <Lucide 名>` 的矢量。矢量名保持「图形」，描边绑定 `text` 变量。名称不变，实例里覆盖过的图标颜色才会保留。
3. 核对：用 `fetch_variables` 读取变量快照，运行 `node scripts/design_tokens/ardot.mjs --check <快照 JSONL>` 比对数值；再用 `batch_read` 抽查母组件的变量绑定，并各截一张浅色、深色画板，确认颜色正确继承。
