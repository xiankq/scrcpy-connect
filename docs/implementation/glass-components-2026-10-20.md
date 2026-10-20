# 官方玻璃组件接入与模拟器运行

本记录限定2026-10-20、pub.dev 原版 `liquid_glass_widgets 1.13.0`、Flutter3.47.7/Dart3.13.5。当前材料/手势职责见[架构](architecture.md#材质启动与渲染)，视觉语义见[规范](../../designs/design.md)；不将旧easy后端成像继承为此次widgets验证。

## 接入边界

页面直接使用库的 `GlassTabBar.bottom`、`GlassIconButton` 和 `GlassMenu`，设计系统仅导出类型及配置值。底栏没有外套第二整栏玻璃；regular整栏与内部clear交互镜片分别处理，后者通过 `GlassMaterial.navigationLensSettings` 共用上游基线。业务导航持有受控选择，库承担拖动/焦点/材料反馈；其onTapDown或拖动取消回调不等同普通确认按钮的提交规则。

对话框/Tooltip用官方 `GlassCard`，保留框架路由、焦点、语义、键盘及滚动适配；菜单/提示各有独立采样平面，避免继承工具组范围。工具组、侧栏、视频控制及退出把手保留必要业务布局与手势归属，普通表单/内容面不因库有同名控件就替成玻璃。官方主题统一可共享的stretch，尺寸、选择色及组件不从主题读取的参数仍由调用点配置。

Pencil中的导航、明暗/降低透明度、媒体工具、大屏和确认实例经对象API展开核对。按住/拖动代表是静态状态，不证明连续运动或GPU成像；源稿定位统一见[设计对照](design-fidelity.md#源稿与实现定位)。

## 模拟器崩溃定位与运行配置

实际宿主为Ubuntu24.04、Android Emulator37.2.12、API36/x86_64 AVD。SwiftShader两次SIGSEGV；swangle关闭Vulkan和lavapipe在Impeller OpenGLES初始化后SIGILL。GDB在 `libgfxstream_backend.so` 捕获 `glInvalidateFramebuffer` 零附件路径的 `ud2`。

[对应gfxstream源码](https://github.com/google/gfxstream/blob/main/host/gl/glestranslator/gles_v2/gles_v30_imp.cpp#L623)对空vector访问 `&res[0]` / `&emulatedAttachments[0]`，与捕获分支吻合；[GLES3.1规范](https://registry.khronos.org/OpenGL/specs/es/3.1/es_spec_3.1.pdf)允许零附件数，[libc++硬化说明](https://libcxx.llvm.org/Hardening.html)解释越界trap。该定位属于模拟器原生图形转换层，不将不同栈的SwiftShader SIGSEGV无证据并为同因。

清除图形覆盖环境、显式 `-gpu host -feature -Vulkan` 后恢复运行，仍经过gfxstream。实际renderer是Mesa llvmpipe (LLVM20.1.2)，不是Intel硬件GPU；参数名host不能当硬件加速证据。这次模拟器规避没有修改 SDK 二进制或 pub 缓存，也没有降级 premium 材料。

`tool/glass_emulator.dart`固定该本机规避，清除Mesa/Gallium/EGL覆盖，要求可访问X11并禁用快照加载/保存，不创建或清空AVD：

```sh
dart tool/glass_emulator.dart --avd <既有AVD名称> \
  --display <本机display> --xauthority <本机Xauthority>
```

这不是所有Linux驱动的通用修复；启动参数、实际renderer和故障栈须按新环境重新确认。

## GPU成像与交互样本

以下为当轮历史命令。直接上游组件的采集夹具在测试收敛中移除；当前保留实际 PageFrame／弹层的 `glass_chrome_test.dart` 与 `tool/driver/glass_chrome.dart`，不再重复维护上游控件的场景矩阵。

```sh
flutter drive --profile -d <主控设备> \
  --driver=../tool/driver/glass_components.dart \
  --target=integration_test/glass_components_test.dart
```

API36/Impeller OpenGLES/llvmpipe样本完成冷启复跑和直接官方控件复跑。每轮分别捕获明暗静止、按住/拖动、对话框、Tooltip、独立图标及降低透明度；报告核对锁定后端、shader加载、实际光学层、无轻量/BackdropFilter替代、按住/拖动时非零镜片厚度、导航回调和图标取消不激活。实体偏好下光学层、premium适配器及模糊均为零；不能将minimal外壳统计为光学面。

最终收敛使用 pub.dev 原版，无 path override 或源码副本。明暗静止/按压/拖动与同坐标原背景分别取样；镜片仍继承父栏已处理的背景，不能把这轮截图解释为独立穿透底栏。未用新增固定描边、夸张折射或透明度替代材料规范。

设备/主机PNG尺寸、SHA和场景标记分别核对。有限目视看到clear镜片和网格边缘折射、明暗文字可辨、实体导航不透背景。`harnessComplete`与`hostValidationComplete`通过，`visualAcceptanceComplete=false`、`performanceMeasured=false`保持：这不是iOS原生等效、完整可打断手感、多视频性能或物理设备认证。

普通 `app/lib/main.dart` Android x64 debug也实际构建、安装、冷启动与热重载，设备列表及底栏拖到设置已目视、runtime errors为空。该普通入口与profile夹具是不同产物；未据此宣称Linux构建、软件渲染或其他宿主运行通过。逻辑回归与运行证据层级见[验证记录](validation.md)。
