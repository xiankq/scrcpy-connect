# 现成玻璃组件接入核查

日期：2026-10-20。已删除项目自定义的 `GlassTabBar`、`GlassIconButton` 及 `GlassDestination`；页面直接使用库的公开构造，设计系统只原样导出官方类型。对象为 Flutter 主控共享设计系统及对应 Pencil 静态代表状态。本记录只说明本次工作区的检查结果；当前材料规则归[视觉规范](../../designs/design.md)，产品入口归[信息架构](../../designs/prod/information-architecture.md)，资源和渲染边界归[架构](architecture.md#材质启动与渲染)。历史 `liquid_glass_easy` 的 GPU 回执不能用于本次接入认证。

## 固定来源与接入意图

根工作区解析的依赖为 `liquid_glass_widgets 1.13.0`；核对了该发布包的 `glass_tab_bar.dart`、`tab_bar_bottom_internal.dart`、`tab_bar_bottom_layout.dart` 与 `tab_bar_drag_gesture_mixin.dart`。上游为 [sdegenaar/liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets)，此处行为结论来自本机锁定版本源码，不推定后续版本一致。

底部导航使用现成 `GlassTabBar.bottom`。外部不再包整栏 `Glass` 或额外裁剪；静止选中面沿用 `glass-selected`，按压、拖动或正在归位时由内部局部镜片表达反馈。镜片保留库默认 clear 意图，不能机械套入整栏 regular 的散射。受控选中值归导航宿主；重复当前项、宿主拒绝切换及外部改变选中值均需保持内容与反馈一致。

标准点击路径会在 `onTapDown` 请求切换，平台视图混合路径另有释放时选择；横向拖动结束按位置与速度决定目标，拖动取消也可能请求最近目标。因此不能将普通按钮“取消必不提交”的规则直接写成底部导航的产品承诺。组件的原生内部镜片不属于每个目的地各包一片完整玻璃，不受旧静态“导航选中面与父导航同一平面”的表述限制。

## Flutter 控件核查与实施

| 控件 / 用途 | 本次接入与取舍 |
| --- | --- |
| 底部全局导航 | 页面直接构造官方 `GlassTabBar.bottom`，删除组件转发壳、外层玻璃、额外 clip、手写 spring 与选择色块。整栏映射项目 regular token，内部 indicator 不覆盖官方 clear 默认；高度根据实际标签及 `textScaler` 计算且至少为 64。实体分支使用已有 `surfaceContainerHigh` 语义选择面 |
| 独立圆形图标控制 | 页面直接构造官方 `GlassIconButton`，删除同名项目控件类；工具组内的图标仍由共享背景承载，不逐项添加完整玻璃 |
| 确认 / 编辑对话框及 Tooltip | 使用官方 `GlassCard` 并隔离本地光学层，保留框架路由、焦点、语义、窄屏和键盘适配。官方 `GlassDialog` / Sheet 的固定布局不适合这些既有内容约束，因此继续保留项目适配层；未将材料复用表述为完整替换其路由机制 |
| 视频控制组 | 为整个控制组增加 `GlassPressFeedback`，保留 slider scrubbing 的业务手势；新增两项使用实际 `VideoPreview` 的回归 |
| 菜单 | 原先已采用官方 `GlassMenu`，本次检查后保留 |
| 工具组、侧栏、远控退出把手 | 现有 Wrap、纵向排列及业务 pan 分别需要自身布局和手势归属，保留局部材料与按压观察反馈；未为采用现成控件而删除必要行为 |
| 普通开关、slider、表单及内容面 | 保持实体内容控件，不因库提供同名玻璃组件而替换所有内容表面 |

以上取舍按布局、内容与手势归属评估。现成控件持有材料和交互；业务导航回调留在页面。`GlassMaterial` 的 settings/quality/theme/navigationHeight 等方法只返回配置值，不生成按钮或导航组件。1.13.0 没有专属 IconButton/TabBar theme，且导航默认 settings 不完全读取全局 theme，因此仅将可统一的 stretch 放入官方主题，组件尺寸、选中色和镜片等公开参数在调用点明确配置。对话框、菜单和媒体工具组仅保留已说明的布局、路由或业务手势适配。

## Pencil 母组件与实例

通过 Pencil MCP 对象 API 读取和修改 `designs/mobile.pen`，并通过 `pen interactive --app visual_studio_code` 的 `save()` 落盘；未按文本读取或修改该文件。既有尺寸、颜色和 token 定义保持不变；降低透明度代表实例改用已有 `tint` 实体选中面，避免透明白选中面叠白底而失去轮廓。

| 对象 | 母组件 / 代表状态 ID | 本次核对 |
| --- | --- | --- |
| 悬浮底部导航 | 母组件 `Ffm0s`，静止选中槽 `fQuah` | 补充现成组件、受控选择、局部镜片及辅助偏好语义；母组件仍为淡色静止态 |
| 三个全局目的地 | 设备 `lUDPa/JS8Kf`、传输 `W6enLf/y78ks`、设置 `w6WUAT/NrufR` | 分别展开核对选中槽、标签、图标和整栏背景，导航高度均为 64 |
| 深色外观 | `iO69Y` 内 `OxyeM/P6kZv` | 实际截图检查文字、淡色选择与暗背景 |
| 降低透明度 | `iO69Y` 内 `W7Lua/tsJDG` | 实际截图检查实体面、边界与已有 `tint` 选择，无导航 shader |
| 材料对照 | `V6QGx4` 内 regular `dv6j1`、reduced `V5rM0d` | 逐一展开；reduced 根为实体面，选择使用已有 `tint`，无镜片 |
| 新导航交互对照 | 行 `N70xWl`；静止 `p3bT4/imM4A`、按压 `dpTfr/IhBFe`、拖动 `j70oXL/ZJSuG` | 复用 `Ffm0s`，只在按压/拖动静态代表位置设置局部 clear shader，不增加该镜片的阴影；说明明确动态待运行核验 |
| 圆形图标操作与页头 | `lufWX`、`wbM5x`，页头动作组 `BiHE4` | 核对现有玻璃母组件与共享动作组边界；不把每个组内图标另建完整材料 |
| 媒体导航 | `gkDVd`，照片页 `sepTa/KrWxP`，clear 动作组 `QRJfU` | 核对关闭与保存/分享采用 clear，静态文件名保持内容角色 |
| 大屏侧栏 | `UMqM7`，平板 `H0TFx/U05pQ`、桌面 `zLBrM/QhSA8` | 核对相同目的地和共享材料；本次底部交互镜片不变成侧栏逐项玻璃 |
| 确认/编辑对话框 | `DaArO`，重命名 `t9cCs`、删除 `PEVBx`、设备名 `vxekh`、移除 `PsZhk`、断开 `gVsDQ` | 核对现有实例引用与 regular 材料归属，不新增页面或改变动作 |
| 应用打开面板与退出把手 | `yLJek`、`c2RYVn`、`Z0fV6l/i8NNI` | 核对 regular 控制归属，保留实体远端内容与退出控件的空间关系 |

新增导航对照行和全部受影响导航实例的展开结构扫描未报告裁剪问题。源页面的扫描提示来自已禁用的组件插槽；已沿祖先启用状态核对，设备、传输、设置及明暗辅助状态未发现活动分支裁剪。材料板旧示例仍有分隔插槽的结构提示，本次未据此重排无关历史示例。

已实际查看深色状态、降低透明度状态、新增交互对照及按压局部截图。它们说明静态层次、文字和选择轮廓，不能证明 Flutter 后端的连续拖动、折射、手感或 GPU 表现。Pencil 使用已有 `assets/liquid-glass.glsl`，其静态镜片不等于运行库自身的 shader。

## 规范与 token 核验

`node tool/design_tokens/generate.mjs --check` 通过，官方 0.4.0 parser 报告 0 errors、68 warnings；`npm run lint --prefix tool/design_tokens` 通过，0 errors、68 warnings、1 info。保留警告来自既有光学/布局扩展属性与官方只扫描组件引用造成的 orphan token 提示；本次只修改正文，未改变 token 或生成常量。

## 回归与运行验证边界

主流程已回传以下结果：

| 层级 | 实际命令 / 范围 | 结果 |
| --- | --- | --- |
| 应用与设计系统全量回归 | 在 `app/` 运行 `rtk flutter test --no-pub --reporter expanded test ../packages/design_system/test` | 较早阶段 409 passed；直接使用官方控件后全量 410 passed；补齐官方主题下减少动态效果的真实拖动回归后，最终全量 411 passed，日志 `/tmp/connect-glass-components/direct-controls-final-tests.log` |
| 后续导航定向回归 | 全量完成后新增并修复语义与辅助偏好下键盘焦点两项回归，重新运行 `glass_navigation_test` | 6 passed，已包含在最终全量结果中；官方图标实际拖动回归验证普通模式跟手、减少动态效果时位移为零 |
| 设计系统静态分析 | `dart analyze packages/design_system` | No issues found |

## 模拟器崩溃定位与运行配置

实际环境为 Ubuntu 24.04、Flutter 3.47.7 / Dart 3.13.5、API 36 x86_64 AVD、Android Emulator 37.2.12。`swiftshader` 两次退出 SIGSEGV/139；`swangle`（关闭 Vulkan）和 `lavapipe` 在 Impeller OpenGLES / LiquidGlass 初始化后退出 SIGILL/132。负面回执保留在 `/tmp/connect-glass-components/gpu-attempts.json`，不能把初始化或 APK 编译成功当成成像通过。

GDB 捕获到宿主模拟器 `RenderThread` 在 `libgfxstream_backend.so+0x7c3bed` 执行 `ud2`，调用者为 `gles2_decoder_context_t::decode`。反汇编及二进制内嵌路径将其定位到 `gles_v30_imp.cpp` 的 `glInvalidateFramebuffer`：零附件分支进入 trap。[公开上游源码](https://github.com/google/gfxstream/blob/main/host/gl/glestranslator/gles_v2/gles_v30_imp.cpp#L623) 的 helper 对空 vector 使用 `&res[0]`，随后还有 `&emulatedAttachments[0]`；这与捕获的空计数分支吻合。[GLES 3.1 规范](https://registry.khronos.org/OpenGL/specs/es/3.1/es_spec_3.1.pdf) 第 337 页只禁止负附件数，零附件合法。[libc++ 硬化说明](https://libcxx.llvm.org/Hardening.html)解释了容器越界在生产构建触发 trap 的行为。该证据属于模拟器原生图形转换层；未把早先 SwiftShader 的 SIGSEGV 也无证据归入同一根因。原生栈和启动日志在 `/tmp/connect-glass-crash/`。

本机采用清除图形覆盖环境变量、显式 `-gpu host -feature -Vulkan` 的配置后恢复运行。它仍经过 gfxstream，属于经本机回归验证的运行规避，并未修补上游缺陷。实际 renderer 是系统 Mesa `llvmpipe (LLVM 20.1.2, 256 bits)`，GLES 3.0 / OpenGL 4.5，不是 Intel 硬件 GPU；不能因参数叫 host 就登记硬件加速。没有修改 SDK 二进制、pub 缓存或 `liquid_glass_widgets` 源码，也未降低应用 premium 材料。

仓库启动入口 `tool/glass_emulator.dart` 固定该配置，清除 Mesa/Gallium/EGL 覆盖，要求可访问的 X11 display，并关闭快照加载和保存。它不创建、清空或改写 AVD。当前主机从根目录运行：

```sh
rtk proxy env ANDROID_HOME=/home/xiankq/Android/Sdk \
  dart tool/glass_emulator.dart --avd interop-controller \
  --display :0 --xauthority /run/user/1000/gdm/Xauthority
```

display、Xauthority 与 AVD 是本机身份；其他机器须按实际环境指定，不把该配置当作所有 Linux 图形驱动的通用修复。

## 本次 GPU 成像与拖动回归

从 `app/` 执行：

```sh
rtk proxy env ANDROID_HOME=/home/xiankq/Android/Sdk \
  flutter drive --no-pub --profile -d emulator-5554 \
  --driver=../tool/driver/glass_components.dart \
  --target=integration_test/glass_components_test.dart
```

首次完整运行 31 秒通过；随后实际用仓库启动入口关闭并冷启动同一 AVD，41 秒复跑通过，第二份报告和图片在 `/tmp/connect-glass-components/gpu-cold/`。删除组件包装后，又以相同 driver 在 `/tmp/connect-glass-components/gpu-direct/` 完整运行 31 秒通过。三轮均有 11 张 1080×2400 PNG 及 `result.json` 位于 `/tmp/connect-glass-components/gpu/`。明暗静止、按住和首至末拖动共 6 图，加上对话框、Tooltip、独立图标按住、明暗降低透明度共 11 图。报告核对官方后端 1.13.0、shader 支持且加载、premium 适配器及实际光学层、无 lightweight 或 BackdropFilter 替代、按住/拖动时官方 indicator 的非零厚度、两次从 0 到 2 的回调提交及取消图标按压不激活。实体偏好下光学层、premium 适配器与模糊数均为零。主机逐图核对 PNG 尺寸、device/host SHA-256 与像素场景标记，`harnessComplete`、`hostValidationComplete` 均为 true。

辅助偏好断言初次将 `AdaptiveGlass` 实体路径的外壳统计为原生光学面而失败；现排除 minimal 外壳，并独立要求 `LiquidGlassLayer` 为零，未放宽实体偏好的实际渲染要求。修正后才登记完整通过。

已逐张有限目视：静止导航表现为淡色选中面，按住与拖动出现局部 clear 镜片和网格边缘折射，明暗文字可辨；对话框和提示框可见规则范围内的背景透入；实体导航下网格不透入。该样本不是原生 iOS 等效、连续运动手感、多路视频性能或物理设备认证，报告保持 `visualAcceptanceComplete=false`、`performanceMeasured=false`。

## 普通入口与调试产物

普通 `app/lib/main.dart` 的 Android x86_64 debug APK 构建通过；它与 profile 集成夹具是不同入口。此前请求软件渲染的失败尝试实际仍启动 Impeller OpenGLES，不能登记软件渲染通过；Linux 桌面构建缺少工具链，也不计通过。

采用上述运行配置后，普通入口首次正常显示设备列表，已通过 VM Service 连接执行 Dart MCP hot reload，结果 `Hot reload succeeded`。截图 `/tmp/connect-glass-crash/host-main.png` 已目视。

早先中间产物清理回执 `/tmp/connect-glass-components/cleanup.json` 记录 68 路径、527,125,864 字节；随后为崩溃回归重新生成 profile 夹具。最终已再次清理 app 专属 profile 中间产物和重复测试 APK，共 65 路径、527,059,934 字节，回执 `/tmp/connect-glass-components/cleanup-final.json`；保留普通 debug APK、既有 release、共享 hooks 与插件/Gradle 缓存。

最终直接使用官方组件的普通入口重新构建、安装、运行，并通过 VM Service 执行 hot reload（203ms），运行时错误查询为空。detach 后再次 force-stop / 普通 Activity 冷启动成功，pid4593；实际从底栏设备项拖到设置项并已目视最终设置页，截图 `/tmp/connect-glass-crash/direct-main-settings-settled.png`。模拟器与应用保留运行便于继续查看，未改变 AVD 持久配置；本次手建 VM 转发已移除。

最终普通 APK 为 `/home/xiankq/git/scrcpy-connect/app/build/app/outputs/flutter-apk/app-debug.apk`，84,208,106 字节，SHA-256 `0e44e16b51d1cc07bdb73ebaf7db749d823d52a64fd47023c0c2945134147c08`；ZIP 完整性与 x86_64 engine 条目核对通过，回执 `/tmp/connect-glass-components/main-apk.json`。其摘要区别于早先包装实现，不能复用旧摘要。
