# 应用实现

修改行为先读[产品规格](../../designs/prod/README.md)，修改视觉先读[设计约束](../../designs/AGENTS.md)。

## 状态与能力

- `stores/` 只承载 Riverpod provider/notifier，维护应用响应式状态、校验与派生，并组合 service。`services/` 承载与视图无关的数据处理、持久化、通信和原生能力；缓存、任务及资源租约跟随实际所有者。
- Widget/Page 持有导航、弹窗、焦点、选择器、渲染与视图租约，负责其生命周期；将路由、应用和窗口的可见性及焦点作为数据传入 store/service。页面局部状态就近维护。
- 同一份状态保持一个来源。按实际复用、独立替换点或资源所有权抽取，直接命名其数据或能力；简单调用就地完成。
- `stores/`、`services/` 保持扁平，以共同业务前缀关联文件。文件名对应主要公开类型；同一能力的接口、执行句柄和回收失败可同文件，辅助实现私有化。公开数据与值校验归 `models/`；`utils/` 只放无业务身份的通用纯函数。

## 页面与视觉

- 页面按路由语义嵌套，入口使用完整语义的 `*_page.dart`；专属控件与交互助手就近放置。页面组合可独立理解的交互与呈现单元，跨页面复用成立后再提升到 `widgets/`。
- 路由沿用 `router/app_router.dart` 的 typed route；导航动作通过 `router/navigation.dart`，资源解析通过 `router/route_resource_resolver.dart`。调整路由同时核对返回、深链及资源失效的行为。
- 非控件视觉定义归 `styles/`；组件消费语义 token。视觉数值唯一维护在 [design.md](../../designs/design.md)，通过[生成器](../../scripts/design_tokens/README.md)更新 `styles/generated/`。
- 修改共享控件时核对设计稿母组件及受影响实例；运行态检查明暗主题、窄容器、大字、安全区和辅助偏好。GPU 效果以实际渲染取证。
