# 主控应用边界

- `pages/` 按业务父子关系组织：有子页的入口放 `index/`，叶页直接放自身目录；文件名为完整目录链（含 `index`）加 `_page.dart`。专属组件放本页 `widgets/`，跨页业务组件放最近公共父级的 `widgets/`。
- 路由集中在 `router/app_router.dart`，跨页导航使用生成的 typed route。参数核验、返回、恢复及生成检查遵循[导航契约](../../docs/implementation/flutter-navigation.md)；修改时同步调用处与受影响测试。
- 页面入口和行为以[产品规格](../../designs/prod/README.md)及[交互规则](../../designs/prod/interaction-rules.md)为准，Pencil 状态不直接对应独立路由。
- 页面、会话、播放器和连接的生命周期遵循[架构所有权](../../docs/implementation/architecture.md)。跨设备操作核对当前可见页面与目标设备；未知结果先核对，恢复不自动重放。
- 界面遵循[视觉规范](../../designs/design.md)，使用 `design_system` 生成的语义 token。按组件和内容流还原，并检查窄屏、大字及安全区。
