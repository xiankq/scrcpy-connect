# 生成链、单应用目录与受控依赖

本文记录仓库工具链的职责边界。当前产品修订的验证索引见 [产品验收记录](product-refinement.md)；下文测试数、APK 摘要与临时路径是注明阶段的历史产物，不是当前检出的自动通过声明。

## 视觉 token 的权威来源

`designs/design.md` 是视觉值来源。`tool/design_tokens` 固定官方 `@google/design.md@0.4.0`，从公开 `lint(markdown).designSystem` 解析模型生成 `packages/design_system/lib/src/design_tokens.g.dart`。官方该版本没有直接生成 Dart 的 CLI，DTCG 输出也未覆盖组件属性；项目只维护 Dart emitter，不另建 YAML 解析器或第二套 token 值。

修改来源后重新生成，生成文件随源码维护且不得手改。仅生成 token、检查漂移、官方解析器的单位限制及扩展属性契约见 [生成器说明](../../tool/design_tokens/README.md)。`ConnectTokens` 保留语义接口，主题和材质使用生成常量；协议、媒体尺寸、手势几何和布局策略阈值不按数值巧合转换为视觉 token。

完整生成与一致性入口从仓库根执行：

```sh
rtk proxy npm ci --ignore-scripts --prefix tool/design_tokens
rtk proxy python3 tool/generate.py
rtk proxy python3 tool/generate.py --check
```

`tool/generate.py --check` 汇总 token、FRB 和 Dart builder 的生成一致性。`tool/check.sh` 使用固定 Node 依赖运行官方 lint 与生成器回归；官方对项目扩展属性和未直接被标准 components 引用的颜色所给警告保持可见，警告数是源文件状态的结果，不作为固定规格。

依赖解析先通过锁文件完成，生成过程不自动升级 FRB 依赖，也不触发 `dart run` 的隐式重新解析。网络不可用但固定依赖已缓存时，可先使用 `flutter pub get --offline --enforce-lockfile`；这不允许更新锁文件或跳过生成一致性检查。

## 根目录应用与包职责

根 `pubspec.yaml` 是唯一 Flutter 应用入口。`lib/`、`test/`、`integration_test/`、`test_driver/`、`benchmark/` 与平台 runner 均在根目录；命令和 CI 产物路径从根解析，旧 `apps/connect` 已移除。`packages/design_system` 与 `packages/interop_bridge` 为 Dart workspace 包，`crates/` 为 Cargo workspace，应用平铺不改变这些模块边界。

## 唯一受控 fork：third_party/fvp

`third_party/fvp` 保存官方 fvp 0.39.1 源码与许可证。受控差异是五份原生 snapshot 回调的空结果保护、MDK 0.39.0 正式版本及官方归档 SHA 固定、Apple 精确版本约束，以及相应清单和回归；公开 Dart 播放器 API 保持上游接口。具体来源与补丁见 [CONNECT_PATCHES.md](../../third_party/fvp/CONNECT_PATCHES.md)。下载的 SDK、`.cxx` 与构建缓存不属于跟踪源码。

snapshot 失败允许空结果，未保护的原生解引用可直接终止主控进程，Dart 异常处理无法拦截；首帧、恢复和截图均依赖该路径。保留源码副本是为使这组修复及原生依赖可重复。取消 path override 的条件是替代上游版本具备同等保护与依赖约束，并通过对应回归，不能只删除目录。

## 构建与产物边界

被控执行产物集中在 `servers/`。scrcpy 使用一份固定版本、上游 Java 源不改动的标准脱糖构建；原始来源、构建输入、DEX 回填、许可及对应源码由 [vendor 清单与工具](../../servers/vendor/README.md)维护。`tool/check.sh` 核对 vendor 和 companion 产物，并执行旧平台兼容回归；功能下限及实际设备证据见[被控兼容边界](android-target-compatibility.md)。构建产物、来源归档和下载缓存不可混为同一清理对象。

普通 `lib/main.dart` 安装包与集成测试入口安装包分开标识；同一输出文件名被测试构建覆盖后，不能继续按普通应用产物交付。保留的交付包记录入口、架构、签名核验与摘要，历史摘要不代表当前文件。

调试结束清理过期 `build` 中间目录、测试资产、重复 APK 和已失效的 `.dart_tool/flutter_build` 输出。`.dart_tool/hooks_runner/shared`、Gradle 和固定 SDK 下载可作为复用缓存保留，不能与发布包混入 Git；清理前确认没有运行中的构建使用这些目录。

设备实验按本次创建的资源清理：测试进程、临时转发、夹具和目标模拟器均记录身份，既有主控及用户资源不随测试批次停止。截图与日志使用系统临时目录；重要结论在仓库文档中保留环境和结果，不能仅依靠临时文件存在。

## 根目录迁移阶段验证（历史产物）

根目录应用310项、桥接层131项、设计系统4项测试，完整Flutter analyze、分析插件契约、生成器4项Node回归、FRB与Dart生成一致性通过；255个Dart文件格式检查通过。工具8项回归、原生snapshot接缝、CMake依赖3项及driver验收契约通过。

普通`lib/main.dart`入口从根目录实际构建Android x64 debug通过，耗时59.98秒；无旧CMake路径错误。新产物`build/app/outputs/flutter-apk/app-debug.apk`共120,500,169字节，SHA256为`8b40368290e232b01c3cae6ed25b9c51dcd4f5e8318bd372afe9cf839d8d3cfa`。独立验证x86_64 Flutter/Rust ELF、ZIP完整性、16KB对齐与签名通过；debug证书仍为既有身份。JVM原生ownership3项、audio1项通过。构建及验证记录位于`/tmp/connect-root-build.log`、`/tmp/connect-root-apk-receipt.json`和`/tmp/connect-root-native-{ownership,audio}.log`。

该迁移阶段未对新包重复设备端到端部署，未在其他宿主构建；迁移前的AVD流程仍保留其原有时间及产物边界，不继承为新包运行结果。

## 2026-10-19 视觉修订回执（历史产物）

该阶段根应用[全量323个非hidden项](/tmp/connect-final-tests.jsonl)全部success；两处纯lint修复之后[3文件13项](/tmp/connect-final-pages.jsonl)通过并重拍96图；[analyze](/tmp/connect-final-analyze.log)无问题；[generate.py --check](/tmp/connect-final-generate.log)完整通过，含FRB Rust／Dart和build_runner。design_system 11项、Node生成器4项已有材质验证回执。真实[产品r2](/tmp/connect-final-product/result.json)及独立[GPU九场景](/tmp/connect-glass-material/result.json)各按自身契约通过；9张GPU图已逐张有限目视，不把工具visualAcceptanceComplete=false擅自改写成人工认证。按压形变、性能与原生等效仍有明确边界。

最终普通`lib/main.dart`Android-x64 debug包：[构建日志](/tmp/connect-final-main-build.log)、[回执](/tmp/connect-final-main-apk.json)，路径`build/app/outputs/flutter-apk/app-debug.apk`，147,239,422字节，SHA256 `b7c766abfc6a94a2166af30fa2a4572898deb297e4a6ae62c94b5973e91073e8`；ZIP、x64 ELF与apksigner验证通过。普通APK覆盖集成测试包安装并启动成功，观察pid11476、Impeller OpenGLES、未见UnhandledException；该启动观察不代替集成r2完整业务或四宿主运行。
