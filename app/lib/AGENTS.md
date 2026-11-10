# 主控应用

- 页面布局、命名、typed route与焦点按[导航](../../docs/implementation/flutter-navigation.md)；用户行为按[产品规格](../../designs/prod/README.md)。
- 业务归对应连接、文件、媒体模块，资源按[架构](../../docs/implementation/architecture.md)持有；页面不成为业务依赖。
- 主题与非控件视觉定义归 `styles/`，跨页面共享控件归 `widgets/`，页面专用控件留在对应页面的 `widgets/`；控件配套的几何、反馈等实现就近维护。
- 数值和视觉角色唯一维护于[视觉规范](../../designs/design.md)，通过[生成器](../../scripts/design_tokens/README.md)输出到 `styles/generated/`；组件使用语义 token，生成文件不手改。
- 共享控件改动同步设计稿母组件及实例，核对明暗主题、窄容器、大字、安全区和辅助偏好。实时 GPU 与 Ardot 静态稿分别取证。
