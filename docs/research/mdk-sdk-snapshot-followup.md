# MDK snapshot 与异步解码后续核查

2026-10-18。问题：当前 renderer snapshot 的历史 native 崩溃是否已有明确修复版本，
以及能否通过升级 SDK 替代本项目已有的生命周期保护和显式异步解码配置。

## 当前版本与结论

官方最新正式 SDK 仍为 [MDK 0.39.0](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.39.0)，
发布于2026-09-30；[fvp 包 API](https://pub.dev/api/packages/fvp) 的最新版本为0.39.1，
发布时间2026-10-15。SDK 仓库核查到的 HEAD 为
`f038eb2c67141e6d71ef067f11a9a3c68dd5ab95`。没有找到晚于当前基线的正式 SDK
升级候选；本次未下载、构建或替换二进制。不能用“升级 latest”作为已经验证的修复。

## snapshot 的公开修复与问题

[固定版本变更记录](https://github.com/wang-bin/mdk-sdk/blob/f038eb2c67141e6d71ef067f11a9a3c68dd5ab95/Changelog.md)
记录了0.37的无视频帧 OpenGL snapshot 崩溃与时机修复、0.38的空回调清除、0.39的
snapshot JPEG 失败和 Android native-window GL context 释放后使用修复。这些均已在
当前版本或之前，公开说明未明确将本项目 renderer 中空 `std::function` 的 SIGABRT
对应到某个已修复问题。

[fvp #146](https://github.com/wang-bin/fvp/issues/146) 曾报告 `bad_function_call`，
2024-11-04关闭，报告者11-06表示未再复现；其展示的 `Player::onStateChanged` 栈不能
直接等同当前 renderer snapshot 栈。[MDK #117](https://github.com/wang-bin/mdk-sdk/issues/117)
中的连续 snapshot 崩溃仍开放，维护者要求日志和复现材料，没有给出已修复版本。
因此继续保留本项目已有 NULL／生命周期保护，历史 native 崩溃仍待最小复现和验证，
不把未找到对应修复解释为不存在修复。

## async 默认值不能替代实际回执

[9月11日 Decoders 文档](https://github.com/wang-bin/mdk-sdk/wiki/Decoders/54b14277b5de03f1d3f12ae126ac17f3b2f40151#amediacodec)
已描述 API28+ 的 AMediaCodec 异步默认值为1、Java 路径为0；
[10月12日版本](https://github.com/wang-bin/mdk-sdk/wiki/Decoders/cffa9514397313c46d60b98ea9def02d60e87afa#amediacodec)
继续保留这项说明。不能将文档日期说成 SDK 发布后才改变默认。AImage 异步 acquire
与 codec 的异步输入输出也是不同选项；前述变更记录中的0.36 AImage async、0.38
codec async buffer release／flush 修复均非当前新候选。

公开资料尚不能解释本机基线为何表现为同步路径；保留本项目已实际 A/B/A 验证的
`AMediaCodec:async=1`，实测范围见[异步解码记录](../implementation/android-decoder-async.md)。
不以文档默认值否定运行证据，也不据此声称所有真机路径均已验证。

## 检索范围

后台只读检索覆盖官方 SDK／fvp 变更记录、上述版本 API、相关 issues 以及 Decoders
Wiki；检索词包括 snapshot、bad_function_call、std::function、async、SIGABRT。
Context7 的 MDK 查询未返回匹配内容后转向官方来源；一次 API 限流后改用官方网页
核对关键 issue 和 Wiki。未穷举所有 Discussions，未联系上游，未测试新 SDK 二进制。
此笔记是升级候选核查，不是 native 崩溃已解决的验收证据。
