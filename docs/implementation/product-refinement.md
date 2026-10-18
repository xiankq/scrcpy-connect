# 产品与实现收敛（2026-10-18–19）

本轮按用户的十一项反馈调整产品规则、同一份 Pencil 源稿和 Flutter/Rust 实现。视觉值来自 [design.md](../../designs/design.md)，流程来自 [交互规则](../../designs/prod/interaction-rules.md)。既有 ADR 的主控免调试、真实应用任务与连接授权约束继续有效。

| 反馈 | 原问题与决定 | 实现与验证位置 |
| --- | --- | --- |
| 1 默认 iOS 返回 | 使用框架的 Cupertino 转场，各普通页面不维护自己的返回动画或手势 | design_system 的 PageTransitionsTheme；导航测试 |
| 2 移除易用性设置 | 外观只选择浅色、深色、跟随系统。文字缩放、减少动态和高对比读取系统信号 | AppearancePage、ConnectApp；设备偏好与响应式测试 |
| 3 声音随打开页面 | 设备连接、后台保留会话、实际打开控制页面是三个不同状态。只有最后一种持有播放意图；同时打开设备合并播放，同设备去重 | AppController 页面租约、RemotePage、native audio；audio_test |
| 4 设备内剪贴板开关 | 删除全局开关、固定对象、手动发送/获取设置页和冲突选择。当前设备开启同步时，进入和切换立即以设备内容覆盖主控；后续复制自动同步 | DeviceDetailsPage、ClipboardCoordinator、native preferences；clipboard_test |
| 5 字体按钮紧凑 | 收紧语义文字级别、按钮、列表行、内容边距和导航。触控区域至少44，不以整体缩放达到紧凑 | design_system 与 Pencil implementation tokens；截图和大字测试 |
| 6 玻璃与紫色 | 删除紫色装饰与灰色金属反光，显式定义中性色，内容改普通面。浮动控制共享轻阴影、细边缘和透色材质 | Glass、ContentPanel、设备卡、工作台；glass_contrast_test |
| 7 设计还原 | 同步调整共享组件、实际页面结构、信息归属与文案；移除废弃设计页面，不保留旧入口 | mobile.pen、prod 文档、实际 Flutter 截图 |
| 8 Flexible | 根据父约束决定标题和内容空间；文本换行、内容滚动、大屏扩展。手机画稿尺寸只作视口，不作为缩放因子 | PageFrame、HomePage、各列表/表单；280窄屏、横屏、2倍文字与嵌入窄pane测试 |
| 9 旧版 TCP | 无线指南提供直接 IP+端口入口，默认5555，保留明确的 TCP 传输类型，不依据端口猜测协议 | WirelessGuidePage、ConnectionFormPage；connection_transport_test |
| 10 远控返回与三键 | 系统返回/实体 Escape 发远端 Android Back；仅关闭按钮离页。每设备 showNavigationBar 默认true，三键为4/3/187 | RemotePage、设备偏好；remote_input_test、remote_lifecycle_test |
| 11 越界静默丢弃 | 原坐标舍入可能产生 width/height 本身，引起远端参数拒绝并被误判为画面失败。边沿限制在有效像素内，越界取消已开始手势并忽略余下事件 | RemotePage.pointer；右边沿与越界不暂停回归 |

## 衍生问题

旧偏好仅作一次性清理，不继续提供旧模式。旧后台声音偏好也一并移除，后台声音随统一的后台保持设置。设备设置按设备 ID 存储，更新一个设备不能覆盖另一个设备；移除设备同步移除偏好。剪贴板使用代次与当前设备检查阻止旧请求、旧事件及离开前台后的结果写入主控。

音频检查除了“同设备去重”，还必须覆盖一台设备启动挂起时关闭另一台、退出期间启动返回，以及真实 session.disconnected 事件。清理不能排在另一个设备的启动之后；最后一个页面释放应立即撤销媒体启动意图，并独立停止对应设备声音。

空闲状态没有页面租约和声音任务时不查询音源，避免恢复事件触发无意义的状态查询循环。测试查询按设备用途区分，保留恢复流程不重放副作用的断言。音源启动要求真实控制会话，Rust夹具同步补齐视频/控制握手，不放宽生产约束。

远控有效手势出界必须发送最后有效点的 cancel，避免远端残留按下；重新进入画面不自动续接旧指针。正常断线仍可标记最后一帧与阻止输入，触控越界不进入该状态。导航条使用独立空间，触控坐标按剩余画面区域计算。

## 验证边界

最终稳定源码通过 `tool/check.sh` 各门禁：协议与FRB生成一致性、伴生组件确定性构建、工具与原生依赖检查、Dart/Rust格式、视频snapshot回归、workspace clippy（`-D warnings`）、Flutter analyze及架构分析插件契约。Rust共301项通过、68项依其真机/外部环境契约忽略；Flutter应用310项、interop_bridge 131项、design_system 3项通过。CPU敏感的既有密码学测试以 `RUST_TEST_THREADS=4` 执行。完整日志保存在 `/tmp/connect-refinement-check.log`。

Android 本轮实际端到端流程通过：独立主控与目标 AVD，旧版 TCP 连接、文件流程、H.265 486×1080 实际编码/解码与 `mdk.snapshot` 证据、默认三键、系统返回保留远控、画面外点击不暂停、退出控件拖动/收起/展开、关闭返回工作台、本地呈现暂停与关闭后无活动音源。最终 `productAcceptanceComplete` 与全部新增回执为 true，日志、回执及截图位于 `/tmp/connect-refinement-e2e`。本次启动的目标 AVD 与临时转发已清理，保留既有主控。

Android x64 debug APK 已构建并独立验证 ZIP、签名、Flutter/Rust ELF 架构与16KB对齐，使用既有 debug 签名。实际AVD流程的集成入口APK在收尾清理中移除，摘要回执保留于 `/tmp/connect-refinement-e2e/product-flow-apk-receipt.json`。该轮在目录迁移前、最终空闲查询修复后另构建普通 `lib/main.dart` 入口，产物为 `build/app/outputs/flutter-apk/app-debug.apk`（120,543,637字节，SHA256 `1f30b81316f955429560456965f74ee54ec4994c5febc00056af564300dfb71b`），构建及包装验证通过，未对普通入口重复drive。构建日志位于 `/tmp/connect-refinement-main-apk.log`，debug包不作为发行签名产物。

Pencil 修改保存并重开后核对为94页、27母组件、158变量，未保留独立音源/剪贴板/易用性设置页；活动分支无意外越界，工作台的一处纵向滚动视口裁剪按设计单独确认，完整内容保留；组件与变量无缺失。共享页头65个实例文案、工作台分组列表和X关闭按钮已核对。官方 DESIGN.md lint 为0错误、31警告，分类见[工具链记录](../research/design-system-and-toolchain.md)。Flutter 截图含浅/深色、外观、设备设置、TCP、平板、280窄屏与横屏2倍文字，保存在 `/tmp/connect-refined-ui`。

单测、组件测试和模拟器截图不能替代物理手机上的多设备声音听测、剪贴板系统权限、GPU材质与系统返回手势验收。模拟器日志仍有 GLES 0x501 及 Surface 释放后的 BufferQueue 告警，当前实际解码、健康状态和截图核对通过；不把这些局部证据推广为各GPU零告警或四端运行全部通过。未执行的真机组合不继承历史通过记录。
