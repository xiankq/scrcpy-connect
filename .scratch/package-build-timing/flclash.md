# FlClash 的打包和发布流水线

对照了 `chen08209/FlClash` 的主分支快照 `afe7136`、三次成功的标签发布，以及 Interconnect Preview 3 的 GitHub Actions 记录。

## 工作流如何减少等待

- FlClash 在同一个标签工作流里运行检查和发布构建。版本任务一完成，Android、Windows、Linux、macOS 的七个矩阵任务就可以开始。Dart、插件、Go、Android 单测、Rust 等检查独立运行。上传等同一次运行的检查和矩阵都通过，再下载、合并与核验各平台产物。标签构建直接消费当前提交和版本，分支上的调试构建只做编译验证并丢弃 bundle。 [主分支检查和桌面调试](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.github/workflows/build.yaml#L112-L178) · [主分支发布矩阵及上传](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.github/workflows/build.yaml#L340-L555) · [v0.9.5-pre.1 固定版本工作流](https://github.com/chen08209/FlClash/blob/41b0583836e5883a3ed0b070a2890cf71b0b4800/.github/workflows/build.yaml#L373-L550)
- 标签构建关闭了 Go 和 Flutter 的 Actions 缓存，部分检查中 Rust 缓存的保存也受分支条件控制。发布的 Android job 仍使用 Gradle 初始化和 NDK 安装 action，公开的 job 耗时无法证明每个工具缓存的命中状态。 [缓存配置](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.github/workflows/build.yaml#L13-L21) · [发布工具配置](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.github/workflows/build.yaml#L435-L470) · [上游缓存说明](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.agents/commands.md#L478-L490)
- FlClash 的 Android 发布 job 默认用一次 `flutter build apk --split-per-abi` 生产 arm64-v8a、armeabi-v7a 和 x86_64。只有显式请求 universal 时才安排通用包构建，公开矩阵没有传入该选项。Android 的 Go 核心由 Gradle 的 `bindCore` 一次处理所需 ABI，桌面核心由 Flutter 构建 hook 编译。它使用 `dart tool/package.dart` 直接启动打包脚本，以免入口先为宿主触发原生 hook。只合并产物的上传任务显式禁用 Go 和 Rust 构建 hook。 [APK 参数和构建计划](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/tool/package.dart#L131-L201) · [默认 ABI](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/tool/package.dart#L251-L258) · [Android Core Build](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.agents/architecture.md#L1795-L1813) · [打包与上传入口](https://github.com/chen08209/FlClash/blob/afe7136002271fd64f098b154e7fff40be721eb8/.github/workflows/build.yaml#L488-L555)

## 公开运行耗时

运行时间来自 GitHub Actions API，表中使用北京时间。整条发布从运行创建计到完成，包含排队。Android 和上传任务按实际开始到完成计，包含各自的环境准备与产物处理。

| 标签 | 运行起止时间 | 整条发布 | Android 构建任务 | 上传任务 |
| --- | --- | --- | --- | --- |
| FlClash `v0.9.5-pre.1` | 2026-11-22 22:58:32–23:16:01 | [17 分 29 秒](https://github.com/chen08209/FlClash/actions/runs/45035698907) | [10 分 59 秒](https://github.com/chen08209/FlClash/actions/runs/45035698907/job/137248883699) | 1 分 48 秒 |
| FlClash `v0.9.5-rs.1` | 2026-11-23 17:39:46–18:07:50 | [28 分 04 秒](https://github.com/chen08209/FlClash/actions/runs/45149067664) | [24 分 18 秒](https://github.com/chen08209/FlClash/actions/runs/45149067664/job/137605617656) | 1 分 24 秒 |
| FlClash `v0.9.4` | 2026-11-19 14:54:43–15:31:15 | [36 分 32 秒](https://github.com/chen08209/FlClash/actions/runs/44475623932) | [15 分 15 秒](https://github.com/chen08209/FlClash/actions/runs/44475623932/job/135398612553) | 2 分 04 秒 |
| Interconnect `v0.1.0-preview.3` | 2026-11-24 21:58:53–22:20:47 | [21 分 54 秒](https://github.com/xiankq/scrcpy-connect/actions/runs/45409045447) | [19 分 51 秒](https://github.com/xiankq/scrcpy-connect/actions/runs/45409045447/job/138497929281) | 1 分 14 秒 |

`v0.9.5-rs.1` 使用另一条 Rust 核心构建路径。三次样本里，上传前最后完成的构建都是 Intel macOS。稳定版的任务约在创建运行八分钟后才开始。 [FlClash Rust 发布入口](https://github.com/chen08209/FlClash/blob/bdf83cab5e503f5dfd0aa1eedf848e0d07b7fcc8/.github/workflows/build.yaml#L369-L529) · [FlClash 稳定版运行图](https://github.com/chen08209/FlClash/actions/runs/44475623932)

Interconnect Preview 3 先运行主分支 CI，再启动标签发布。Android 已经通过一次 Gradle 构建交付三个 ABI 和通用包。借鉴 FlClash 的调度后，标签预检通过即可启动平台矩阵，公开发布前再读取同一提交的主分支 CI 结果。 [Interconnect 主分支 CI](https://github.com/xiankq/scrcpy-connect/actions/runs/45406462380) · [Interconnect 标签发布](https://github.com/xiankq/scrcpy-connect/actions/runs/45409045447)
