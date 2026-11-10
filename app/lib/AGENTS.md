# 主控应用

- 页面布局、命名、typed route与焦点按[导航](../../docs/implementation/flutter-navigation.md)；用户行为按[产品规格](../../designs/prod/README.md)。
- provider 与 service 只保存数据、执行数据操作；弹窗、导航、焦点、页面可见性及视图租约由 widget 或页面 hook 持有和释放。业务实现通过数据与结果交互，不依赖页面。
- 按实际复用和生命周期决定抽取；同一份状态只有一个来源，纯转发层直接删除，目录保持扁平。
- 主题与非控件视觉定义归 `styles/`，跨页面共享控件归 `widgets/`，页面专用控件留在对应页面的 `widgets/`；控件配套的几何、反馈等实现就近维护。
- 数值和视觉角色唯一维护于[视觉规范](../../designs/design.md)，通过[生成器](../../scripts/design_tokens/README.md)输出到 `styles/generated/`；组件使用语义 token，生成文件不手改。
- 共享控件改动同步设计稿母组件及实例，核对明暗主题、窄容器、大字、安全区和辅助偏好。实时 GPU 与 Ardot 静态稿分别取证。
