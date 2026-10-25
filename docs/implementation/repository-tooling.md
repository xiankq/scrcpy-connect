# 生成链、依赖与产物边界

本文维护仓库工具职责、受控输入和构建产物规则；实际执行结果见[验收记录](validation.md)，当前代码、构建和调试改造见[本轮重构记录](code-and-build-refactor-validation.md)。

## 视觉 token

`designs/design.md` 是视觉值唯一来源。`tool/design_tokens` 固定官方 `@google/design.md@0.4.0`，从官方 `lint(markdown).designSystem` 模型生成 `packages/design_system/lib/src/design_tokens.g.dart`。上游没有 Dart CLI，DTCG 输出也不覆盖组件 token，因此仓库只维护 Dart emitter，不另建 YAML 解析器或第二套值。

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
dart --disable-dart-dev tool/generate.dart
dart --disable-dart-dev tool/generate.dart --check
```

生成文件不得手改。官方对项目扩展属性和未被标准组件引用的颜色会给出警告；这些警告保持可见，不以固定数量作为规格。完整 emitter 契约见[设计 token 工具](../../tool/design_tokens/README.md)。

## workspace 与生成

`app/pubspec.yaml` 是唯一 Flutter 应用入口；根 `pubspec.yaml` 声明 workspace 和工具依赖。`app` 与四个 Dart 能力包共用根 `pubspec.lock` 与 `.dart_tool`。ADB、scrcpy 的协议库、普通 API 库和各自 FRB 入口使用根 Cargo workspace；媒体核心使用 `rust/media_codec/` 的独立 workspace 与锁文件。应用不设置 Rust 工作区成员或原生业务组装层。

Flutter 应用运行、构建和集成测试在 `app/` 执行；能力包测试在各包执行，仓库工具与生成从根目录执行。主机驱动在 `tool/driver/`，集成测试目标在 `app/integration_test/`；独立诊断入口仍可位于 `tool/benchmark/`。

纯宿主工具测试在独立 `tool/host/` Dart 包运行，拥有自己的锁文件，不加入 Flutter workspace，也不依赖 Flutter 或能力包。这样工具的 ZIP、进程、生成器和协议夹具测试不会启动应用原生 hooks。实际应用、原生能力和设备测试仍在相应环境运行；不能把纯宿主通过当作原生验证。纯工具入口使用 `dart --disable-dart-dev tool/<entry>.dart` 直接运行 VM，Flutter 构建或能力包用例使用正常工具入口。

`protocol/commands.json` 定义应用 Dart 命令契约，`dart --disable-dart-dev tool/protocol_codegen.dart` 只生成应用内字段与核验策略，不生成 Rust 业务分派。旧 owner／nativeResult 分层字段被拒绝，能力层独立维护类型化 FRB 契约。仓库定位、工具查找和隔离复制等公共工具位于 `tool/src/repository_tooling.dart`。其余生成物由 `dart --disable-dart-dev tool/generate.dart` 汇总，`--check` 同时检查生成漂移。依赖已缓存但网络不可用时，可使用 `flutter pub get --offline --enforce-lockfile`；不得借此更新锁文件或跳过一致性检查。

FRB 配置统一放在仓库顶层，路径相对仓库根目录。`flutter_rust_bridge.yaml` 与 `flutter_rust_bridge.scrcpy.yaml` 分别指定 ADB、scrcpy 包内部的 Dart 生成目录及 `rust/` 中对应的 Rust 绑定。生成工具始终从根目录读取配置，隔离检查使用同一份配置与路径规则。

FRB 检查使用 `.dart_tool/frb_check/` 中单一受 OS 文件锁保护的私有输入镜像及 Cargo cache，增量同步源文件并移除已删除输入；不复制应用 runner、assets、被控 JAR、媒体来源归档或历史构建。镜像输出仍与仓库逐字节比较，复用缓存不跳过生成检查。生成检查关闭 Rust incremental 和 debug 信息，正常主机调试保留行号信息、关闭 incremental；连续检查复用同一缓存路径，避免每轮产生一整套随机临时编译树。

## 当前依赖边界

锁文件中的版本必须整体解析，不能为追新拆散兼容链：

| 依赖 | 当前边界 |
| --- | --- |
| `build_runner 2.16.2` / `build 4.0.11` | 更新版 `build_runner` 需要 `build 5`，现有 `go_router_builder` 与 `riverpod_generator` 仍约束 `build <5` |
| `cross_file 0.3.5+5` | 当前 `file_picker`、`share_plus` 仍依赖 0.3，不能单独升到 0.4 |
| `qr 3.0.2` | `qr_flutter 4.1.0` 仍依赖该主版本 |
| `sha1 0.10.7` | `rsa 0.9.10` 的 ADB AUTH 签名使用 digest 0.10；升级前需先迁移签名器 |
| `rustls-rustcrypto 0.0.2-alpha` | 固定使用此 TLS provider，常规依赖升级不替换 provider |
| Flutter SDK 锁定包 | `material_color_utilities`、`test_api` 随 SDK；升级 Flutter 后重新解析并跑生成与测试 |

新增或升级依赖时同步检查 `pubspec.lock`、`Cargo.lock`、许可证、对应源码归档和生成物，不以版本号变化代替构建或运行证据。

## 被控执行产物的共享打包

`servers/vendor`、`servers/companion` 的源码与受控产物，以及 `rust/adb/device_fs_helper` 的通用设备端 Rust 源码与 `servers/helpers` 的构建器、固定输入、manifest 和四 ABI 产物构成同一条链。文件助手保留独立 workspace、锁文件与构建 profile，不加入根 Rust workspace。`dart --disable-dart-dev servers/package.dart` 核对摘要并生成 `app/assets/servers/`；`--check` 只读拒绝缺失、漂移和多余文件。

Android 三种主控 ABI 共享一套应用 assets。应用资源适配器负责按共享 manifest 校验、限制解压长度和原子还原私有 `bundled_servers/`；`ApplicationHost` 在交付业务能力前，将全部被控 ABI 的文件助手注入实际同库 `NativeAdbFileApi`，随后初始化 scrcpy JAR。打包包含资源不等于运行时已经配置能力。能力包只校验并持有本次明确提供的执行输入，不读取应用 assets、私有目录、整份业务清单或产品设置；后续部署使用已接收的字节，不重新信任可变磁盘缓存。

被控助手按被控设备 ABI 选择，不能按主控架构裁剪。APK 检查核对共享资源只有一套、长度与摘要正确，并拒绝 Android Rust 库再次嵌入原始或压缩产物。修改 JAR、helper 或来源后需重建、更新 manifest，再同步共享资源；不得只替换二进制或降低编译目标。

## 原生媒体与官方 ADB

`packages/media_codec/third_party/` 固定 FFmpeg、dav1d 与 nv-codec-headers 的来源和 SHA-256。`packages/media_codec/tool/build_ffmpeg.py` 只构建所需静态库，并生成配置回执与依赖许可证；构建缓存位于 `.dart_tool/media_codec/`。构建需要目标平台工具链、Python、Meson、Ninja 与适用的汇编器，不从播放器 SDK 下载通用媒体运行时。

媒体编译锁和工作目录均以实际安装 prefix 为身份，区分 Apple 设备、模拟器及其他目标配置；MSVC 环境探针使用本次独占的临时文件。成功后保留可复用安装库、配置、来源和许可证，回收不参与缓存命中的中间对象；清理失败报告并保留现场，后续同配置命中时重试。失败构建保留自身工作区以供诊断，不删除其他并行配置。

共享解码核心位于 `rust/media_codec/`，使用独立 Cargo workspace 与锁文件；bindgen 从固定 FFmpeg 头文件生成 ABI。Flutter 插件只实现纹理、音频输出及生命周期需要的平台胶水。Apple 源码适配与实际 SDK/机器验收分开记录。

Windows 宿主需要 Visual Studio C++ 桌面工作负载、Windows SDK 和 `Microsoft.VisualStudio.Component.VC.ATL`；现有通知插件编译依赖 `atlbase.h`，仅安装桌面工作负载不足。工具查找遵守 Windows PATHEXT，不能执行 Flutter SDK 中供 POSIX 使用的同名无扩展脚本。

`packages/adb/third_party/platform-tools.lock.json` 固定桌面官方 platform-tools 归档及选取文件摘要。`packages/adb/tool/prepare_adb.dart` 校验后只提取 adb、Windows 所需 DLL、NOTICE 与版本信息，桌面包放置于可执行文件旁的 `adb/`。Android/iOS 不附带桌面 adb。`tool/build_host.dart` 核验目标架构、裁剪配置、必需原生库与官方 adb，再生成交付归档。

Linux/Android 的通用进程监督器源码归 `rust/adb/api/supervisor/`，由该库 `build.rs` 调用目标 `rustc` 构建后嵌入能力库；不增加应用 asset、共享包或 Cargo 工作区成员。交叉构建必须提供目标 linker，ABI 与页大小等目标 flags 传递给监督器，不能嵌入宿主产物代替目标产物。ADB 与 scrcpy 的 Native Assets hooks 显式登记 build script 和监督器源码，隔离生成复制整个 Rust 输入树。Linux 运行使用封存的可执行 memfd；Android 只有目标编译证据，移动 ADB 不使用桌面进程路径。Darwin 尚未完成相同监督机制，不能把 Linux 回归外推为 macOS 验收。

## 玻璃宿主

本机 Linux/X11 成像回归使用既有 AVD：

```sh
dart --disable-dart-dev tool/glass_emulator.dart --avd <既有AVD名称> \
  --display <本机display> --xauthority <本机Xauthority>
