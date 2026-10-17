# 实际mDNS锁版契约与解析器修复

核对日期：2026-10-18。服务发现是无线连接的基础设施；研究版本、实际锁版与设备验证必须分别记录。本报告针对A56中的mdns-sd差异，以及由此发现的A58；其余直接依赖仍须逐库完成契约核查。Context7没有收录该Rust库，本次使用作者固定源码、发布说明与本地锁版源码。

## 实际使用与版本差异

本次实施前，`crates/adb/Cargo.toml`使用`0.17`，Core测试依赖精确`=0.17.2`，Cargo.lock最终解析为0.17.2。此前[pure-rust依赖研究](pure-rust-adb-dependencies.md)讨论0.21.5，不是实际工程已使用该版本的证据。

| 契约 | 0.17.2实际使用语义 | 差异／验收条件 |
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

版本归属以[固定0.21.5 changelog](https://github.com/keepsimple1/mdns-sd/blob/a25148c4d7adea836316dac2eca6c5bbdd79aa15/CHANGELOG.md)及具体提交为准，例如[shutdown清理](https://github.com/keepsimple1/mdns-sd/commit/8d24304)、[大小写刷新](https://github.com/keepsimple1/mdns-sd/commit/ec1e733)、[接口移除事件](https://github.com/keepsimple1/mdns-sd/commit/7daa1d4)。这些修复仍需要本工程场景验证。

## A58：锁版解析器的可达panic

0.17.2发布源码`dns_parser.rs`允许HINFO记录在包尾声明RDLENGTH=0，随后读取字符长度时直接索引已经到达包尾的offset。上游明确修复同一问题并附回归样本，首个包含修复的发布版为[0.21.2](https://github.com/keepsimple1/mdns-sd/releases/tag/v0.21.2)，固定修复为[c65dd3c](https://github.com/keepsimple1/mdns-sd/commit/c65dd3c12ecb3ca685446a4eca4b924e5c2480f4)。它不是仅补文档即可关闭的版本差异。

**源码可达性事实**：UDP接收在服务名、配对身份与GUID判断之前解析整个DNS消息。能向启用接口的接收端口投递该畸形消息的局域网发送者可到达解析器，仍取决于平台网络权限、接口与防火墙。解析在独立mDNS_daemon线程，无catch_unwind；普通Result错误分支接不住该panic。[旧版接收路径](https://github.com/keepsimple1/mdns-sd/blob/3d9ddbbd14d99a8e9a6d524fc6eb3a1ad5c57383/src/service_daemon.rs)、[旧版解析器](https://github.com/keepsimple1/mdns-sd/blob/3d9ddbbd14d99a8e9a6d524fc6eb3a1ad5c57383/src/dns_parser.rs)。

**对项目影响的推断**：通常unwind会结束发现线程并关闭事件通道。Core现有长期发现只创建一次daemon，遇Closed不重建且不清理已有发现状态，因此可能长期停止端点更新与撤销。若最终宿主采用panic=abort，还可能退出进程；本workspace未设置该策略，各宿主最终配置未验。没有任意代码执行证据，也没有向共享网络投递该消息作攻击实验。

处理选择是包含修复的受支持发布版或受控回补；没有证据要求为这一个问题直接升级到研究中的最新版本。本批选择精确0.21.2并同步实际生产依赖与Core测试依赖，编译及回归结果需在实施记录另列。生产密码链、完整ADB fuzz和其他0.21.4+修复并不因此关闭。

## 验证边界

0.21.2保留项目使用的new／browse／stop_browse／shutdown／verify、ResolvedService和IPv6 scope访问方式；源码检查未发现必须重写适配层的API差异，编译结果仍须独立取得。flume、if-addrs、mio和socket-pktinfo有传递版本变化，需要核对普通／构建依赖与四平台。[修复发布清单](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/Cargo.toml)。

解析器回归应在离线临时副本运行上游已有HINFO用例，不能向共享宿主5353发送畸形包。真实UDP补充验收可以使用ServiceDaemon::new_with_port的独占测试高端口与loopback单播，先后证明正常消息到达和坏包后仍可处理新消息；只看进程退出码不足以判断独立线程存活。新版本另有unstable-fuzz-api离线入口，不必依赖nightly，但不能作为产品接口。[私有端口API](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/src/service_daemon.rs)、[离线fuzz入口](https://github.com/keepsimple1/mdns-sd/blob/v0.21.2/src/fuzz_api.rs)。

持续发现重建、混合大小写刷新、多接口移除、IPv6 scope、换网／睡眠TTL、关闭队列满与四宿主权限，仍是独立未验项；上游fuzz不替代本项目ADB协议fuzz。

## 本批实际处置结果

两处manifest及Cargo.lock已统一精确0.21.2，无需修改发现适配源码。传递变化为flume0.11.1→0.12.0、if-addrs0.14.0→0.15.0、socket-pktinfo0.3.2→0.4.1；移除旧Windows绑定，未升级无关直接依赖。四端依赖树解析通过；增量四包无build脚本，不引入cc／ring／aws-lc／libusb等vendored实现，必要系统调用仍为libc／windows-sys。该增量核对不等于整个依赖闭包已生产验收。

ADB／Core全部测试目标check --locked通过；已有discovery单测通过，独立/tmp源码副本运行上游原HINFO测试1通过／53 filtered。未修改registry，不声称本地执行过旧版坏包红测，也未给共享端口发坏包。

公开Runtime真实DNS-SD／TLS七项以新锁版串行77.36秒全部通过，`/tmp/connect-mdns-safe-reconnect.log`；验证备用端点、端口变化、goodbye、拒明文、迟到旧握手及ABA代际等既有场景。iOS／macOS／Windows核心cross-check分别4.24／4.18／8.26秒通过，`/tmp/connect-mdns-safe-core-cross-checks.log`，不代表这些宿主Flutter整包。最终综合门禁／Android三ABI及普通main在[总验收](../implementation/validation.md)另记，不能从旧锁版证据继承。
