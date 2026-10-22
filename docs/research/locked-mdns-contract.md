# mDNS版本语义与旧解析器修复

核对日期：2026-10-18。服务发现是无线连接的基础设施；研究版本、实际锁版与设备验证必须分别记录。本文比较旧锁版 0.17.2 与 0.21 系列的 API、网络语义和 HINFO 解析器修复。当前两个 Cargo 清单与 lockfile 已统一到 `=0.21.6`，包含下述解析器修复；构建边界见[工具链契约](../implementation/repository-tooling.md)。

## 旧0.17.2工程快照与上游差异

本次实施前，`crates/adb/Cargo.toml`使用`0.17`，Core测试依赖精确`=0.17.2`，Cargo.lock最终解析为0.17.2。此前[pure-rust依赖研究](pure-rust-adb-dependencies.md)讨论0.21.5，不是实际工程已使用该版本的证据。

| 契约 | 研究时0.17.2工程语义 | 差异／验收条件 |
| --- | --- | --- |
| feature闭包 | 默认reuseport、async、logging；项目未关闭默认项 | 0.18起移除reuseport feature；新版依赖树及四平台须重新核对 |
| 发现候选 | Core短时收集3秒，以fullname更新Resolved并删除Removed | 候选页不能因此宣称实时持续更新 |
| 长期发现 | Core只收已信任GUID的Connect服务，每GUID最多8条，端点变化推进generation | 库不发事件时，Core代际保护不能代替缺失的事件 |
| Goodbye | 0.17.2将响应TTL=0变为1秒，再经缓存过期发Removed | 支持撤销不等于即时删除；实际七项DNS-SD测试另有证据 |
| IPv6 scope | ScopedIpV6已有scope index，适配层保留到SocketAddrV6 | 不必为scope本身升级，实际连接仍未验 |
| Drop | stop_browse三个类型后发shutdown，忽略错误且不等终态 | 只是尽力关闭，不能称确认线程结束 |
| 断网 | ADB公开network_changed可重建；Core长期循环未接此入口 | 不能从库自动接口检测推导完整换网恢复 |

项目实现见[发现适配](../../crates/adb/src/wireless/discovery.rs)和[Core设备生命周期](../../crates/interop_core/src/device.rs)。旧发布的feature与API依据[0.17.2固定源码清单](https://github.com/keepsimple1/mdns-sd/blob/3d9ddbbd14d99a8e9a6d524fc6eb3a1ad5c57383/Cargo.toml)。

相关上游差异如下；未自动把新版本行为归给旧工程：

| 首次版本 | 与本项目有关的变更 |
| --- | --- |
| 0.18.0 | shutdown自动清理；名称转义；默认排除部分点对点接口；移除reuseport feature |
| 0.18.2 | 混合大小写hostname的A／AAAA刷新修复 |
| 0.19.0 | 接口地址移除补发Resolved；新接口查询处理；ScopedIpV4的Eq／Hash语义变化 |
| 0.20.0 | 可选serde格式变更；本工程未启用对应feature，也未直接序列化该类型 |
| 0.21.0 | 默认发包上限改变，IPv4／IPv6接收上限分开，属于实际网络行为变化 |
| 0.21.2 | 截断HINFO越界panic修复，上游新增解析器fuzz入口 |
| 0.21.4–0.21.5 | 未解析实例重查、未知记录处理、单调时钟／睡眠TTL与接口检查修复 |

版本归属以[固定0.21.5 changelog](https://github.com/keepsimple1/mdns-sd/blob/a25148c4d7adea836316dac2eca6c5bbdd79aa15/CHANGELOG.md)及具体提交为准，例如[shutdown清理](https://github.com/keepsimple1/mdns-sd/commit/8d24304)、[大小写刷新](https://github.com/keepsimple1/mdns-sd/commit/ec1e733)、[接口移除事件](https://github.com/keepsimple1/mdns-sd/commit/7daa1d4)。版本修复与本工程运行资格仍是不同层级。

## 旧0.17.2解析器的可达panic（已升级修复）

0.17.2发布源码`dns_parser.rs`允许HINFO记录在包尾声明RDLENGTH=0，随后读取字符长度时直接索引已经到达包尾的offset。上游明确修复同一问题并附回归样本，首个包含修复的发布版为[0.21.2](https://github.com/keepsimple1/mdns-sd/releases/tag/v0.21.2)，固定修复为[c65dd3c](https://github.com/keepsimple1/mdns-sd/commit/c65dd3c12ecb3ca685446a4eca4b924e5c2480f4)。当前0.21.6已包含修复，以下说明旧版可达性和升级理由。

**源码可达性事实**：UDP接收在服务名、配对身份与GUID判断之前解析整个DNS消息。能向启用接口的接收端口投递该畸形消息的局域网发送者可到达解析器，仍取决于平台网络权限、接口与防火墙。解析在独立mDNS_daemon线程，无catch_unwind；普通Result错误分支接不住该panic。[旧版接收路径](https://github.com/keepsimple1/mdns-sd/blob/3d9ddbbd14d99a8e9a6d524fc6eb3a1ad5c57383/src/service_daemon.rs)、[旧版解析器](https://github.com/keepsimple1/mdns-sd/blob/3d9ddbbd14d99a8e9a6d524fc6eb3a1ad5c57383/src/dns_parser.rs)。

**旧版工程影响的推断**：通常unwind会结束发现线程并关闭事件通道。当时Core长期发现只创建一次daemon，遇Closed不重建且不清理已有发现状态，因此可能长期停止端点更新与撤销。若最终宿主采用panic=abort，还可能退出进程；本workspace未设置该策略，各宿主最终配置未验。没有任意代码执行证据，也没有向共享网络投递该消息作攻击实验。

首个包含该修复的版本为 0.21.2；当前锁定版本与构建边界见[工具链契约](../implementation/repository-tooling.md)。解析器修复不等于完整 ADB fuzz 或发现生命周期已经通过。

## 验证边界

0.21.2保留项目使用的new／browse／stop_browse／shutdown／verify、ResolvedService和IPv6 scope访问方式；源码检查未发现必须重写适配层的API差异，编译结果仍须独立取得。flume、if-addrs、mio和socket-pktinfo有传递版本变化，需要核对普通／构建依赖与四平台。[修复发布清单](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/Cargo.toml)。

解析器回归应在离线临时副本运行上游已有HINFO用例，不能向共享宿主5353发送畸形包。真实UDP补充验收可以使用ServiceDaemon::new_with_port的独占测试高端口与loopback单播，先后证明正常消息到达和坏包后仍可处理新消息；只看进程退出码不足以判断独立线程存活。新版本另有unstable-fuzz-api离线入口，不必依赖nightly，但不能作为产品接口。[私有端口API](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/src/service_daemon.rs)、[离线fuzz入口](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/src/fuzz_api.rs)。

持续发现重建、混合大小写刷新、多接口移除、IPv6 scope、换网/睡眠TTL、关闭队列满与宿主权限应分别验证，不能从解析器修复推导全部通过；实际完成度由升级记录维护。上游fuzz也不替代本项目ADB协议fuzz。