```

入口清除 Mesa/Gallium/EGL 覆盖，使用 `-gpu host -feature -Vulkan`，禁用快照并保留 AVD。实际 renderer 通常仍是 Mesa llvmpipe 软件实现；“host”不代表硬件 GPU。该规避针对已知 Emulator 37.2.12/gfxstream 零附件崩溃，不保证其他 Linux 驱动。实际成像边界见[设计还原](design-fidelity.md)。

## 测试取舍

`dart --disable-dart-dev tool/check_architecture.dart` 随主机门禁执行，依赖层次在 `tool/src/architecture.dart` 明确维护；通用包按已接受的架构决定声明其允许依赖。Rust 同时使用 Cargo metadata 核验带平台条件的路径依赖。Dart 检查读取真实语法树，不以目录名称或文本搜索推断依赖。生成库及 typed router 的组装例外见[模块接口](architecture.md#模块位置与接口)。

主门禁分别检查根 Rust workspace 和独立 `rust/media_codec/` 的格式，不能以根目录的 `cargo fmt --all` 代替后者。媒体核心的主机测试和 Clippy 另需固定 FFmpeg 构建、匹配的 Clang 资源目录及目标平台链接环境；Flutter 包测试不能替代这组 Rust 核验。

测试围绕失败风险和可观察结果保留，优先通过责任接口覆盖。常量、简单透传、框架默认、源码字符串和已由生成检查覆盖的稳定逻辑不单独建用例；同一场景不重复到多个层级。取消与迟到回执、资源所有权、协议互操作、持久化未知结果和真实故障回归保留独立断言。

日常调试按修改范围运行纯宿主、应用或能力包用例；`tool/check.sh` 是完整仓库门禁，不作为每次调试前置。`--android` 默认仅构建 `android-arm64`，通过 `ANDROID_TARGET_PLATFORM` 明确选择其他单 ABI；跨 ABI 验证使用发布入口。Flutter、FRB、Gradle、Java/DEX 和 Cargo 等长任务流式输出到终端，不完整缓存日志。需要解析的进程回执使用有界异步捕获，每条输出流有字节上限；超时或超限失败后确认自有直接子进程退出，不能持续积累日志或把截断数据当成完整回执。

Flutter 的宿主测试、设备构建和 release 构建会共用工作区的插件注册生成物；同一工作区内串行执行这些准备与编译步骤，避免 release 排除开发插件的注册表覆盖正在构建的集成测试。设备截图和结果回执必须使用实际存在的集成测试插件，不因通道缺失静默跳过。纯宿主工具测试使用独立 Dart 环境，可与设备运行并行。

设备驱动在 SDK 退出前的响应回调及异常收尾中恢复自有资源；多个独立恢复动作逐项尝试并汇总失败，原始错误与堆栈保持可追溯。VM 巡检 RPC 有有限等待，停止后先排空巡检再恢复设备，避免清理与在途观察竞争。截图按实际变更采集，不维护所有页面、主题和尺寸的常驻矩阵。设备用例由测试声明指定环境变量和隔离目标，ignored 不计作通过。

独立 Android 夹具共用 `tool/e2e/build_fixture.dart`，在同一输出目录持锁构建。复用身份覆盖源码、资源、构建器、SDK/JDK 工具与测试签名密钥；命中前核对实际 APK 摘要及签名，损坏或工具变化重新构建。编译目录仅在未命中时创建并在收尾回收，保留可复用的签名密钥、最终 APK 和输入回执；不为每次调试重复展开 Java、DEX 和 APK 中间产物。上传到设备的宿主样本使用本次独占的系统临时目录，生成、上传及核验结束后回收，截图和结果回执按实验用途保留。

## 构建与产物边界

普通 APK、集成测试 APK、profile 夹具和不同 ABI 产物分别标识。同一路径被测试构建覆盖后，不能继续按普通应用产物交付。发布包记录入口、架构、签名、摘要和验证环境；历史摘要不代表当前文件。

调试结束清理过期中间目录、测试资产、重复 APK 和失效 `.dart_tool/flutter_build` 输出；仍复用的 `.dart_tool/hooks_runner/shared`、Gradle 和固定 SDK 缓存保留。来源归档、受控 JAR/helper、许可证及要求的对应源码属于项目输入，不按体积或目录名清理。

截图与日志使用系统临时目录，设备实验只清理本次创建的进程、转发、夹具和测试安装。重要结论在仓库记录环境和结果，不依赖临时文件继续存在。

应用的系统文档暂存与传输来源属于受账本和发布租约保护的数据，不归构建清理管理。其共用容量、页面归还、取消排空及引用核对遵守[架构所有权](architecture.md#恢复持久化与媒体)；调试或恢复不能按体积清除未知来源来腾出空间。
