# 测试

这里是全仓测试规则的唯一出处。应用和能力包的测试放在各自模块的 `test/`，仓库工具的测试放在本目录。

## 什么值得测

每个测试都要能回答：「它能抓住哪种真实会发生的错误？」答不出来就不写。

- 公开能力接口的结果：成功、失败、取消、超时、迟到的结果被丢弃、断线后恢复。
- 资源由谁创建、何时释放：例如只读传输记录时不启动 ADB server，页面退出后租约归还、原生资源只释放一次。
- 用户能看到的页面行为：点了什么之后出现什么、进入哪个页面、哪个按钮可用或禁用、读屏标签、窗口变窄时换成哪种导航。
- 无障碍回退：减少动态、降低透明度、大字号时显示的是哪种控件、内容是否还能操作。
- 状态机的关键转换：连接尝试、会话、传输任务、配对。
- 解析外部输入：平台通道消息、ADB 和 shell 输出、协议回复、旧版本保存的文件、设置导入。
- 修 bug：先写一个能复现这个 bug 的测试，再修。测试名或注释写明它防的是哪个问题。

## 不写什么

- 纯转发、getter、常量、生成代码、`copyWith`、`==`/`hashCode`。
- 视觉数值：颜色、字号、字重、圆角、间距、模糊值、像素尺寸、动画中途的透明度。视觉对照 Ardot 设计稿截图核对。
  - 例外：某个布局 bug 修复后，可以保留复现它的最小断言，例如「加载圈在去掉标题栏后的内容区居中」。只断言这个关系，不顺带断言尺寸。
- 被测对象内部的调用顺序和次数。
  - 例外：次数或顺序本身就是对外承诺时可以断言，而且要断言在进程、设备或平台边界上。例如「同一查询只读一次手机」「导入时先冻结、再保存、再恢复」「原生资源只释放一次」。
- 只换了参数的重复测试：合并成一个表驱动测试，或者只留下行为不同的那几种情况。
- 只为测试加的生产代码：`@visibleForTesting` 只用来注入依赖。测试删掉后，只有它在用的生产代码一起删掉。

## 怎么写

- 测试名写行为，例如「断线后重连成功时恢复原画面」，不写「test reconnect 1」。
- 一个测试只验证一个行为，准备、动作、断言分三段写。
- 只在进程或平台边界替换依赖：平台通道、ADB、FFI、时钟。不要用假对象重写被测对象自己的逻辑。
  - 文件读写可以直接用 `Directory.systemTemp.createTemp` 建的真实临时目录，用 `addTearDown` 删除。
- 时间用 `fakeAsync`、`tester.pump(duration)` 或注入的计时器推进，不用真实等待。
  - `Future<void>.delayed(Duration.zero)` 和 `flushProviders` 只是让出一轮微任务，不算真实等待。
  - 必须跨真实 isolate 或端口的测试才用 `tester.runAsync`，例如 `app/test/router/mobile_remote_app_test.dart`。
- 两个以上测试文件用到的假对象和夹具放在 `app/test/support/`。已有：
  - `fixed_state.dart`：固定的设备列表、恢复状态、偏好，以及 `flushProviders`。
  - `video_events.dart`：视频会话事件。
- 假 Notifier 不能有公开的可变字段，`riverpod_lint` 的 `avoid_public_notifier_properties` 会报错。要记录调用就在构造时传回调，例如 `FixedDeviceList(onRefresh: () => refreshes++)`。
- 单个测试文件超过约 400 行时，先找重复的准备代码和测实现细节的用例。边界假对象本身就长的文件（如 `device_resources_test.dart`）不用硬拆。

## 怎么跑

在仓库根目录运行。提交前跑 `./scripts/check.sh`，它会跑下表除最后一行外的全部命令，另外做生成一致性和格式检查。

| 改了什么 | 命令 |
| --- | --- |
| 应用 | `cd app && flutter test --no-pub`；只跑一个文件：`flutter test --no-pub test/pages/files/files_page_test.dart` |
| 静态分析 | `flutter analyze --no-pub --fatal-infos`，要求 0 个问题 |
| 架构检查规则 | `dart --disable-dart-dev scripts/check_architecture.dart` 和 `dart --disable-dart-dev test/architecture_test.dart` |
| ADB 构建钩子 | `dart --disable-dart-dev packages/adb/test/native_hook_test.dart`：不用的原生库不应被构建或打包 |
| 媒体库 Apple 构建脚本 | `python3 -m unittest discover -s packages/media_codec/test -p '*_test.py'` |
| 发布脚本 | `python3 -m unittest discover -s test -p 'release_publish_test.py'` |
| Rust | `cargo test --workspace`。身份测试用官方 ADB/OpenSSL 固定向量，核对公钥编码、PEM 往返和授权签名 |
| 手机端文件助手 | `cargo test --manifest-path rust/adb/device_fs_helper/Cargo.toml`，只能在 Linux 编译，`check.sh` 不跑 |

macOS 的临时目录经过 `/var` 链接。单独跑涉及临时目录的测试前，先执行 `export TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)"`，和 `check.sh` 保持一致。

新增其他模块的测试时，把运行命令加进 `scripts/check.sh` 和上表。

## 手动核对

材质、动效和多窗口没有自动测试。改到这些地方时，在真机或原生宿主上按下面核对。

材质与动效：在设备上对照 Ardot 设计稿截图，分别打开系统的「减少动态」和「降低透明度」各看一遍。

多窗口：

1. 连接一台手机，打开它的「手机屏幕」，再从应用列表打开一个独立应用窗口。
   - Android：系统最近任务里出现两个任务，名称分别对应手机屏幕和该应用。
   - iPad：在台前调度或分屏中出现两个窗口。
   - iPhone：不开新窗口，在应用内进入页面，返回键回到上一页。
2. 再次打开第 1 步里的同一个窗口。系统聚焦原窗口，不新建窗口。
3. 用系统按钮关闭其中一个窗口。另一个窗口的画面继续更新，点击和键盘输入仍然有效，设备仍是已连接。
4. macOS 用 Flutter 3.50 调试时，先关闭远控子窗口再热重启。
