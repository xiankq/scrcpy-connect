# 设计系统

数值和视觉角色唯一维护于 [designs/design.md](../../designs/design.md)。修改 token 后运行[生成器](../../scripts/design_tokens/README.md)，组件使用语义 token，生成文件不手改。

本包只承载主题、材料与共享控件，业务状态与路由由应用提供。共享组件改动同步母组件及实例，核对明暗主题、窄容器、文字放大和辅助偏好。实时 GPU 与 Ardot 静态稿分别取证。
