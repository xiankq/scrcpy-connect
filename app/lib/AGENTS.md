# 主控应用边界

涉及页面、导航或设备操作时，先读[产品规格](../../designs/prod/README.md)及对应[交互规则](../../designs/prod/interaction-rules.md)；涉及布局和材质时，读取[视觉规范](../../designs/design.md)。实现中的页面不按 Pencil Frame 数量拆分路由。

页面、持久会话、本机播放器和设备连接有不同的生命周期，职责以[架构所有权](../../docs/implementation/architecture.md)为准。路由身份和关闭策略见[导航契约](../../docs/implementation/flutter-navigation.md)。

涉及声音、剪贴板或跨设备操作时，按[交互规则](../../designs/prod/interaction-rules.md)分别核对页面可见性、当前设备、设备偏好和已提交操作的目标。已提交动作的结果未知时先核对，路由重建、恢复连接及后台事件不触发自动重放。

视觉数值使用 `design_system` 生成的语义 token；共享材料与控件在 `packages/design_system` 维护，页面选择语义变体并承载业务状态。产品界面使用用户能据以操作的信息，渲染后端、协议或调试状态留在诊断与测试中。

还原稿件时映射组件语义、对齐关系和内容流，不将 Frame 坐标或整屏缩放作为页面布局。紧凑密度与操作命中范围分别核对；窄父容器、文字放大、键盘及安全区域变化后，内容和主要动作仍须可达。普通页面过渡与远控返回映射分别按产品规则验收。
