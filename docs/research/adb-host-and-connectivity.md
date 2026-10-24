# ADB 连接、身份与平台依据

2026-10-16至18核查 AOSP `android17-release` 提交 `9084198a2d4b0f6a0f174260fb42da33485b684d`。它不是 Platform Tools 37.0.1 二进制的已证构建提交。当前库契约见[ADB 库](../../rust/adb/README.md)，产品取舍见[ADR](../adr/)。

## 协议与流控

smart socket（桌面 client→server）与二进制 transport（host→adbd）是两层协议。直接主机库可自行实现后者，桌面也可复用官方 server；两种路径的授权和生命周期能力不能混称。[services](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/services.md)

| 固定源码事实 | 实现影响 |
| --- | --- |
| 24字节帧头；版本、maxdata 与 feature 分别协商 | 1.0.0校验是字节求和；协商前CNXN/AUTH不超过4KiB，不能照旧文档的“CRC/256KiB”实现 |
| AUTH可多轮TOKEN/签名/公钥；STLS升级TLS后仍等待CNXN | 申请授权与被动重连分开，TLS握手成功不直接表示在线 |
| OPEN/WRTE/OKAY/CLSE按逐流ID复用同一transport | 单流慢消费或关闭不能占住整条设备读包器 |
| delayed_ack 的 OPEN给初始信用，OKAY是signed i32增量，累计信用可为负 | 仅双方宣告后启用，接收预算容纳超出信用的一个完整包；消费后返还额度 |
| AOSP信用为32MiB/流，未定义触控服务优先级 | 不直接照搬桌面窗口到手机；并发信用、排队与调度另有限额 |

来源：[adb.h](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.h)、[握手与分发](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/adb.cpp)、[transport](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)、[信用与关闭尾包](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/sockets.cpp)。本项目的具体队列和信用预算由源码维护，不在研究中复制第二份。

## 配对与长期身份

传统 `tcpip` 是未加密 ADB；Android11+无线调试使用独立配对和TLS连接端口。配对顺序是TLS1.3→导出64字节 exporter（`adb-label\0`）→配对码与exporter组成PAKE密码→BoringSSL变体SPAKE2→HKDF-SHA256/AES128-GCM交换PeerInfo。角色名末尾NUL、网络序长度和固定8192字节PeerInfo均属于互操作契约。[配对实现](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_connection/pairing_connection.cpp)、[认证算法](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/pairing_auth/pairing_auth.cpp)、[TLS](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/tls/tls_connection.cpp)

BoringSSL变体包含特定mask点、cofactor兼容与transcript格式，不能仅凭算法名换成通用 `spake2`。依赖方案见[纯Rust依赖](pure-rust-adb-dependencies.md)。

持久的是RSA-2048主控密钥，不是配对码或某张证书。Android公钥编码不是SPKI/PEM；传统AUTH签名接收已经形成的SHA1摘要，不能再次哈希。TLS证书可由同一RSA身份重建，设备核对授权公钥。[host AUTH](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/auth.cpp)、[证书生成](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/crypto/x509_generator.cpp)、[设备授权](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/daemon/auth.cpp)

| 操作 | 身份后果 |
| --- | --- |
| 被控Forget/revoke | 删除授权公钥并踢掉使用该key的transport |
| 主控删除设备/GUID | 不等于撤销被控授权 |
| 复制私钥到另一安装 | 两个安装共享同一授权身份 |
| 只恢复设备元数据 | 不恢复私钥和连接资格 |

AOSP known-hosts仅保存GUID；主控TLS服务端证书verify callback接受自签，设备端才核验主控授权。配对码/exporter绑定配对通道，但GUID、hostname和临时设备证书都不是永久物理身份pin。[known-hosts](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/adb_wifi.cpp)、[TLS握手](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/transport.cpp)、[授权期限](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/keystore.md)

## 平台与连接路径

Android Keystore不可导出key需要平台signer；默认接收PEM/PKCS8的库不能直接换成alias。传统AUTH与TLS1.3 RSA-PSS、自签证书及证书选择分别适配。[Keystore](https://developer.android.com/privacy-and-security/keystore)、[rustls SigningKey](https://docs.rs/rustls/0.23.40/rustls/sign/trait.SigningKey.html)

Android UsbManager授权后的FD可交native；授权、插拔、FD关闭与ZLP framing仍属平台责任。nusb/libusb支持桌面不自动提供Android FD或iPhone USB支持。[USB host](https://developer.android.com/develop/connectivity/usb/host)、[ZLP](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/zero_length_packet.md)、[libusb Android](https://github.com/libusb/libusb/blob/master/android/README)

`_adb._tcp`、`_adb-tls-pairing._tcp`、`_adb-tls-connect._tcp`不能混用。mDNS与Wi-Fi2负责发现/自动连接，不提供NAT穿透；reverse依赖已有transport。IPv6 link-local需保留接口scope，多网卡与组播受限要分别处理。[Wi-Fi架构](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/docs/dev/adb_wifi.md)、[发现结构](https://android.googlesource.com/platform/packages/modules/adb/+/9084198a2d4b0f6a0f174260fb42da33485b684d/client/discovered_services.h)

底层Rust socket同样受Android本地网络授权限制；iOS Bonjour、本地网络隐私和multicast entitlement也分别判断，普通iPhone没有通用USBDriverKit host保证。[Android网络权限](https://developer.android.com/privacy-and-security/local-network-permission)、[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[DriverKit](https://developer.apple.com/documentation/driverkit/creating-drivers-for-ipados)

CLSE取消通信不回滚已执行的远端动作；重建transport不迁移旧stream ID。shell v1退出码、SYNC元数据/压缩与非幂等提交的具体处理见[兼容研究](adb-android-compatibility.md)和[ADB接口](../../packages/adb/README.md)。
