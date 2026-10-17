# ADB 主机库、连接与身份研究

研究日期：2026-10-16。本文用于后续 grilling 和设计决策，不是实施方案，也不把完整产品改写成 MVP。

已确认范围：当前实现 Android 主控设备；被控设备不安装额外 APK、不 root，允许经 ADB 推送并临时执行自有扩展 JAR；支持同网、USB 和路由已经可达的跨网；支持多被控设备、多控制会话并行；Rust 库独立于 Flutter。未来 iOS、Windows、macOS 可使用各自必要的平台依赖，本次不声称已验证这些平台。

证据等级：**已证事实**来自下列固定源码或官方文档；**工程推论**是据此推导的产品/实现影响；**待 POC**不能凭源码阅读转为已支持。第三方 Rust 库以作者自己的源码为一手来源，其 README 的真机结果仍是作者自述，不是本项目验收结果。

## 1. 版本与来源快照

| 对象 | 本次实际核查基线 | 使用限制 |
| --- | --- | --- |
| Android SDK Platform Tools | 官方发布说明最新列出 **37.0.1，2026-07** | 不能把协议版本、adb server 版本和发行包版本当成同一数字 |
| AOSP ADB | `android17-release`，提交 `9084198a2d4b0f6a0f174260fb42da33485b684d`，2026-03-25 | 是可复核源码快照，**不冒充 37.0.1 二进制的精确构建提交** |
| AOSP ADB `main` | `1cf2f017d312f73b3dc53bda85ef2610e35a80e9`，2025-03-25 | 比上述 Android 17 分支旧；不能因 URL 含 `main` 就当作最新实现 |
| `adb_client` | crates.io `3.2.3`；仓库 HEAD `e52238305bbb01bf45dc96ac27108815c9b55d9f` | 以下源码结论按该提交；不假定已发布 crate 与 HEAD 所有文件完全一致 |
| `libadb` | crates.io `0.5.0`；HEAD `bc681df985967e083cdd7c02df45f942495393a5` | 0.x API；搜索/文档缓存有时仍返回 0.1.0，不能依赖 `latest` 摘要 |
| DroidMux | HEAD `9adeb6258166e9b88808bc6e67845c73763f070c`；workspace `0.1.0` | README 表示尚未发布到 crates.io；需固定提交 |
| `radb-core` | crates.io `1.0.0`；HEAD `1de15f1e51a6660f04110b7a7c42a5e5b6db4d29` | 与另一仓库的同名 `radb` 不混用 |

