# 生成链、依赖与产物边界

本文维护仓库工具职责、受控输入和构建产物规则；实际执行结果见[验收记录](validation.md)。

## 视觉 token

`designs/design.md` 是视觉值唯一来源。`tool/design_tokens` 固定官方 `@google/design.md@0.4.0`，从官方 `lint(markdown).designSystem` 模型生成 `packages/design_system/lib/src/design_tokens.g.dart`。上游没有 Dart CLI，DTCG 输出也不覆盖组件 token，因此仓库只维护 Dart emitter，不另建 YAML 解析器或第二套值。

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
dart tool/generate.dart
dart tool/generate.dart --check
```

生成文件不得手改。官方对项目扩展属性和未被标准组件引用的颜色会给出警告；这些警告保持可见，不以固定数量作为规格。完整 emitter 契约见[设计 token 工具](../../tool/design_tokens/README.md)。

## workspace 与生成

`app/pubspec.yaml` 是唯一 Flutter 应用入口；根 `pubspec.yaml` 只声明 workspace 和工具依赖。`app`、`packages/design_system`、`packages/interop_bridge` 共用根 `pubspec.lock` 与 `.dart_tool`，Cargo 使用根 workspace。

Flutter 运行、构建和测试在 `app/` 执行；仓库工具、生成和主机检查从根目录执行。主机驱动在 `tool/driver/`，性能目标在 `tool/benchmark/`，从 `app/` 显式使用 `--driver=../tool/driver/<入口>.dart` 与 `--target=../tool/benchmark/<入口>.dart`。

`protocol/commands.json` 生成 Dart/Rust 命令契约；`dart tool/protocol_codegen.dart` 只处理该来源。其余生成物由 `dart tool/generate.dart` 汇总，`--check` 同时检查生成漂移。依赖已缓存但网络不可用时，可使用 `flutter pub get --offline --enforce-lockfile`；不得借此更新锁文件或跳过一致性检查。

## 当前依赖边界

锁文件中的版本必须整体解析，不能为追新拆散兼容链：

| 依赖 | 当前边界 |
| --- | --- |
| `build_runner 2.16.2` / `build 4.0.11` | 更新版 `build_runner` 需要 `build 5`，现有 `go_router_builder` 与 `riverpod_generator` 仍约束 `build <5` |
| `cross_file 0.3.5+5` | 当前 `file_picker`、`share_plus` 仍依赖 0.3，不能单独升到 0.4 |
| `qr 3.0.2` | `qr_flutter 4.1.0` 仍依赖该主版本 |
| `sha1 0.10.7` | `rsa 0.9.10` 的 ADB AUTH 签名使用 digest 0.10；升级前需先迁移签名器 |
| `rustls-rustcrypto 0.0.2-alpha` | 当前指定 provider 无更新发布，不替换 TLS provider |
| Flutter SDK 锁定包 | `material_color_utilities`、`test_api` 随 SDK；升级 Flutter 后重新解析并跑生成与测试 |

新增或升级依赖时同步检查 `pubspec.lock`、`Cargo.lock`、许可证、对应源码归档和生成物，不以版本号变化代替构建或运行证据。

## 被控执行产物的共享打包

`servers/vendor`、`servers/companion`、`servers/helpers` 的源码、固定输入、manifest 和产物构成同一条链。`dart servers/package.dart` 核对摘要并生成 `packages/interop_bridge/assets/servers/`；`--check` 只读拒绝缺失、漂移和多余文件。

Android 三种主控 ABI 共享一套 Flutter package assets。`initializeNativeRuntime` 在 FRB 初始化前把六份资源还原到私有 `bundled_servers/`，逐一校验并在损坏时原子替换；解压长度有界。Rust 对照编译清单再次校验并将原始字节保存在进程内，部署不信任随后被修改的磁盘缓存。

被控助手按被控设备 ABI 选择，不能按主控架构裁剪。APK 检查核对共享资源只有一套、长度与摘要正确，并拒绝 Android Rust 库再次嵌入原始或压缩产物。修改 JAR、helper 或来源后需重建、更新 manifest，再同步共享资源；不得只替换二进制或降低编译目标。

## 社区原版 fvp 0.39.1

播放器使用 pub.dev 社区原版 `fvp: 0.39.1`，不保留本地 fork、path override 或 pub 缓存补丁。发布归档 SHA-256 为 `2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`。

Android、Windows、Linux 的 CMake 默认从 SourceForge 下载 MDK SDK；Apple CocoaPods 使用 `mdk ~> 0.39.0`，SwiftPM 使用上游固定归档。Dart 锁文件不固定这些平台 SDK 字节，构建回执按实际平台记录版本。原版 `MdkSnapshot` 对失败回调的空结果未判空，Bridge 因此使用有界原生回读并晚于排空再销毁 Player；逐帧诊断仍为可选。

Android 的 fvp 链接启用 `--as-needed`，应用打包排除未使用的 `libass.so`；FFmpeg 仍随包分发。该配置不修改社区包源码或 SDK 缓存，最终 ELF 必须没有缺失的 `libass.so` 必需依赖。

## 玻璃宿主

本机 Linux/X11 成像回归使用既有 AVD：

```sh
dart tool/glass_emulator.dart --avd <既有AVD名称> \
  --display <本机display> --xauthority <本机Xauthority>
```

入口清除 Mesa/Gallium/EGL 覆盖，使用 `-gpu host -feature -Vulkan`，禁用快照并保留 AVD。实际 renderer 通常仍是 Mesa llvmpipe 软件实现；“host”不代表硬件 GPU。该规避针对已知 Emulator 37.2.12/gfxstream 零附件崩溃，不保证其他 Linux 驱动。实际成像边界见[设计还原](design-fidelity.md)。

## 测试取舍

测试围绕失败风险和可观察结果保留，优先通过责任接口覆盖。常量、简单透传、框架默认、源码字符串和已由生成检查覆盖的稳定逻辑不单独建用例；同一场景不重复到多个层级。取消与迟到回执、资源所有权、协议互操作、持久化未知结果和真实故障回归保留独立断言。

截图按实际变更采集，不维护所有页面、主题和尺寸的常驻矩阵。设备用例由测试声明指定环境变量和隔离目标，ignored 不计作通过。

## 构建与产物边界

普通 APK、集成测试 APK、profile 夹具和不同 ABI 产物分别标识。同一路径被测试构建覆盖后，不能继续按普通应用产物交付。发布包记录入口、架构、签名、摘要和验证环境；历史摘要不代表当前文件。

调试结束清理过期中间目录、测试资产、重复 APK 和失效 `.dart_tool/flutter_build` 输出；仍复用的 `.dart_tool/hooks_runner/shared`、Gradle 和固定 SDK 缓存保留。来源归档、受控 JAR/helper、许可证及要求的对应源码属于项目输入，不按体积或目录名清理。

截图与日志使用系统临时目录，设备实验只清理本次创建的进程、转发、夹具和测试安装。重要结论在仓库记录环境和结果，不依赖临时文件继续存在。
