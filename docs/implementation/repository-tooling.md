# Token生成与单应用目录（2026-10-19）

## 官方解析与Dart生成

`designs/design.md`是视觉值来源。固定`@google/design.md@0.4.0`及npm lockfile，使用其公开`lint(markdown).designSystem`模型生成`packages/design_system/lib/src/design_tokens.g.dart`。项目仅提供Dart输出层，不另写YAML解析器或第二份token值。

官方当前CLI支持CSS、Tailwind、DTCG等格式，没有Dart格式；DTCG输出还不包含components，不能覆盖本项目的玻璃光学参数。采用完整官方解析模型保留颜色、alpha、排版、间距、圆角、组件属性和引用。[官方API](https://github.com/google-labs-code/design.md#programmatic-api)、[官方export命令](https://github.com/google-labs-code/design.md/blob/main/packages/cli/src/commands/export.ts)、[DTCG输出](https://github.com/google-labs-code/design.md/blob/main/packages/cli/src/linter/dtcg/handler.ts)。

从根目录执行：

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
python3 tool/generate.py
python3 tool/generate.py --check
```

只生成视觉token时使用`node tool/design_tokens/generate.mjs`。`--check`在内存生成、格式化并比较，不覆盖源码，源值变化或生成物漂移会失败；缺失引用、未知属性、标识符冲突、未定义单位和不完整排版也会失败。官方0.4.0会忽略YAML数字行高，因此源文件把无单位行高写为字符串，不以手工解析补救。px按规范映射Flutter逻辑像素。

设计系统使用生成常量，`ConnectTokens`只保留语义接口。应用57个文件的通用间距、圆角、媒体底色、小字、图标和标题高度也改为生成值引用。协议、媒体尺寸、手势几何和布局策略阈值不映射成视觉token；尚无公共语义的个别特殊间距不强行套用其他同数值token。字体大小、字重和行距来自规范；按现有规范继续使用平台中文系统字体。

`tool/check.sh`安装固定Node依赖，运行生成一致性及Node回归，使用同一份依赖执行官方lint。当前lint为0错误、42警告：15项明确支持的组件扩展属性、27项未被官方components引用检查覆盖的颜色；警告不隐藏。

## 根目录为Flutter应用

项目只有一个应用，根`pubspec.yaml`直接声明`scrcpy_connect`；`lib/`、`test/`、`integration_test/`、`test_driver/`、`benchmark/`及各平台runner位于根目录。`packages/design_system`与`packages/interop_bridge`继续作为Dart workspace包；`crates/`继续为Cargo workspace，不因应用移动而合并职责。

旧`apps/connect`与空`apps`目录已移除。依赖路径、build_runner、FRB隔离检查、Android/其他宿主打包脚本、分析插件探针、CI产物位置和文档命令同步更新；签名文件随Android工程原样移动，未更换身份。迁移时暂存的旧应用build、Dart缓存和插件登记文件在新工程验收后已清理；本机IDE配置的小型备份仍保留于`/tmp/connect-root-layout-c_ziqepa/old-app-cache`，不作为第二个工程入口。

所有常用命令现在从仓库根目录运行：

```sh
flutter pub get
flutter run
flutter test
python3 tool/android.py build
```

## third_party/fvp保留原因

该目录只有官方fvp 0.39.1的受控源码副本：88个跟踪文件，共481,632字节。MDK下载与`.cxx`等缓存由Git忽略。差异是五份原生snapshot回调的空结果保护、MDK 0.39.0版本与官方归档SHA固定、Apple精确版本约束，以及相应清单和回归；没有修改公开Dart播放器API。[补丁清单](../../third_party/fvp/CONNECT_PATCHES.md)。

snapshot失败允许空结果，官方回调直接解引用会使主控原生进程崩溃，Dart异常处理不能拦截。生产首帧、恢复和截图均使用此路径。2026-10-19核查的官方最新发布仍为0.39.1，master与v0.39.1均指向`a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93`，尚无同等修复可直接替换。[发布元数据](https://pub.dev/api/packages/fvp)、[该版本回调源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/callbacks.cpp)。

所以保留目录及许可证。改成自有Git fork仍需维护同样补丁；改为构建前下载并打补丁会增加依赖准备步骤。上游包含同等修复和可重复依赖约束后，才可取消path override及此副本，不能仅删除目录并退回有崩溃风险的发布版。

## 本轮验证

根目录应用310项、桥接层131项、设计系统4项测试，完整Flutter analyze、分析插件契约、生成器4项Node回归、FRB与Dart生成一致性通过；255个Dart文件格式检查通过。工具8项回归、原生snapshot接缝、CMake依赖3项及driver验收契约通过。

普通`lib/main.dart`入口从根目录实际构建Android x64 debug通过，耗时59.98秒；无旧CMake路径错误。新产物`build/app/outputs/flutter-apk/app-debug.apk`共120,500,169字节，SHA256为`8b40368290e232b01c3cae6ed25b9c51dcd4f5e8318bd372afe9cf839d8d3cfa`。独立验证x86_64 Flutter/Rust ELF、ZIP完整性、16KB对齐与签名通过；debug证书仍为既有身份。JVM原生ownership3项、audio1项通过。构建及验证记录位于`/tmp/connect-root-build.log`、`/tmp/connect-root-apk-receipt.json`和`/tmp/connect-root-native-{ownership,audio}.log`。

本轮未对新包重复设备端到端部署，未在其他宿主构建；迁移前的AVD流程仍保留其原有时间及产物边界，不继承为新包运行结果。

本轮收尾清理重复旧构建、旧Dart缓存、旧APK及过渡设计导出，共释放约11.32 GiB；最新根目录APK、验收日志/回执/截图和仍复用的构建缓存保留。旧集成入口APK仅保留摘要回执`/tmp/connect-refinement-e2e/product-flow-apk-receipt.json`。
