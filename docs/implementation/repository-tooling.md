# 生成链、单应用目录与受控依赖

本文记录仓库工具链的职责边界。实际检查与运行边界见[验证记录](validation.md)，本文件维护工具职责与构建输入。

2026-10-20 的依赖版本核对、上游升级约束及构建结果见[依赖升级记录](dependency-upgrade-2026-10-20.md)。

## 视觉 token 的权威来源

`designs/design.md` 是视觉值来源。`tool/design_tokens` 固定官方 `@google/design.md@0.4.0`，从公开 `lint(markdown).designSystem` 解析模型生成 `packages/design_system/lib/src/design_tokens.g.dart`。官方该版本没有直接生成 Dart 的 CLI，DTCG 输出也未覆盖组件属性；项目只维护 Dart emitter，不另建 YAML 解析器或第二套 token 值。

修改来源后重新生成，生成文件随源码维护且不得手改。仅生成 token、检查漂移、官方解析器的单位限制及扩展属性契约见 [生成器说明](../../tool/design_tokens/README.md)。`ConnectTokens` 保留语义接口，主题和材质使用生成常量；协议、媒体尺寸、手势几何和布局策略阈值不按数值巧合转换为视觉 token。

完整生成与一致性入口从仓库根执行：

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
dart tool/generate.dart
dart tool/generate.dart --check
```

`tool/generate.dart --check` 汇总 token、FRB 和 Dart builder 的生成一致性。`tool/check.sh` 使用固定 Node 依赖运行官方 lint 与生成器回归；官方对项目扩展属性和未直接被标准 components 引用的颜色所给警告保持可见，警告数是源文件状态的结果，不作为固定规格。

依赖解析先通过锁文件完成，生成过程不自动升级 FRB 依赖，也不触发 `dart run` 的隐式重新解析。网络不可用但固定依赖已缓存时，可先使用 `flutter pub get --offline --enforce-lockfile`；这不允许更新锁文件或跳过生成一致性检查。

## 应用与 workspace 职责

`app/pubspec.yaml` 是唯一 Flutter 应用入口，`app/` 直接包含 `lib/`、`test/`、`integration_test/` 与平台 runner。根 `pubspec.yaml` 仅声明 Dart workspace 与仓库工具依赖；`app`、`packages/design_system` 与 `packages/interop_bridge` 共享根 `pubspec.lock` 和 `.dart_tool`，依赖从仓库根统一解析。`crates/` 为 Cargo workspace。

应用运行、构建和 Flutter 测试在 `app/` 执行。主机驱动保留在 `tool/driver/`，性能基准入口保留在 `tool/benchmark/`；从 `app/` 运行时显式指定 `--driver=../tool/driver/<入口>.dart` 与 `--target=../tool/benchmark/<入口>.dart`。仓库工具、生成命令与 CI 编排入口仍从仓库根执行，工具负责将 Flutter 子进程的工作目录设为 `app/`。普通 APK 输出位于 `app/build/app/outputs/flutter-apk/`。

本机 Linux/X11 的玻璃成像回归使用 `dart tool/glass_emulator.dart --avd <名称>` 启动既有 AVD；该入口固定已验证的 host GL 配置并清除图形覆盖环境，不创建或清空设备。Emulator 37.2.12 原生崩溃证据、display 参数、实际 Mesa 软件 renderer 及适用边界见[组件运行记录](glass-components-2026-10-20.md#模拟器崩溃定位与运行配置)。

`dart tool/android.dart build` 默认构建 ARM32、ARM64、x86_64 通用 release APK，并压缩包内原生库，以下载体积为优先。Android 安装时会解压匹配架构的库，需将下载大小与安装后的总占用分别衡量。`--no-compress-native` 保留库在 APK 中直接加载，`--abi` 可用于特定架构分析；这些对照构建不能替代通用交付包。

仓库自有生成、构建、诊断及主机测试编排统一使用 Dart；服务端构建器随其产物保存在 `servers/`，其余入口在 `tool/`。工具回归使用同一锁定的 `flutter_test`，不另建测试依赖环境。Node 仅用于官方 DESIGN.md 解析及其 Dart emitter；原生源码和系统构建器保持平台要求的语言。第三方来源归档内的上游脚本不属于自有工具，不改写归档以消除文件扩展名。

工具迁移后的历史回执仍只证明原版本的运行结果。本文与专项记录中的复现入口随目录调整，原日志、版本、环境及已知限制不因迁移改变。

## 被控执行产物的共享打包

`servers/vendor`、`servers/companion` 和 `servers/helpers` 的原始产物及来源 manifest 仍是受控输入。`dart servers/package.dart` 核对这些摘要，生成 `packages/interop_bridge/assets/servers/` 中的六份 zlib 和原始字节清单；`--check` 只读检查缺失、漂移和多余文件。该生成器已接入 `tool/generate.dart`，更新原始产物后随生成链提交压缩资源，不改写 JAR、DEX 或助手本身。

Android 的三种主控 ABI 共享一套 Flutter package assets，不在各自 Rust 库中嵌入执行产物。`initializeNativeRuntime` 在调用 FRB 初始化前，将六份资源还原到应用私有根的 `bundled_servers/`，逐次校验已有缓存，损坏时原子替换；解压长度有界。Rust 对照编译清单再次校验并保存进程内不可变字节，部署不信任随后被替换的磁盘缓存。缺失或错误资源使初始化失败，不降级到另一份产物。其他宿主及独立 Rust 使用同一组内置压缩资源，验证后还原。

被控助手按被控设备 ABI 选择，不能按主控架构删减。APK 检查核对共享压缩资源只有一套、还原长度与摘要正确，并拒绝 Android Rust 库再次内嵌原始或压缩产物。来源归档和许可证的分发要求不因压缩改变。

## 社区原版 fvp 0.39.1

播放器精确依赖 pub.dev 社区原版 `fvp: 0.39.1`，由锁文件记录 hosted 包身份。不保留 `third_party/fvp` 源码副本、path override 或本地空回调补丁，也不修改 pub 缓存。包的来源是 [0.39.1 发布版](https://pub.dev/packages/fvp/versions/0.39.1)，其[原始归档](https://pub.dev/api/archives/fvp-0.39.1.tar.gz) SHA-256 为 `2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`。

MDK 的规则直接继承该发布包，不再由本仓库统一固定正式版本或各平台归档摘要：

| 构建路径 | 原版依赖规则 |
| --- | --- |
| Android、Windows、Linux 的 CMake | 默认从 SourceForge nightly 下载对应平台 SDK；上游支持 `FVP_DEPS_URL`、可选 `FVP_DEPS_SHA256` 与 `FVP_DEPS_LATEST`。Dart 锁文件不固定这些下载字节。 |
| Apple CocoaPods | `mdk ~> 0.39.0` 版本范围，由 Pod 解析结果确定具体版本。 |
| Apple SwiftPM | 上游 binary target 使用 MDK 0.39.0 Apple 归档 URL 及其 checksum。 |

规则依据为固定上游的 [CMake 下载器](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/cmake/deps.cmake)、[Podspec](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/ios/fvp.podspec) 和 [SwiftPM 清单](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/darwin/fvp/Package.swift)。构建回执按实际平台记录采用的 SDK；下载缓存不作为跟踪源码保存。

Android 仅对 fvp 插件链接启用 `--as-needed`，去掉可选运行库的冗余硬依赖后，应用打包排除 `libass.so`。远控输入没有字幕轨，普通视频预览使用平台播放器；其他宿主不排除字幕库。FFmpeg 仍随包分发并由 MDK 运行时加载。此配置不修改社区包源码、SDK 缓存或下载来源，最终 ELF 必须没有缺失的 `libass.so` 必需依赖。

原版 `MdkSnapshot` 对 MDK 失败回调的空 `ret` 未判空，构造 Dart typed data 时直接读取其 stride、height 和 data。此前宿主源边界探针曾注入该空结果并得到原生 SIGSEGV；这是空结果路径的已知限制，区别于 renderer 内部的历史空 `std::function` 崩溃，Dart 异常处理不能拦截该原生解引用。当前选择直接使用原版，不保留本地修补。[原版回调源码](https://github.com/wang-bin/fvp/blob/a6e59bdaa690fc7bbd2d80f5e299ad9e0515be93/lib/src/callbacks.cpp)、[历史调查](../research/scrcpy-first-frame-performance.md#fvp空结果故障与可复现交付2026-10-18)。

本地补丁及其 `fvp_snapshot_regression`、`check_native_deps` 专用工具与 MDK 固定回归已移除。普通宿主产物的链接、库架构和打包验证继续保留。下文及专项记录中的补丁版测试、APK、SDK 摘要均保留历史身份，不继承为社区原版验证；切换后的实际结果另记[验收记录](validation.md)。

## 构建与产物边界

被控执行产物集中在 `servers/`。scrcpy 使用一份固定版本、上游 Java 源不改动的标准脱糖构建；原始来源、构建输入、DEX 回填、许可及对应源码由 [vendor 清单与工具](../../servers/vendor/README.md)维护。`tool/check.sh` 核对 vendor 和 companion 产物，并执行旧平台兼容回归；功能下限及实际设备证据见[被控兼容边界](android-target-compatibility.md)。构建产物、来源归档和下载缓存不可混为同一清理对象。

普通 `app/lib/main.dart` 安装包与集成测试入口安装包分开标识；同一输出文件名被测试构建覆盖后，不能继续按普通应用产物交付。保留的交付包记录入口、架构、签名核验与摘要，历史摘要不代表当前文件。

调试结束清理过期 `app/build` 中间目录、测试资产、重复 APK 和已失效的 `.dart_tool/flutter_build` 输出。`.dart_tool/hooks_runner/shared`、Gradle 和固定 SDK 下载可作为复用缓存保留，不能与发布包混入 Git；清理前确认没有运行中的构建使用这些目录。

设备实验按本次创建的资源清理：测试进程、临时转发、夹具和目标模拟器均记录身份，既有主控及用户资源不随测试批次停止。截图与日志使用系统临时目录；重要结论在仓库文档中保留环境和结果，不能仅依靠临时文件存在。
