# 工具链与产物

## 工作区与生成

根Dart workspace共用锁文件和.dart_tool，应用在app运行，能力包测试在各包运行。纯宿主工具测试使用独立的 `tool/host/`，不触发Flutter原生hooks。生成入口见[tool/README](../../tool/README.md)。

- `protocol/commands.json` 生成应用Dart命令契约。
- 根FRB配置生成各能力包内部绑定，app只用公开接口。
- `designs/design.md` 经固定官方解析器生成设计token，Pencil变量映射同一来源。
- 生成文件随来源更新，使用各自 `--check` 检查漂移；不手改生成物。

依赖以锁文件整体解析；离线可用 `flutter pub get --offline --enforce-lockfile`。FRB检查复用 `.dart_tool/frb_check/` 的加锁镜像与Cargo缓存，不为每轮建立新编译树。

## 被控执行产物的共享打包

[servers](../../servers/README.md)维护固定源码、许可证、产物与manifest。修改来源后重建，再运行 `dart --disable-dart-dev servers/package.dart` 同步app/assets/servers。

应用校验并还原共享资源，把明确字节注入同库能力；Rust不另嵌一套JAR或读取应用assets。文件助手按被控ABI选择，主控ABI裁剪不影响共享资源。

## 原生媒体与官方 ADB

FFmpeg、dav1d及nv-codec-headers由媒体包锁定并保留对应源码与许可证。构建使用 `packages/media_codec/tool/build_ffmpeg.py`，缓存位于 `.dart_tool/media_codec/`；独立 `rust/media_codec/` workspace需单独format/test。

桌面ADB来源由 `packages/adb/third_party/platform-tools.lock.json` 固定，准备工具归ADB包；移动端不附带桌面adb。Linux监督器由目标Rust工具链构建嵌入，交叉编译须提供目标linker，不能复用宿主二进制。

Windows需Visual Studio C++桌面工作负载、Windows SDK和ATL。Flutter测试、设备构建与release准备共用插件注册文件，在同一工作区串行执行。

## 测试取舍

- 默认复用或替换现有用例。新增前说明具体失败、现有覆盖缺口及责任层；只有独立高风险缺口才净增。临时复现和TDD不自动变成常驻测试。
- 同一风险在责任层详细验证；桥接和页面只保留各自接线风险。相同分支的枚举、别名和入口选代表，不做参数笛卡尔积。
- 常量、简单透传、getter/copy、低风险布局、框架/第三方行为、生成源码外形不常驻。视觉用代表截图，生成物用漂移检查。
- 保留真实协议、损坏/越界、未知副作用、跨代所有权及清理重试；这些名称本身不豁免重复审查。
- `tool/check_test_budget.dart` 按 `tool/test_budget.json` 限制各域源码行数及注册标记，含新文件和专属fixture；Rust内嵌测试只计注册。`--report` 只读；超限先去重，确有新风险才说明理由并人工改预算。
- 静态标记不等于循环展开数；不合并无关场景、挤压格式或移出默认测试集来绕过预算。删除时一起清理孤立fixture与入口。

调试按改动范围运行检查，完整门禁用 `tool/check.sh`；`--android` 额外构建单ABI调试包。设备结果注明主控、被控、ABI与连接方式，环境跳过不计通过。

## 构建与产物边界

正式main、测试夹具和不同ABI的产物分别标识，测试构建覆盖过的包不能当作正式交付。截图、日志及独占样本放系统临时目录；结束后清理本次进程、转发、测试安装和过期产物，保留交付包与在用缓存。

受控源码、来源归档、许可证及JAR/helper属于输入。文档、分享与传输来源按[所有权](architecture.md#恢复持久化与媒体)回收，不按目录大小清理。长任务流式输出；需解析的进程输出有容量及期限，失败后确认自有子进程退出。
