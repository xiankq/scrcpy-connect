# 设计稿与 Flutter 核对

视觉数值归[视觉规范](../../designs/design.md)，页面入口与行为归[产品规格](../../designs/prod/README.md)。本文维护源稿定位、捕获契约和证据边界，不复制逐页规则。

## 源稿与实现定位

`designs/mobile.pen` 是唯一源稿，须通过 Pencil MCP 或 `pen interactive` 对象 API 读写。代表状态从[用户流程](../../designs/prod/user-flows.md)定位，截图配对由[pages.json](../../tool/visual_parity/pages.json)维护，源码入口以[导航契约](flutter-navigation.md)为准。

一个 Frame 可表示页面的正常、失败、抽屉或系统授权状态，不要求独立路由。画布数、Frame 数、源码页数和路由数不能互相推导。

| 核对对象 | 源稿定位 | 实现入口 |
| --- | --- | --- |
| 设备状态、首卡与工作台 | `RTx0Z/uESR9/N5P7M`、`y5TL9/aozX4`；`nqQEb/m0AlTk/PxnBS/Txxv0/KcWEm` | `devices/widgets/`、`devices/workspace/index/` |
| 活跃应用与目标图标 | `U1FJF/VacW7/OApmp`、受限态 `lYdIf` | `running_apps.dart`、`apps.list(filter:running)`、`apps.icon` |
| 统一连接表单与发现 | 外壳 `JORmP`、Tab `igSfI`、`W3GRn/G4CpTk/OxUaB/OpFKk`、`yMlVd` | `connection/form/`、`connection/discovery/` |
| 授权密钥与转 IP | `nzitC/x7ZjT/s3Fdhr/bcFd3/B5nGcj/AXigJ`、`XszXp/gHHmj/vPWPs` | 设置、连接表单、`host_identity.rs`、`device.rs`、`tcpip.rs` |
| 传输与当前活动 | `W6enLf/R759qi/fKBPB/mDL3I` | `transfer_history_row.dart`、文件传输、设备 activities |
| 底栏镜片 | 母组件 `Ffm0s`、材料板 `N70xWl` | `home_page.dart`、`GlassMaterial.navigationLensSettings`、`NavigationSelectionLens` |
| 通知卡片 | `Cyzll`、`a7A57` | 通知页、系统提醒适配 |
| 画布组织 | `KTHuP/B3uE9/w4TjN`、共享板 `Rie7E/TfjoF` | 完整屏幕与局部状态分开；保留被引用母组件，删除页面已覆盖的重复小样 |

## 静态核查

每个受影响页面分别检查明暗、降低透明度、长标题、窄容器、文字放大、安全区和必要的横屏/键盘状态。普通内容按父约束流式布局；远控画面与浮层才使用绝对叠加。标记为滚动视口的裁剪必须确认完整末项可达。

结构扫描证明引用和几何边界，目视说明文字、材料和层级。两者都不能替代 Flutter 运行、真实 GPU 或双设备授权。页头保护层在正文层最后绘制并止于实际标题栏底部；滚动内容消费避让，不能给 AppBar 另加不透明底色。

## 捕获契约

配对配置记录每个 case 的源 Frame、截图、裁剪、视口、内容差异和夹具身份。没有完整 Frame，与已有 Frame 但未配对是不同状态；未配对原因保留在 `unmatchedCaptures`，局部状态不拉伸成整页。

手机参考为 402×874/DPR1，常态安全区 top 54/bottom 34；平板 1194×834、桌面 1440×960 使用各自完整视口。照片预览与远控保留全屏。历史 `capture-contract.json` 和 `layout-contract.json` 只有在 PNG 哈希匹配时才能附到报告；当前不维护遍历所有页面、主题和尺寸的截图矩阵。

按实际变更在运行应用中截图后，从仓库根运行：

```sh
dart tool/visual_parity/compare.dart \
  --pencil-dir <本次源稿导出目录> \
  --flutter-dir <本次Flutter捕获目录> \
  --output <新的比较目录>
```

工具生成并排图、RGB 差图和报告；缺图、解码失败或尺寸不匹配失败。源图不得拉伸、补边或自动对齐。`completed=true` 只表示比较完成；RGB 指标没有自动阈值，`visualAcceptanceComplete` 与 `contentAcceptanceComplete` 仍需人工核对字形、内容、安全区、遮挡和滚动终点。

## 当前运行证据

`glass_chrome_test.dart` 与对应 driver 覆盖透明页头、弹层、菜单、提示和辅助偏好；导航镜片入口为 `navigation_lens_test.dart` 与 `navigation_lens.dart`，覆盖静止、按住、拖动、归位、滚动背景、实体偏好和减少动态。当前宿主实际使用 Mesa llvmpipe 软件渲染，不能据此声称物理 GPU 或 Apple 原生等效。

API36 双 AVD 已实际核对全屏顶部区域、远端通知栏与返回、横屏比例、输入法、独立窗口逻辑密度、通知内容和质量重建。以上证明对应镜像中的界面与系统交互，不覆盖物理刘海、其他 OEM、连续手感、多视频负载、读屏或性能预算。

静态 Pencil 投影、Widget 软件捕获、真实 shader 成像和业务设备运行分别记录。现有样本未通过性能或完整可访问性验收，不能把“截图成功”写成视觉交付全部完成；最新证据与环境见[验收记录](validation.md)。
