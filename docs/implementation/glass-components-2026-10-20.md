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

## 2026-10-21 静止镜片与固定选项组后续

本节记录后续实现及有限运行，不改写上文10月20日的原版控件事实。依赖仍为pub.dev原版1.13.0，未引入fork、自制shader或重复整栏玻璃。最初在原版底栏之上叠加公开 `AnimatedGlassIndicator`，可以呈现静止镜片，但会重新采样glyph并在稳定画面边缘留下碎字。后续通过公开 `GlassTab.icon`/`activeIcon` 插槽，将静止镜片改到选中glyph之前，保留原版高质量masking和单一track；该slot方案消除了文字痕迹，但镜片进入原选中ClipPath/saveLayer后未呈现期望的静止光学轮廓，因而未采用。

最终组合以公开 `AdaptiveGlass` 绘制唯一regular轨道，随后绘制静止 `AnimatedGlassIndicator`，最上方保留官方 `GlassTabBar.bottom` 的原始glyph、手势和移动镜片。前景bar的公开settings将厚度/模糊设为零、glass/backer透明、body为clear、shadow为空；锁定版本premium渲染器在有效厚度及模糊均为零时跳过光学绘制，因此不再产生第二条轨道。静止镜片在glyph之前且不进入选中saveLayer。该配置仅启用在浅色premium，不能将该快速路径结论推广到Skia/Web或轻量回退；暗色、实体偏好和fallback保留原路。当前代码与生命周期归[架构](architecture.md#材质启动与渲染)，材料目标仍由[视觉规范](../../designs/design.md#elevation--depth)维护。

运行环境为Ubuntu24.04、Flutter3.47.7/Dart3.13.5、Android Emulator37.2.12、API36/x86_64的 `interop-controller`。仍按上文固定host GL、禁用Vulkan配置启动；SurfaceFlinger实际报告Android Emulator OpenGL ES Translator、Mesa llvmpipe LLVM20.1.2、OpenGL ES3.1。宿主报告硬件GPU不可用，因此本轮属于真实shader软件Mesa成像，不是物理GPU验收。

独立入口为 `app/integration_test/navigation_lens_test.dart` 与 `tool/driver/navigation_lens.dart`，从 `app/` 运行：

```sh
rtk proxy env NAVIGATION_LENS_OUTPUT=/tmp/connect-navigation-lens-three-layer-20261021 \
  /home/xiankq/flutter/bin/flutter drive -d emulator-5554 --no-pub \
  --driver ../tool/driver/navigation_lens.dart \
  --target integration_test/navigation_lens_test.dart
```

最终三层版assembleDebug耗时63.3秒，设备测试13秒完成，断言与主机八张捕获回执通过，drive正常退出。样本独立保存在 `/tmp/connect-navigation-lens-three-layer-20261021/`：`rest.png`、`held.png`、`drag.png`、`returned.png`、`scroll.png`、`opaque.png`、`reduced-motion.png`、`reduced-motion-held.png`，`result.json`为 `navigationLensComplete: true`、`shaderSupported: true`。旧 `/tmp/connect-navigation-lens/` 保留的是未验收的high-slot版本，没有覆盖或混作新证据。夹具使用可滚动的文字列表，不冒充目标设备内容；验证支持并初始化真实shader、静止面挂载、按住与释放早期让位、拖到目的地后的恢复、实体偏好下无 `LiquidGlassLayer`/`BackdropFilter`，以及减少动态按住时只存在一片实际绘制的镜片、无扩张/pinch，松手后仍可导航。捕获前排出旧帧，主机核对八个回调；本入口没有复用10月20日的PNG哈希/像素场景标记验证，不能继承其产物身份保证。

逐张目视结果：`rest`、`returned`、`scroll`、`reduced-motion` 均可辨认静止选中镜片的薄边、轮廓与离面阴影，glyph没有旧叠加方案的碎字；滚动后镜片随真实背景变化，外栏仍只有一条可见轨道。`held`、`drag` 保留官方移动镜片的背景折射与形变，`reduced-motion-held` 为一片无扩张/pinch的镜片，`opaque` 为实体栏与清楚选中面。按住样本的触点十字为Flutter测试指针标记，不是产品材料。此有限矩阵通过本次静止光学及交接检查，不代表连续手感、多视频负载、读屏或物理GPU性能验收。

普通main入口在三层修复前另行实捕了浅色三个稳定选中目的地、按压横拖与归位、暗色、外观组卡及大字状态；当时热重载成功，runtime errors为空。原图位于 `/tmp/glass-navigation-resting-*.png`、`/tmp/glass-navigation-dark.png`、`/tmp/glass-appearance-group.png` 等本轮临时文件，不计作最终三层组合的样本。最终普通main冷构建后新增首页与设置稳定镜片、明暗实体组卡和白glyph实捕，当前DTD热重载成功且runtime errors为空；电量变化及普通产品流程证据见[验证记录](validation.md)。固定设置首页、外观、记录恢复、媒体空间及设备能力的组卡/语义图标有五项320宽、2倍文字Widget测试通过；共享设计系统全23项通过，三层修复后导航六项与相关Dart分析再次通过。未把其他固定页面的Widget夹具计作设备实捕。

公开 `GlassTabBar.bottom` 没有背景/indicator builder、静止thickness或直接关闭track绘制的开关；`backgroundKey`文档限定Skia/Web，现有track的独立采样key属于内部实现。曾试公开 `MaskingQuality.off`，该版把完整selected tabs行压入选中slot，实际出现微型重复tabs，因此未采用。最终通过上述公开settings的premium无光学路径与三层组件顺序解决，不复制上游实现，也未以固定描边或填充补成假镜片。

新slot测试曾在截图前两次遇到 `IntegrationTestPlugin` 缺失。同期另一交互终端构建release，生成注册器不含开发插件；串行 `--no-pub` 重跑仍复用该文件。等待release结束后执行官方 `flutter pub get` 恢复开发插件注册，再次运行截图channel与测试通过；未手改生成物或清理共享build。该失败属于构建注册状态，未计作产品功能失败。

较早七张叠加方案测试通过后，原模拟器进程退出245，末尾出现gfxstream空GL上下文日志，自动卸载未完成；仅能确认退出时间与日志，尚未证实根因。同一AVD用固定命令重启、未wipe，确认boot完成后继续执行slot及最终三层测试；这两轮均正常退出。最终三层测试后已交还5554，未触碰5556。测试通过与此前模拟器退出分别记录，不宣称该配置完全稳定。