来源：[Platform Tools 发布说明](https://developer.android.com/tools/releases/platform-tools)、[AOSP 固定提交](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d)、[AOSP main 提交](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9)、[adb_client 元数据](https://crates.io/api/v1/crates/adb_client)、[libadb 元数据](https://crates.io/api/v1/crates/libadb)、[radb-core 元数据](https://crates.io/api/v1/crates/radb-core)。四个仓库提交用只读 `git ls-remote HEAD` 核对。

## 2. 已证事实：ADB 分层与设备连接

### 2.1 5037 host server 不是嵌入式主机库的必需品

官方桌面架构是 CLI client → 本机 adb server → 被控设备 adbd。5037 上的是 smart-socket 服务：例如 `host:devices`、选择 transport、host forward；它和 USB/TCP 上的 ADB 二进制 transport 协议是两层接口。Rust 库可以自己拥有 transport、认证、消息分发和服务流，直接连接 adbd；已有下述多个 Rust 库这样实现。它不必运行独立 `adb` 进程，也不必向 Flutter 暴露 5037。[官方架构](https://developer.android.com/tools/adb)、[AOSP services](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/services.md)、[DroidMux 架构边界](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/docs/compatibility.md)

“不依赖 adb server”也意味着设备发现、transport 注册、在线状态、密钥选择、重连、forward listener 生命周期等职责需要库或其上层承担。把 5037 兼容服务另做成可选适配层，和实现直接 ADB 主机核心，在源码上是可分离的工作；是否需要让外部 `adb` CLI 接入本产品，是产品兼容性决定。

### 2.2 CNXN / AUTH / STLS 不是一个简单请求响应

| 环节 | 核实的行为 | 实现影响 |
| --- | --- | --- |
| 帧 | 24 字节 header，6 个 little-endian `u32`；command、arg0、arg1、长度、校验、magic；随后 payload | 增量解析、长度上限、截断、magic 与非法状态都需处理 |
| CNXN | 协商版本、maxdata、设备 banner 与 `features=` | 设备声称支持的 feature 与本库实现的 feature 取交集，不能只检查设备列表 |
| AUTH | TOKEN → RSA SIGNATURE；已有密钥逐一失败后可提交 Android 编码公钥，引发被控设备授权 | 被动重连与主动申请授权应区分，防止重试不断弹确认框 |
| STLS | 先交换 ADB `STLS`，再对同一 TCP 流升级 TLS，之后继续读 ADB 数据 | TLS 握手成功还不足以把设备连接标为在线；AOSP 等后续 CNXN |
| OPEN / OKAY / WRTE / CLSE | 每个逻辑流有本地/远端 ID，数据包在同一 transport 上交错 | 不能让单个 `shell()` 独占读包器；需要集中分发与逐流状态 |

来源：[协议说明](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/protocol.md)、[实际握手与分发 adb.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、[host AUTH 实现](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/auth.cpp)。协议说明含旧数字，遇到差异以固定提交实现为准。

当前源码 `A_VERSION=0x01000001`，旧版本 `0x01000000`；`MAX_PAYLOAD_V1=4096`，当前本地上限 `MAX_PAYLOAD=1 MiB`，实际 negotiated maxdata 取对端与本地上限较小值。协商前 CNXN/AUTH payload 保持 4 KiB 以内。1.0.1 可跳过校验；旧字段常被文档叫 CRC，实际 `calculate_apacket_checksum()` 是字节求和，不是 CRC32。不能照旧协议文档里 256 KiB/CRC 的文字直接实现。[adb.h](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.h)、[checksum 与 CNXN](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、[maxdata 与发送校验](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)

### 2.3 Flow control 与 delayed_ack

经典模式逐流以 OKAY 驱动继续 WRTE；AOSP 的本地 socket 排队/消费决定何时确认。`delayed_ack` 改为逐流字节信用：OPEN.arg1 给初始接收额度，OKAY 携带 4 字节 **signed int32** 增量，WRTE 消耗额度；源码显式允许负增量。当前 AOSP 初始额度为 **32 MiB/流**，说明文档旧 trace 中的 1 MiB 不能当当前常量。两边协商支持后才能把 OPEN.arg1 改成非零。[delayed_ack 文档](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/delayed_ack.md)、[当前常量](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.h)、[OKAY 校验](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、[逐流信用与排队](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp)

ADB 协议没有为“触控比文件推送更优先”定义跨流服务等级。支持多路复用不等于已经实现公平调度；所有流仍共享 USB/TCP 带宽和底层写队列。对 CLSE 前已收尾部数据，AOSP 有保留待写队列后再销毁 socket 的路径，不能收到 close 就丢掉所有缓存。[asocket 的背压职责](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/asocket.md)、[sockets.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp)

### 2.4 Burst Mode复核与当前实现差距（2026-10-18）

只读子代理复核上述Android17固定修订，另核官方新文档：Burst Mode从Platform Tools
36.0.0提供，当前仍为默认关闭的实验功能，主机由`ADB_BURST_MODE=1`启用。wire feature
仍叫`delayed_ack`；主机主动宣告与设备支持取交集，不能根据对端banner直接启用。
[官方Burst说明](https://developer.android.com/tools/adb#burst_mode)、
[固定transport.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)。

双方一旦协商，普通和reverse OPEN的arg1均须给初始额度，首个及持续OKAY携带4字节
有符号增量；累计额度为signed64，允许零／负增量。额度大于零即可发一个完整WRTE，
扣除后可以暂时为负；接收预算应容纳最多额外一个包，消费者实际交付字节后才返还。
不能把它简化为“一个包一次ACK”。[固定adb.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、
[固定sockets.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp)。

后续已实施默认关闭的`ConnectOptions::burst_mode`，仅主动宣告且对端也支持时启用；
`Client::burst_mode()`报告实际状态。默认经典模式仍以OPEN.arg1=0、空OKAY、逐包ACK
和两包接收队列运行。外部连接器原`from_negotiated_transport`保留经典格式；新增
`from_negotiated_transport_with_burst`要求调用者确实主动宣告过feature，不能只看远端。
Burst实现正反向流、signed i32增量／i64累计信用、部分消费返还、取消与关闭尾包；
每流64KiB信用及一个max_payload超额接收，128MiB全连接保守预留涵盖队列元数据和
保留读缓冲，尾包消费者释放前不回收预留。未直接照搬桌面32MiB窗口。
[client.rs](../../crates/adb/src/client.rs)、[信用／预算](../../crates/adb/src/burst.rs)。

这些是可实施的协议差距，**尚未证明是当前约一秒视频等待的原因**。先采逐stream
payload读取、路由／消费、ACK实际写出及包大小／间隔；后续Burst A/B保持设备／画面／
码率，比较延迟和排队，而不只吞吐。回归需含classic及双方feature组合、正反向流、
部分读／合并信用、零／负／耗尽／恢复、非法长度与ID、慢流隔离、取消／尾包及TLS。
这些协议回归已纳入完整ADB测试72通过／13忽略，包括真实本地TCP反向桥及Rust TLS
协议端；不是实际USB／无线TLS adbd／全平台长稳通过。Core的`adbBurstMode`默认关闭、
只影响新连接；经典／Burst双AVD视频对照和范围见[视频记录](../implementation/video-performance.md)。

## 3. 已证事实：无线配对、密钥与连接安全

### 3.1 旧 TCP 与 Android 11+ 无线调试分开

旧 `adb tcpip <port>` 路径经已有授权通道开启 TCP listener，常用 5555，ADB transport 本身不加密；Android 11+ 无线调试另有 pairing listener 和 TLS connect listener。后者端口随机、可变化；配对端口不是投屏连接端口。两条路径即使最终承载相同 shell/sync 服务，认证与安全性也不同。[AOSP Wi-Fi 架构](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md)

现代配对的实际顺序如下，不能简化为“六位码 + 标准 TLS 证书校验”：

1. 配对双方先建立 **TLS 1.3**，AOSP 配对路径接受对端自签名证书。
2. 导出 **64 字节 TLS exporter**，label 是包含末尾 NUL 的 `adb-label\0`；把 exporter 追加到配对码字节，作为 PAKE password，绑定此 TLS 通道。
3. 执行 BoringSSL 风格 SPAKE2，角色名分别为包含 NUL 的 `adb pair client\0` 与 `adb pair server\0`。
4. 用 SPAKE2 结果经 HKDF-SHA256，info=`adb pairing_auth aes-128-gcm key`，导出 16 字节密钥；用 AES-128-GCM 与序号 nonce 交换 PeerInfo。
5. pairing frame 是 packed `u8 version + u8 type + u32 payload length`，长度转换为网络序；当前版本 1。PeerInfo 固定 8192 字节：type + data；主控发送 `ADB_RSA_PUB_KEY`，被控返回 `ADB_DEVICE_GUID`。

来源：[pairing_connection.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_connection/pairing_connection.cpp)、[PeerInfo 定义](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_connection/include/adb/pairing/pairing_connection.h)、[SPAKE2 调用](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_auth/pairing_auth.cpp)、[HKDF/GCM](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_auth/aes_128_gcm.cpp)、[TLS 版本/exporter](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/tls/tls_connection.cpp)。

**BoringSSL 的 SPAKE2 不能仅凭算法名替换为通用 Rust `spake2` crate。** 上游源码包含特定 Edwards25519 mask 点、password scalar 的 cofactor 兼容处理、长度前缀 transcript。DroidMux/libadb 都自实现这套变体而非直接使用通用 `spake2`。这证明 Rust 实现路线存在，尚不等于本项目可以省略密码学与跨实现互操作验证。[BoringSSL spake25519.cc](https://android.googlesource.com/platform/external/boringssl/+/refs/heads/android17-release/src/crypto/curve25519/spake25519.cc)、[DroidMux crypto.rs](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-pairing/src/crypto.rs)、[libadb spake2.rs](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/pairing/spake2.rs)

### 3.2 持久的是主控 RSA 身份，不是六位码或某一张 TLS 证书

AOSP host 生成 RSA-2048 密钥，私钥写 `~/.android/adbkey` 的 PEM 文件；认证公钥使用 Android 自有 little-endian RSA 编码（含 modulus、Montgomery 参数、exponent），base64 后加可读注释，**不是直接放 SPKI/PKCS#1 PEM**。传统 AUTH 用 `RSA_sign(NID_sha1, token, 20, ...)`：token 已是摘要形态，签名接口不会先再 SHA1 一次。配对和正式 TLS 用同一个持久 RSA 身份生成 X.509 证书；证书可重新生成。设备 TLS 验证把证书里的公钥与授权公钥比较，不把“相同证书字节”作为身份条件。[host auth/keygen](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/auth.cpp)、[RSA keygen](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/crypto/rsa_2048_key.cpp)、[X.509 生成](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/crypto/x509_generator.cpp)、[Android 公钥编码](https://android.googlesource.com/platform/system/core/+/refs/heads/android17-release/libcrypto_utils/android_pubkey.cpp)、[设备证书认证](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/auth.cpp)

被控设备主要维护 `/data/misc/adb/adb_keys` 与过期元数据；主控另存 `adb_known_hosts.pb` 的 **GUID**，用于无线自动连接筛选。这不是保存六位码，也不是 TLS server 证书 pin。重新生成主控私钥会失去旧授权身份；只恢复设备列表/GUID 不会恢复登录能力。[ADB keystore 文档](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/keystore.md)、[known-hosts 与配对持久化](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)

### 3.3 Android Keystore 不可导出密钥：协议可适配，默认接口不直接兼容

Android Keystore 允许 RSA-2048，并可把密钥留在 TEE/StrongBox 内；不可导出是其安全属性，不能从 key alias 获取私钥 PEM 再喂给 Rust。AOSP `TlsConnection::Create(cert, priv_key, fd)` 和本次检查的 Rust 库默认 identity builder 都接收私钥材料，不直接接收 Android Keystore handle。[Android Keystore](https://developer.android.com/privacy-and-security/keystore)、[AOSP TLS 构造](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/tls/tls_connection.cpp)、[DroidMux TLS identity](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-pairing/src/tls.rs)、[libadb TLS identity](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/tls/identity.rs)

可适配的证据与未完成工作应分开：

- **传统 AUTH：**AOSP AndroidKeyStore provider 有 `NONEwithRSA`/PKCS1 与 SHA1withRSA 等实现。依据 AUTH 语义，候选桥接是对正确 SHA1 DigestInfo 做 raw RSA PKCS1 签名；不能用 `SHA1withRSA.update(token)` 直接双重哈希。具体 key authorizations、`DIGEST_NONE` 在所选 TEE/StrongBox 上的可用性，需 POC。[AndroidKeyStoreRSASignatureSpi](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android17-release/keystore/java/android/security/keystore2/AndroidKeyStoreRSASignatureSpi.java)、[AUTH 签名实现](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/auth.cpp)
- **TLS：**rustls 有可自定义 `SigningKey`/`Signer` 的接口；可研究 JNI 调用 Keystore 签名，私钥不进入 Rust。需要覆盖 TLS 1.3 RSA-PSS 签名、客户端证书选择，以及自签证书生成/装载，不是实现传统 AUTH signer 后就自动完成。[rustls SigningKey](https://docs.rs/rustls/0.23.40/rustls/sign/trait.SigningKey.html)、[AndroidKeyStore 的 PSS 实现](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android17-release/keystore/java/android/security/keystore2/AndroidKeyStoreRSASignatureSpi.java)
- **已有库的扩展点：**libadb 有外部 authenticator 与自定义 rustls config 入口，但默认 TLS identity 仍导出 PKCS#8；DroidMux 默认也持有 PEM。不要把“支持外部 RSA 签名”误写为“配对/TLS 全链路已支持硬件不可导出密钥”。[libadb TLS config](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/tls/config.rs)、[libadb authenticator](https://github.com/tarigo/libadb/tree/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/base)、[DroidMux stored credential](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-pairing/src/credential.rs)

因此，“Rust 协议核心 + 平台 signer”与“软件 RSA 私钥 + Rust TLS”都是可以研究的组合。是否强制硬件不可导出、是否允许设备不支持时降级，属于产品安全策略，本文不代选。

### 3.4 撤销、备份与身份恢复

| 事件 | 已证事实 / 可直接推导的语义 |
| --- | --- |
| 被控端 Forget / revoke | 被控授权公钥被删除；adbd 的 key-removed 回调会踢掉使用该 key 的 transport。不是只删产品中的设备卡片 |
| 主控端删设备记录/GUID | 删除自动连接记录不会删除被控端授权；若私钥还在，被控仍可能接受它 |
| 主控备份私钥到另一安装 | ADB 看到相同公钥/签名能力；两个安装实际共享同一主控授权身份，不是各自独立授权 |
| 不可导出 key + 只恢复元数据 | 无法从 alias/GUID 重新构造旧私钥；应把设备列为需重新授权，而非已在线 |
| 复制文件式 PEM | Android Auto Backup 默认包含许多内部 files/shared preferences；必须明确云备份、设备迁移和手动导出的规则；`noBackupFilesDir` 是可用排除机制 |
| 长期未使用 | AOSP 有授权过期与时间戳维护；文档默认一周，不应承诺配对永不失效；实际值/开发者设置需读取或实测 |

来源：[设备撤销回调](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/auth.cpp)、[known-hosts](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)、[授权过期设计](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/keystore.md)、[Framework 授权管理](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android17-release/services/core/java/com/android/server/adb/AdbDebuggingManager.java)、[Auto Backup 文件范围](https://developer.android.com/identity/data/autobackup)。表中备份相同私钥的身份效果是对 ADB 验证逻辑的推论；没有在本次实际导出/恢复任何密钥。

### 3.5 “TLS 已加密”不等于“主控已强认证物理被控设备”

固定 AOSP 源码中，host `FdConnection::DoTlsHandshake()` 的服务端证书 verify callback 直接返回 1；设备端则核对主控证书的公钥是否已授权。配对阶段通过 code + TLS exporter 的 PAKE 绑定当前通道，但主控 known-hosts 之后仅保存 GUID。adbd 自身 TLS RSA key 在进程中懒生成，不能简单假定设备每次重启仍出示同一证书。[transport.cpp TLS 分支](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)、[daemon TLS key](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/auth.cpp)、[known-hosts 存 GUID](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)

**工程推论：**产品若需要强于 AOSP 默认的被控身份保证，需要单独设计与验证绑定机制；不能把 mDNS GUID、hostname、USB serial 或首次见到的临时 TLS 证书自动当成永久可信硬件身份。复制 AOSP 的接受自签行为，也不能删掉 TLS CertificateVerify 的签名验证或 pairing exporter 绑定；这些解决的是不同问题。

## 4. 已证事实：发现、地址和跨网

### 4.1 Wi-Fi 2.0 是发现/重连演进，不是新 NAT 穿透层

官方当前文档将 Android 17 + adb 37.0.0 与 Wi-Fi 2.0 关联，改进受信无线网络的自动连接；新 mDNS 输出包含 hostname、IPv6、serial、产品型号、SDK 版本、用户命名和 `mdns_service_version` 等信息。发布说明中，37.0.0 引入默认 libadbmdns，37.0.1 移除 openscreen 后端。这些版本升级不应写成“所有 Android 11+ 都具有相同行为”。[官方无线调试与 Wi-Fi 2.0](https://developer.android.com/tools/adb)、[37.0.x 发布说明](https://developer.android.com/tools/releases/platform-tools)

传统 mDNS service type 仍需辨别：`_adb._tcp`、`_adb-tls-pairing._tcp`、`_adb-tls-connect._tcp`。mDNS 找不到不等于设备离线；可能是 AP 隔离、接口选择、组播被过滤或服务尚未广告。手动地址可跳过发现，但不能跳过网络可达性、认证与随机端口变化。[AOSP Wi-Fi 架构](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md)、[mdns 接入](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/transport_mdns.cpp)

源码快照的 `ServiceInfo` 同时存 IPv4 与 IPv6 集合、hostname、TXT attributes；但该快照自动连接入口仍有 IPv4 存在性检查。旧 `adb_wifi.md` 还说 CLI 不输出 IPv6，而当前官方命令文档已经展示 IPv6。这是**源码/文档版本边界**，不是有根据地宣称最新发行版所有自动连接路径都已覆盖 IPv6。库自己的地址模型应支持 `[IPv6]:port` 和 link-local 的 interface scope，实际选址策略列入 POC。[ServiceInfo](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/discovered_services.h)、[自动连接入口](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/transport_mdns.cpp)、[当前 adb mdns 输出](https://developer.android.com/tools/adb)

### 4.2 已可达跨网与任意 NAT 分开

ADB 可对已可达 TCP endpoint 工作；例如具有路由的不同子网、用户已有 VPN、明确的端口映射。无线调试本身未提供 rendezvous、STUN/TURN、打洞或中继。Wi-Fi 2.0 没有把 mDNS 变成全球发现，也没有建立双方路由。`adb reverse` 依赖已经建立的 ADB transport，不能用来建立第一条不可达连接。[ADB TCP/无线说明](https://developer.android.com/tools/adb)、[reverse 服务定义](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/services.md)

**工程推论：**在当前“已可达跨网”的既定范围内，无需引入网关来证明基础可行性；同时不能承诺“打开无线调试即可穿越任意 NAT”。这不是缩减功能，而是把连接条件写进准确的能力支持级别。

### 4.3 Android 主控侧权限属于连接能力的一部分

Android USB 授权与被控 ADB 授权是两个独立环节。LAN 方面，官方当前规定 Android 16 保护是 opt-in；Android 17 上 target SDK 37+ 广泛 LAN 访问受 `ACCESS_LOCAL_NETWORK` 运行时权限控制，底层 Rust socket 同样受限；NSD 系统 picker 有针对选定服务的替代授权路径。不能以“核心用 Rust”绕过系统权限。[USB host 官方文档](https://developer.android.com/develop/connectivity/usb/host)、[Android 本地网络权限](https://developer.android.com/privacy-and-security/local-network-permission)

## 5. 已证事实：USB 与未来平台边界

### 5.1 Android UsbManager → 自定义 transport / libusb

Android USB host API 提供枚举、用户授权、接口与 endpoint、同步/异步传输；硬件必须支持 host/OTG。ADB 接口应按 interface class/subclass/protocol 与 bulk endpoints 识别，不能仅按整机 class 或 vendor 白名单判断。`UsbDeviceConnection.getFileDescriptor()` 官方说明可传给 native code；libusb 的 Android README 明确展示 UsbManager 授权后取得 FD、`LIBUSB_OPTION_NO_DEVICE_DISCOVERY`、`libusb_wrap_sys_device()` 的无 root 接入路径。[Android USB host](https://developer.android.com/develop/connectivity/usb/host)、[UsbDeviceConnection](https://developer.android.com/reference/android/hardware/usb/UsbDeviceConnection#getFileDescriptor())、[libusb Android README](https://github.com/libusb/libusb/blob/master/android/README)、[AOSP USB 探测](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/transport_usb.cpp)

因此，libusb 在无 root Android 可行；“直接使用桌面枚举/open_device 就能访问 `/dev/bus/usb`”则没有同等保证。JNI/平台层必须处理授权、插拔、FD 与 Java connection 生命周期；包装 borrowed FD、是否复制 FD、谁关闭它、如何中止待完成 I/O，都要跟所选 backend 核对，不能把一个整数长期缓存为永远有效的 USB 身份。[libusb Android 支持说明](https://github.com/libusb/libusb/wiki/Android)、[官方 native FD 接口](https://developer.android.com/reference/android/hardware/usb/UsbDeviceConnection#getFileDescriptor())

USB 也不能被完全当作无边界 TCP：ADB 的 host→device 传输需要在适当边界发送 zero-length packet；端点 `wMaxPacketSize` 的整倍数是重点场景。官方多个平台的 ZLP 修复说明这会影响可靠性。库若提供纯字节 transport 抽象，仍需把 USB transfer framing 放在正确 backend 中。[AOSP USB ZLP 说明](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/zero_length_packet.md)、[Platform Tools 修复记录](https://developer.android.com/tools/releases/platform-tools)

### 5.2 Windows / macOS / iPhone：保留路径，不宣称已经交付

- **Windows：**libusb 支持 WinUSB 等驱动；没有适配驱动的设备不能仅靠应用携带 DLL 就访问。WinUSB 还限制多进程并发使用。同一 ADB interface 被系统 adb server 占用时，嵌入式库需要明确报占用或选择 server 适配，不能任意抢占。官方 37.0.1 的 Windows 后端又引入 libadbusb；不能把某一种 backend 当跨平台永恒默认。[libusb Windows 官方说明](https://github.com/libusb/libusb/wiki/Windows)、[Platform Tools 发布说明](https://developer.android.com/tools/releases/platform-tools)
- **macOS：**libusb/nusb 或平台 USB 接入均有实现路径；官方 ADB 版本多次调整 USB backend 默认值，说明需要实测具体控制器和 OS。nusb 自述支持 Windows/macOS/Linux/WebUSB，不能据此推断其 Android UsbManager FD 桥已经具备。[nusb 官方仓库](https://github.com/kevinmehall/nusb)、[官方 ADB USB 后端说明](https://developer.android.com/tools/releases/platform-tools)
- **未来 iPhone 主控：**TCP/TLS 与指定 Bonjour 服务可沿系统网络 API 接入，需本地网络隐私授权；直接收发 multicast 另有 entitlement。USBDriverKit 的官方支持是 macOS 与 M 系列 iPadOS，并非普通 iPhone raw USB host 保证。iPhone USB 作为平台例外保留，不用 Rust portability 的表述掩盖它。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[Apple iPadOS 驱动要求](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)

## 6. 已证事实：服务层完整度

| 服务 | 必须辨别的协议/行为 | 直接源码 |
| --- | --- | --- |
| shell v1/v2 | v2 有 1 字节 ID + 4 字节长度，区分 stdin/stdout/stderr/exit、关闭 stdin、PTY resize；raw 与 PTY 影响二进制内容 | [shell_protocol.h](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/shell_protocol.h) |
| sync v1/v2 | STAT/LIST 元数据与 SEND/RECV 传输的 v2 feature 不同；64 位字段、symlink、DONE/FAIL 和分块边界不能混淆；DATA 上限 64 KiB 不是 transport maxdata | [file_sync_protocol.h](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/file_sync_protocol.h) |
| 压缩 | Brotli/LZ4/Zstd 由 sendrecv feature 和 flags 协商；不是设置 flag 后传未编码数据；错误与压缩流结束需处理 | [file_sync_client.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/file_sync_client.cpp) |
| forward | host listener 收到一条连接后开启对应 device service stream；无 5037 时库自己管理 listener、bind 地址、并发、端口分配与关闭 | [services 定义](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/services.md) |
| reverse | `reverse:forward/list-forward/killforward/...`；device 发起的反向 OPEN 需要主控正确接收、限域与路由，不能只会发请求 | [sockets.cpp 反向请求跟踪](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp) |
| install | 可用 streaming/abb_exec/cmd package 或 push 后 pm；split APK 有 create/write/commit/abandon；incremental/fastdeploy 是额外完整子协议，不是一个 shell 包装 | [adb_install.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_install.cpp)、[incremental 协议](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/incremental-install.md) |

这里研究安装服务是为了界定独立 ADB 库的“完整度”，不改变被控部署仅用临时 JAR、无额外 APK 的约束。ADB 服务能够执行的操作仍受被控 UID/SELinux/版本约束；重新实现 host 不会给量产 user build 增加 root、remount 或访问所有私有 app 数据的能力。[adbd root 机制](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/root.md)

### 6.1 取消、超时和重试并不由 ADB 自动保证

ADB stream 的通用结束消息是 CLSE，没有“撤销已产生远端副作用”的消息。AOSP shell v2 在协议 FD 消失时向子进程发 SIGHUP，但源码明确考虑子进程忽略信号的情况；这不能解释成所有后代进程、文件写入、短信、安装提交都会原子回滚。sync 中止后可能留下部分文件；安装 session 应显式 abandon，commit 之后需要另行定义结果查询。[shell_service.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/shell_service.cpp)、[sync 服务](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/file_sync_service.cpp)、[安装清理](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_install.cpp)

**工程推论：**连接、用户授权等待、配对、TLS、OPEN、读写空闲、总任务时长需要分别设置期限；不能给长期投屏/通知监听套相同短超时。设备连接重建后 local/remote stream ID 失效，旧控制会话必须重建或失败；不能把旧 future 接到新 transport 上。对于发送短信、拨号、删除文件、安装提交等非幂等操作，断线后自动重发可能重复执行，应返回“结果未知”并按任务类型查询，而不是一律重试。

## 7. 已证事实：Rust 库的复用价值与缺口

以下是源码能力清单，不是排序推荐；没有对这些库运行本项目的真机验收。

| 库 | 源码已证的复用价值 | 对本项目必须补查的边界 |
| --- | --- | --- |
| adb_client 3.2.3 / 固定 HEAD | 有 server client、直接 USB/TCP、AUTH、TCP STLS→rustls、mDNS；可参考大量 host 服务与命令编码 | `pair()` 位于 **server** commands，发送 `host:pair:`，不能当作无需 5037 的 SPAKE2 配对；同步可变接口与默认无限 read timeout 的模型，需评估多会话/取消；默认 TLS identity 从私钥文件加载 |
| libadb 0.5.0 / 固定 HEAD | `no_std + alloc` 核心、自定义 transport、读写 split、AUTH trait、shell v2、sync v1/v2；TLS/pairing feature 已有 Rust SPAKE2 变体、exporter 与 PeerInfo；可选 nusb/rusb，独立 C ABI | README 明确没有 DNS-SD；sync 层有 flags/raw DATA API不等于已提供完整自动压缩管线；默认 TLS identity 需要 PKCS#8；USB backend 说明 read future 不安全随意取消，要保留连接级 I/O 所有权 |
| DroidMux / 固定 HEAD | 分 crate 的 protocol/auth/transport/pairing/discovery/client/shell/sync/package/forward；逐流队列、delayed_ack、bounded I/O、压缩、安装 session 与重连路径；Rust SPAKE2 变体 | 0.1.0、未发布；Android 主控 UsbManager FD 接入、硬件 signer、Wi-Fi2 元数据/IPv6 scope、反向 OPEN 限制均需核查；作者报告的 Android14/Windows USB 覆盖不代表 Android11–17/所有 OEM 已验收 |
| radb-core 1.0.0 / 固定 HEAD | Tokio 直接 TCP、RSA、stream 分发、shell v1/v2、sync、server adapter，可参考 async API | Cargo/连接源码未看到 TLS/SPAKE2/USB 实现，不能拿“pure Rust ADB”名称推断 Android11+无线调试完整支持 |

证据：

- adb_client：[Cargo](https://github.com/cocool97/adb_client/blob/e52238305bbb01bf45dc96ac27108815c9b55d9f/adb_client/Cargo.toml)、[direct handshake](https://github.com/cocool97/adb_client/blob/e52238305bbb01bf45dc96ac27108815c9b55d9f/adb_client/src/message_devices/adb_message_device.rs)、[TCP TLS](https://github.com/cocool97/adb_client/blob/e52238305bbb01bf45dc96ac27108815c9b55d9f/adb_client/src/message_devices/tcp/tcp_transport.rs)、[server pair](https://github.com/cocool97/adb_client/blob/e52238305bbb01bf45dc96ac27108815c9b55d9f/adb_client/src/server/commands/pair.rs)。Context7 用于发现接口，关键结论回查源码。
- libadb：[README/限制](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/README.md)、[pairing client](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/pairing/client.rs)、[sync API](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/sync.rs)、[rusb 取消说明](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/src/transport/rusb.rs)。其 backend 的取消限制不能误写成 libusb 本身没有异步 cancellation API。
- DroidMux：[作者兼容性报告](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/docs/compatibility.md)、[pairing 源码](https://github.com/poapoauu/DroidMux/tree/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-pairing/src)、[USB 源码](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-transport-usb/src/lib.rs)、[压缩实现](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/crates/droidmux-sync/src/protocol.rs)。
- radb-core：[Cargo](https://github.com/theruansilva/radb/blob/1de15f1e51a6660f04110b7a7c42a5e5b6db4d29/Cargo.toml)、[source tree](https://github.com/theruansilva/radb/tree/1de15f1e51a6660f04110b7a7c42a5e5b6db4d29/src)。未发现的能力仅表示本次源码核查未证，不是断言作者永远不会支持。

### 7.1 纯 Rust 与 AOSP/BoringSSL FFI：事实边界

“纯 Rust”至少包含三个不同目标：本项目协议代码用 Rust、没有外部 adb 可执行文件、整个依赖图没有 native 库。前两个不自动推出第三个：上述 rustls 配置通常选择 ring；USB rusb 是 libusb FFI；DroidMux 的 Zstd 路径也有 native 依赖。平台授权和 Keystore signer 仍需 Android API/JNI。[DroidMux workspace Cargo](https://github.com/poapoauu/DroidMux/blob/9adeb6258166e9b88808bc6e67845c73763f070c/Cargo.toml)、[libadb Cargo](https://github.com/tarigo/libadb/blob/bc681df985967e083cdd7c02df45f942495393a5/libadb/Cargo.toml)、[rustls CryptoProvider](https://docs.rs/rustls/0.23.40/rustls/crypto/struct.CryptoProvider.html)

| 方案构件 | 已有事实 | 不能提前承诺 |
| --- | --- | --- |
| 自写/复用 Rust transport 与 services | 多个仓库已有独立实现；可独立于 Flutter 使用 | 不经互操作与负载测试就等同 AOSP 全部功能 |
| Rust 实现 BoringSSL SPAKE2 变体 | 已有具体源码、测试向量与算法差异说明 | 任意 `spake2` crate 均兼容，或自测两端成功即可证明对 AOSP 兼容 |
| 复用 AOSP pairing/BoringSSL | 官方 pairing API/实现可参考或包裹 | 无构建、ABI、许可证维护成本；默认接口直接支持不可导出 Keystore key |
| rustls 自定义 signer/config | 有正式接口；可选择/替换 crypto provider | 将 PEM 默认实现改为 alias 后自然可用；无需验证 RSA-PSS/证书选择 |
| Android UsbManager transport | 官方 API 与 native FD 接入路径存在 | Android 权限/JNI 可以全部消失，或未来 iPhone USB 自动兼容 |

**工程推论：**无需把整套 AOSP host server C++ 移植后才能有完整产品；也没有依据要求为“Rust”一词放弃已成熟的 crypto/USB 后端。选重写、fork、组合或有限 FFI，应以明确的所有权、互操作、维护和交付要求决定，本文不代替用户选库。

## 8. 工程推论：设备身份、连接、会话与并行

### 8.1 一个物理设备可能有多个 transport，不能按地址合并

AOSP 的 USB serial、TCP `host:port`、无线 GUID/service instance 和临时 `transport_id` 有不同用途。CNXN banner 提供 product/model/device/features，不能假定含可信唯一序列号。mDNS service 名还可能因冲突被追加后缀，AOSP known-hosts 专门有前缀匹配 workaround。已配对只说明某个主控身份获授权，不说明设备目前可达、TLS 已连接或某个控制会话正在运行。[banner 解析](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、[transport 注册/ID](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)、[service 名冲突处理](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)

由此推导的模型约束：

- 产品“被控设备”记录与当前“设备连接”分离；同一设备可同时有 USB/TLS 两个候选连接，一条设备连接又可承载多个控制会话/服务流。
- 同型号、同 IP、同用户命名或共享主控 RSA key 都不能独自证明是同一物理被控设备。
- 授权后可比较 USB serial、`getprop`、无线 GUID 等关联证据，但这些不是不可伪造的硬件证明。自动合并的证据门槛、冲突时用户确认和设备重置后的处理应明确。
- 允许临时 JAR 也不自动允许留下持久身份文件；若关联机制需要被控端持久随机标识，应明示其位置、清理与重置语义，再做 POC。

### 8.2 断线切换必须面对副作用边界

可以有“设备仍是同一台、设备连接已经更换、控制会话需要重建”的状态。ADB 不迁移 stream ID；scrcpy/扩展 JAR 是否能重新附着到现有远端进程，是各自协议的另一层问题。不能把 USB→Wi-Fi 自动切换等同零丢帧、触控无重复、文件自动续传与非幂等任务恰好一次执行。

### 8.3 并发预算是完整产品的交付指标

每设备应有独立认证、帧读写与流分发上下文；共享全局调度仍需限制 CPU/内存。按 AOSP 32 MiB/流信用，16 条流可允许约 512 MiB 在途额度；这不是一定预分配 512 MiB，但说明仅照抄窗口会放大手机内存风险。应分别量化最大连接数、每设备并行控制会话数、每流队列、全局缓存和文件后台吞吐时的输入延迟。限制资源不等于删除并行功能。

## 9. 尚需 POC：证据缺口与可测结果

本次未连接被控设备、未执行配对/安装/密钥导入、未编译候选库。下面所有项仍是未完成验证。

| ID | 验证问题 | 可评审的结果，而不是“看起来能用” |
| --- | --- | --- |
| P1 | Rust SPAKE2/TLS 与 AOSP 互操作 | Android11/13/16/17 至少覆盖已选系统矩阵；正确/错误/过期配对码、QR 路径、exporter label NUL、断线/取消、配对成功但 connect 失败分别记录 |
| P2 | 同一 Keystore RSA 身份走 USB AUTH、pairing、TLS | 不导出私钥；raw AUTH 与 AOSP 签名验证通过；TLS-PSS、客户端证书选择、自签证书生成/替换通过；TEE/StrongBox 不支持时给出精确原因 |
| P3 | 密钥恢复与撤销 | 只恢复设备元数据、仅用隔离夹具对照身份丢失、删主控记录、被控 Forget/global revoke、授权过期分别验证；不把“paired”冒充“online” |
| P4 | Android 无 root USB FD transport | UsbManager授权拒绝/重新授权、接口识别、borrowed FD关闭顺序、ZLP整倍数、短传输、插拔、设备重启、endpoint stall、后台恢复都无句柄/线程泄漏 |
| P5 | 混合 transport 的设备关联 | 同一设备 USB+TLS、两台同型号、DHCP换IP、mDNS重命名/冲突、刷机/重置、旧缓存与新设备碰撞，有确定关联/不合并规则 |
| P6 | IPv6 与 Wi-Fi2/旧版共存 | IPv4-only/IPv6-only/link-local scope、多网卡/热点/VPN、mDNS被禁手动地址、端口变动、新旧TXT属性缺失都能给可解释状态 |
| P7 | 多流公平性与关闭竞态 | 视频/音频/触控 + 大文件 + shell/通知；测 p95/p99 输入延迟、内存峰值；一个流慢消费/取消不拖死其他流；CLSE前最后数据与零长WRTE不丢 |
| P8 | 取消/超时及未知副作用 | 在header/payload/ACK/文件DONE/安装commit不同点断开；明确每个API何时返回取消、何时远端仍可能执行、何时允许重试 |
| P9 | sync/安装完整性 | v1/v2、64位文件、所有压缩、Unicode路径/symlink/权限失败、磁盘满、最后字节校验、split安装abandon与commit未知结果；不真的安装被控 helper APK |
| P10 | 最小依赖与独立库边界 | 不加载Flutter即可运行host核心/测试；Android app不依赖外部adb；native依赖与平台接口可单独枚举；四端核心／FRB最终链接／Flutter整包按编译契约留真实产物，未来端运行验证单列，不以静态依据代替编译 |

## 10. “完整 ADB 库”的验收清单

以下是完整度账本，用来避免以几个成功 shell 命令代替交付；不是分期裁功能。AOSP 仅在特定设备/构建上允许的服务，应暴露准确能力支持级别与失败原因，而不是伪造通用支持。

- [ ] **协议互操作**：1.0.0/1.0.1、校验启停、maxdata协商、帧分片/合并、未知命令/非法长度/ID、feature交集、AUTH多key、STLS/TLS1.3、delayed_ack开关/负credit。
- [ ] **发现和连接**：UsbManager与TCP、mDNS三种服务、手动IPv4/IPv6/hostname、接口scope、Wi-Fi2元数据与旧版缺失字段、地址更新与重连、已可达跨网。
- [ ] **身份与授权**：主控RSA持久化、Android公钥格式、pair/QR、私钥与证书生命周期、授权撤销/过期、被控身份关联、备份/导入/换机、日志和错误不泄露秘密。
- [ ] **流与资源**：并行OPEN、双向流、逐流/全局背压、优先级或公平规则、stream取消与transport关闭区分、半关闭、尾部数据、ID生命周期、资源上限与泄漏检查。
- [ ] **shell与通用服务**：v1/v2、PTY/raw、stdin关闭/resize/exit、exec/cmd/abb能力协商、logcat/track类长流、所有API支持期限与有界输出/streaming。
- [ ] **文件sync**：stat/lstat/list v1/v2、sendrecv v1/v2、Brotli/LZ4/Zstd、mtime/mode/symlink/目录行为、64位边界、权限/磁盘失败、进度、取消、完整性与重试语义。
- [ ] **forward/reverse**：TCP/localabstract等承诺endpoint类型、端口分配/no-rebind、listener与反向OPEN限域、并行、list/remove、断线清理、默认bind可见范围。
- [ ] **包管理接口**：single/split/multi-package session、streaming/legacy、commit/abandon、卸载与结果解析；incremental/fastdeploy是否属于声称的AOSP等价面必须登记，不能用名称掩盖遗漏。
- [ ] **完整度对照表**：固定AOSP版本的service/CLI动作逐项映射为库API、平台适配、设备不支持或未完成；root/remount/recovery等按设备能力如实处理。“未完成”不能标成“设备不支持”。
- [ ] **稳定性证据**：所选Android/OEM矩阵、USB/网络故障注入、多设备多会话长稳、性能和电量、重启/后台/恢复、密钥丢失与撤销；记录版本和可重现步骤。
- [ ] **库与发行**：Rust API不依赖Flutter，平台transport/signer接口明确；native依赖/许可证/锁定版本/更新策略、fuzz与互操作测试可运行；未来平台未验证项如实列出。

**工程推论：**工作量主要来自兼容性状态组合与可靠性语义，不是24字节header的代码量。现有源码能显著减少协议摸索、提供测试向量与模块参考，但目前没有证据支持“直接选某个crate就完成全部验收”，也没有根据认定必须从零重写每一层。没有需求指标和设备矩阵之前，按人周给精确工期会制造确定性。

## 11. 当前决定与工程研究前沿

Q26 已确定主控身份不自动备份迁移，Q29 已确定按中断原因和操作类型恢复，Q31 已确定保护已有重要活动；Q35 后常规产品默认由代理处理。不再把这些列为下一轮同义问题。

- **完整度：**依 ADR0002 将固定 AOSP 的 host／service 映射到 Rust API、条件能力与互操作用例。5037兼容、incremental／fastdeploy等的定位需形成有理由的边界账本，不将“完整”偷换为仅满足几个产品命令，也不擅自承诺复制所有 CLI。执行见任务01。
- **复用与纯度：**比较组合与有边界的 fork，记录许可、维护责任、feature 闭包及四端构建。优先尽量纯 Rust，不默认接受原生密码后端。任务02／03／19。
- **身份：**比较软件保护密钥与外部 signer，验证锁屏重连、AUTH／TLS参数、私钥生命周期、撤销与同设备多路径关联；换机仍重新授权。是否采用具体 signer 是证据驱动的实现选择，不让用户选密码算法。任务15。
- **恢复：**按主动停止、网络、系统回收、授权失效分类；ADB 流不可直接迁移，控制重建与文件能否恢复分别报告。未知副作用先核对，不重放。任务14。
- **并发：**在基准硬件和网络上给出资源预算、输入延迟与内存上限，优先保护已有通话和当前交互。任务16／20。
- **占用与冲突：**直接 USB 被其他主机占用时给出释放接口或切换已授权可达网络的路径；不将外部 adb server 作为基本条件。是否另提供5037适配由完整度账本说明。任务01／05。

任务均在[审计账本](../../.scratch/interop/requirements-audit.md)登记。当前仍没有库、构建或真机通过结果。
