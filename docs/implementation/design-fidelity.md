# 设计稿与 Flutter 核对

视觉数值归[视觉规范](../../designs/design.md)，页面行为归[产品规格](../../designs/prod/README.md)。本页维护源稿定位和捕获契约。

## 源稿与实现定位

唯一源稿为designs/mobile.pen，通过Pencil MCP或pen interactive对象API读写。代表状态查[用户流程](../../designs/prod/user-flows.md)，截图配对查[pages.json](../../tool/visual_parity/pages.json)，实现查[导航](flutter-navigation.md)。Frame可表达页面/抽屉/失败/授权状态，其数量不推导路由数；不另维护重复Frame清单。

## 静态核查

按受影响状态检查明暗、降低透明度、长标题、窄容器、文字放大、安全区及必要横屏/键盘。普通内容随父约束流式布局；滚动裁剪需核对末项可达。页头保护层最后绘制、止于实际标题栏底部，正文消费避让，不另加不透明AppBar底色。结构扫描与目视各提供边界/内容证据，运行与GPU另取证。

## 捕获契约

每case记录源Frame、截图/裁剪、视口、内容差异和夹具；未配对原因归unmatchedCaptures，局部状态不拉伸成整页。手机参考402×874/DPR1、安全区54/34；平板1194×834、桌面1440×960各自完整视口；照片/远控保留全屏。历史capture/layout契约只有PNG哈希一致才附报告。

运行截图后从根执行 `dart tool/visual_parity/compare.dart --pencil-dir <源稿导出> --flutter-dir <运行捕获> --output <新目录>`。工具输出并排/RGB差图，缺图/解码/尺寸错即失败，不拉伸、补边或自动对齐。completed仅表示比较结束，visualAcceptanceComplete/contentAcceptanceComplete需人工检查字形、内容、安全区、遮挡及滚动终点；RGB无自动验收阈值。

## 当前运行证据

glass_chrome_test.dart与navigation_lens_test.dart及对应driver覆盖透明页头、弹层/菜单、镜片静止/拖动/归位/滚动背景和辅助偏好。环境为API36 x64、Impeller OpenGLES/Mesa llvmpipe，未取得物理GPU或Apple原生等效证据。

双AVD曾核对全屏顶部、远端通知栏/返回、横屏比例、IME、窗口密度、通知及画质重建。物理刘海/OEM、连续手感、读屏、多视频负载和性能预算仍未覆盖。具体版本运行见[验收索引](validation.md)。
