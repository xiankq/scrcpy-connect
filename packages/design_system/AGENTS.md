# 设计系统

[designs/design.md](../../designs/design.md)定义数值和视觉角色；`lib/src/design_tokens.g.dart` 由[官方解析模型与 Dart emitter](../../tool/design_tokens/README.md)生成。修改 token 时更新规范并生成，不能编辑生成文件或在组件内维护同值常量。

本包承载主题、材料与共享控件，不依赖设备连接、会话、传输或路由业务。新增 API 应表达组件用途；设备偏好与协议状态由应用层提供，不加入材料参数。

主题主动作、功能点缀与状态色使用各自的语义 token；调整点缀色不重定义主题。材料按内容与控制层的用途选择，组件复用不意味着所有承载面使用同一种透明材质。

Liquid Glass 的用途、regular/clear 和辅助偏好以视觉规范为准；实际渲染、初始化与后端降级契约见[架构](../../docs/implementation/architecture.md)。Pencil shader、测试后端与生产 GPU 是不同渲染环境，验证结论注明实际环境。

紧凑外观、命中范围和内容尺寸是不同约束。共享控件按父约束容纳文字及动作，辅助偏好变化后保留语义、焦点与可达操作；母组件变化同时核对明暗主题、窄容器及文字放大。
