# 当前工程的 Dart 语言特性取舍

本地 SDK 为 Dart 3.13.7；`app/pubspec.yaml` 的下界为 3.13.5。以下特性都在当前语言版本内，不需要实验开关；能力接口收敛仍按 [当前规格](spec.md) 执行。生成器也须能解析所采用的语法。

## 已核实的特性

| 特性 | 最低语言版本 | 本项目适用范围 |
| --- | --- | --- |
| Records、解构与模式匹配 | 3.0 | 私有多值返回、临时投影、复合 key；命名字段表达容易混淆的同类型值。Record 是结构类型，按字段值比较；字段不能重新赋值，但所引用的集合并不会因此深度不可变。`typedef` 只增加别名，不增加领域类型身份。[Records](https://dart.dev/language/records)、[Patterns](https://dart.dev/language/patterns) |
| `switch` 表达式、逻辑或模式、`if-case`、`when` | 3.0 | 枚举与封闭结果的解释；在同一处匹配、提取和分支。针对已知枚举/封闭类型，业务须逐项处理时不写兜底分支，让新增状态触发编译错误。[Branches](https://dart.dev/language/branches) |
| `sealed`、`final`、`abstract interface` | 3.0 | 分别表示封闭结果、不可被库外继承/实现的实现类、可替换的纯契约；根据实际扩展要求选择。[Class modifiers](https://dart.dev/language/class-modifiers)、[Effective Dart: Design](https://dart.dev/effective-dart/design) |
| Null-aware collection elements | 3.8 | 适配入口输出真正可缺省的值，例如 `{'identity': ?identity}`；表达式求值为 null 时不插入该项。显式 null 表示清除/继承时不能改用这个语法。[Collections](https://dart.dev/language/collections#null-aware-elements) |
| Dot shorthands | 3.10 | 上下文类型清楚的枚举赋值和 switch 分支，如 `.connected`；推断不清楚或跨领域容易误读时保留类型名。[Dot shorthands](https://dart.dev/language/dot-shorthands) |
| 私有命名 initializing formals | 3.12 | `required this._dependency` 直接初始化私有字段，调用方仍写 `dependency:`；无需手写同名转存。[Constructors](https://dart.dev/language/constructors#private-named-parameters) |
| Primary constructors、concise constructors | 3.13 | 少量字段的普通类可在声明头表达字段和构造参数；类体也可用 `new` / `new named`。只减少声明重复，不提供值相等、copyWith、序列化或生命周期管理。[Primary constructors](https://dart.dev/language/primary-constructors)、[Concise constructor syntax](https://dart.dev/language/constructors#concise-constructor-syntax) |
| Constructor tear-offs | 2.15 | 参数签名完全一致时传 `Type.new` 或 `Type.fromJson`；不增加单纯转发的闭包。这是已成熟的特性，不是 3.13 新增。[Constructors](https://dart.dev/language/constructors#constructor-tear-offs) |

版本演进另见 [Dart language evolution](https://dart.dev/resources/language/evolution)，SDK 的完整变更以 [官方 CHANGELOG](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md) 为准。

## 候选位置

这些是对当前代码的判断，不代表官方要求。优先处理表达含糊或丢失类型信息的位置；已有清楚代码无需逐文件更换拼写。

| 位置 | 建议与边界 |
| --- | --- |
| `app/lib/widgets/device_labels.dart` | 设备快照类型化后直接按 `DeviceConnectionStatus` 匹配，使用逻辑或模式表达连接中的几个状态，替换字符串列表成员判断。设备状态文案可穷尽处理；其他领域共用的字符串文案另行保留。 |
| `app/lib/core/content/content_preview.dart` | JPEG 尺寸返回值从 `(int, int)` 改为 `({int width, int height})`，读取处使用字段名或解构。宽高都是 int，命名可避免 `$1/$2` 的歧义；校验与取消时序保持原状。 |
| `app/lib/core/media/video_recovery.dart` | `_dimensionFrames` 的 `(generation, frames)` 改为命名 Record，匹配同一 generation 后取 frames；保持旧解码器不能抬高新解码器栅栏的规则。 |
| `app/lib/core/content/content_cache.dart` | `_CacheFile` 只有 path、bytes、modified，可用私有命名 Record。`_Snapshot` 带统计行为，`_Reservation` 含可变基线，保留 class；它们如需减少构造声明可考虑 primary constructor。 |
| `app/lib/core/devices/device_connection_pool.dart` | `_invalidate` 已返回命名 Record，消费者可按使用字段解构，避免把 slot/generation/取消报告拆成独立来源。`_Attempt`、`_Retirement`、`_DeviceSlot` 持有取消和清理进度，继续保留有身份的可变 class。 |
| `app/lib/core/devices/device_details_reader.dart` | 屏幕尺寸、磁盘总量/可用量的匿名二元值可命名，减少 `$1/$2`；现有属性映射循环的 Record 解构是合适用法。 |
| `app/lib/core/files/file_stamp.dart` | `identity` 的 null 缺省输出可用 null-aware map value；`kind` 可按文件类型位的 switch 表达式计算。FileStamp 有值语义及序列化，继续保留命名模型。 |
| `app/lib/core/media/device_audio_service.dart` | 原生会话信息中 processId/processStarted 的条件输出可用 null-aware map value；只替换原本明确省略 null 的项。 |

## 不应机械替换的部分

- Freezed factory 的非必填、非空字段继续用 `@Default(...)` 声明默认值；普通 Dart 参数的 `= value` 不能替代生成器要求。已用当前项目的生成器验证。

- 公共领域模型（如设备快照、剪贴板目标、偏好）仍使用命名 class / Freezed。需要领域身份、方法、不可变集合、copyWith、联合变体或 JSON 时，Record 本身不能替代这些规则。私有、简短、没有独立约束的组合才优先 Record。
- 原生/伴生协议与持久化输入可以用 Map/List pattern 一次匹配和提取，但 Map pattern 允许额外键；仍须保留原来拒绝未知键、长度限额、错误码及类型校验的规则。不能借语法优化放宽适配入口。
- `(futureA, futureB).wait` 能保留异构返回类型，但失败会产生 `ParallelWaitError`；现有 `Future.wait` 的清理/恢复路径不能直接替换，须核对异常处理及所有任务实际退出的责任。[FutureRecord2.wait](https://api.dart.dev/dart-async/FutureRecord2/wait.html)
- 不对 `DeviceConnection`、取消令牌、退休记录及资源所有者引入结构相等。精确句柄与实例身份是归属校验的一部分；这些类可减少构造样板，但仍保留身份和清理责任。
