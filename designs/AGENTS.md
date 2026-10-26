# 产品与视觉设计

产品行为见 [prod/README.md](prod/README.md)；视觉数值与材料用途见 [design.md](design.md)。Flutter token 由[生成工具](../scripts/design_tokens/README.md)生成，Pencil 变量沿用同一数值。

`mobile.pen` 是唯一源稿，使用 Pencil MCP 或 `pen interactive` 对象 API 编辑，不按文本修改。共享组件改母组件，页面实例只覆盖业务内容和明确变体；同步核对受影响实例。

完整页面、规范板与局部状态各用独立顶层 Frame。局部错误、菜单和进度只画变化部分，沿用原状态 ID；Frame 不等于路由。远端画面保持原应用外观。

普通内容使用流式布局，远控、遮罩与浮动操作可叠加。`scroll-viewport` 可裁剪完整滚动内容，末项须可达。核对明暗、辅助偏好、窄屏及长文字；静态稿只能验证布局与材料目标，运行效果需实际截图和交互验证。

修改 `design.md` 后运行 token 生成检查。预览放系统临时目录；仓库仅保留源稿、实际引用素材及[来源许可](assets/README.md)。
