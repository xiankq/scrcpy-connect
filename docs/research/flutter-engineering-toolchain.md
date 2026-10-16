# Flutter生成链与状态所有权复核

2026-10-17。用户要求实际使用路由、状态生成器及推荐lint。以下核对发布包与官方源码；依赖解析、生成与测试结果来自本工作区，Android运行另行验证。

## 兼容版本

| 包 | 固定版本/当前锁定 | 职责 |
| --- | --- | --- |
| go_router / go_router_builder | 18.1.0 / 4.5.0 | typed routes及StatefulShellRoute |
| hooks_riverpod | 3.4.3 | provider运行时 |
| riverpod_annotation / generator | 4.0.7 / 4.0.9 | 生成Notifier/DI |
| build_runner | 2.16.2 | workspace生成 |
| riverpod_lint | 3.1.9 | 根analyzer插件 |
| flutter_lints | 6.0.0 | Flutter与Dart推荐规则 |

annotation/generator与运行时的主版本无需相同，依据实际发布约束。当前runner 2.17.1要求build 5，而上述两个生成器要求build<5；2.17.0已撤回。本组合已实际pub get成功，解出build4.0.11、analyzer14.5、source_gen4.3.1，不人为覆盖传递依赖。[annotation元数据](https://pub.dev/api/packages/riverpod_annotation/versions/4.0.7)、[generator元数据](https://pub.dev/api/packages/riverpod_generator/versions/4.0.9)、[builder元数据](https://pub.dev/api/packages/go_router_builder/versions/4.5.0)、[runner变更](https://pub.dev/packages/build_runner/changelog)。

## 路由与状态

builder原生支持typed stateful shell。实体通过ID重新查询；远控临时launch intent只表达用户本次主动打开，不序列化为恢复权限。生成代码不能替代现有输入释放、迟到启动清理或source/session身份检查。[固定版本示例](https://github.com/flutter/packages/blob/go_router_builder-v4.5.0/packages/go_router_builder/example/lib/stateful_shell_route_example.dart)、[恢复配置](https://pub.dev/documentation/go_router/latest/topics/State%20restoration-topic.html)。

Riverpod并非强制代码生成；官方建议已有其他生成链时采用，本项目已有路由生成，统一管线合理。整改实际收益应是不可变state、select订阅、显式命令和所有权；生成器本身不会完成这些工作。keepAlive不防依赖变化重算，router不能依赖整个app snapshot。[官方生成口径](https://riverpod.dev/docs/concepts/about_code_generation)、[销毁生命周期](https://riverpod.dev/docs/concepts2/auto_dispose)。

当前AppController已实质改为生成Notifier，AppState深冻结；页面选择性观察，DI与剪贴板协调器由生成provider管理。原router已有memoization，不能将迁移前问题误写成每事件重造router。全局JSON协议仍是Dart/Rust边界，typed router不等于FRB业务载荷已经schema化。

## Lint实际执行

3.1.9采用原生analysis_server_plugin，要求Dart>=3.13；不再装custom_lint。插件只在workspace根配置，成员analysis_options继承根；启用strict-casts、strict-inference、strict-raw-types，手写源不整体豁免。插件通过独立synthetic package解析，其传递依赖不由根pubspec.lock固定，因此固定SDK与插件版本，额外执行故意违规的negative smoke。[Riverpod变更](https://pub.dev/packages/riverpod_lint/changelog)、[固定SDK插件指南](https://github.com/dart-lang/sdk/blob/3.13.5/pkg/analysis_server_plugin/doc/using_plugins.md)、[Dart分析配置](https://dart.dev/tools/analysis)。

实际烟测在非隐藏临时目录创建公开getter的Notifier，确认分析器报avoid_public_notifier_properties，并自动删除。成员继承根与非隐藏目录联合修正后通过；未单独证明二者各自必要。仅有No issues found不能证明插件生效。

未发现flutter_hooks第一方独立lint；第三方flutter_hooks_lint1.4.0实际发布包仍依analyzer<9，与当前链冲突，不装入项目。hooks规则仍通过基础lint、代码审查和生命周期测试保证。[第一方仓库](https://github.com/rrousselGit/flutter_hooks)、[hooks规则](https://pub.dev/packages/flutter_hooks)、[第三方实际归档](https://pub.dev/api/archives/flutter_hooks_lint-1.4.0.tar.gz)。

## 可复现命令与证据

runner2.16支持workspace及不写输出的only-check，旧delete-conflicting-outputs已移除。脚本从直接依赖runner的app发起workspace构建；提交.g.dart和根锁文件，忽略.dart_tool/build。CI先enforce-lockfile，再检查生成、分析、违规烟测、测试和设计lint。workspace中所有成员dev dependencies共同解析；开发依赖不会成为原生产物，仍可能堵住四端依赖解析。[runner变更](https://pub.dev/packages/build_runner/changelog)、[锁文件检查](https://dart.dev/tools/pub/cmd/pub-get#enforce-lockfile)、[workspace](https://dart.dev/tools/pub/workspaces)。

本轮78/78 widget通过，app严格分析无诊断，workspace only-check退出0，插件negative smoke检出预期违规。重构后实际Android产品页五codec、HOME返回与旋转已取得对应运行证据，见[首帧回归](scrcpy-first-frame-and-latency.md)。以上不代表跨端链接、音频迁移或进程重建已验收；共享层迁移仍按能力重新验证。
