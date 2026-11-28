# interop-adb

异步 ADB 客户端，支持三种连接方式：移动端直连 TCP、已授权的 USB、桌面的官方 ADB server。

- 桌面的 `Client::connect_server` 固定使用 server 给出的 transport ID，失败时不会退回直连。
- 调用方负责 server 进程和身份（密钥）目录。
- 不包含：包管理、增量安装、与 5037 端口兼容的 server。

```rust,no_run
use interop_adb::{Client, ConnectOptions, Identity, OperationOptions};

# async fn example() -> interop_adb::Result<()> {
let identity = Identity::generate()?; // 持久化身份并在多次连接间复用。
let client = Client::connect_tcp("192.0.2.10:5555", ConnectOptions {
    identity: Some(identity),
    request_authorization: true, // 允许被控设备显示授权对话框。
    ..Default::default()
}).await?;
let output = client.shell("printf hello", 4096, OperationOptions::default()).await?;
assert_eq!(output.stdout, b"hello");
# Ok(())
# }
```

## 连接与资源

- `Client` 的所有克隆共用同一条多路复用连接。
- 放弃某个操作：drop 对应的 stream 或 sync 对象。等待连接关闭前，先保留并关闭外部持有的 writer。
- 取消只是给操作发信号，不代表资源已释放，也不代表远端已回滚。
- `is_closed()` 只表示已观察到连接关闭，不表示连接还能响应。
- `inbound_activity()` 的值只能在同一条连接上做相等比较。

## 协议细节

- 收到的数据在被消费后才确认（ACK）。
- 写入通过有界队列保持流内顺序。优先级不能越过已发出的帧或 ACK 额度。
- `burst_mode` 默认关闭，只有双方都支持延迟 ACK 时才能开。
- 旧协议 1.0.0：保留校验和与协商的载荷上限，包括 4 KiB 的对端。
- USB：保留帧头和载荷的边界，以及零长度包（ZLP）。
- `tcp` 选项只作用于 `connect_tcp`，不作用于调用方自己提供的 transport。keepalive 和 Android/Linux 的 TCP user timeout 默认关闭。
- 可选的读取追踪使用调用方提供的单调时钟（不能重入），不包含上游缓冲的时间。

## 服务

| API | 调用方需要知道的 |
| --- | --- |
| `shell`、`shell_session` | stdout/stderr 为二进制；v2 协议提供退出码、EOF 和 PTY 尺寸调整；旧协议合并输出，退出码未知 |
| `cmd`、`abb`、`abb_exec` | `cmd` 按 shell 规则加引号；`abb` 用 NUL 分隔 Binder 参数 |
| `open`、`exec`、`connect_socket` | 原始流；不支持只关闭 stdin |
| `reboot`、`tcpip`、`usb`、`service_response` | 只发请求、收响应；之后的重连由调用方处理 |
| `sync` | 流式传文件，路径按字节传，压缩需显式指定，不做 shell 展开 |
| `jdwp_processes`、`track_jdwp` | 返回有上限的 PID 快照；PID 不能当作应用身份 |

- 旧版 STAT 字段是 32 位，并且分不清"文件不存在"和"无权限"。V2 返回 `Error::RemoteErrno`。
- 压缩使用有界的 Brotli/LZ4/Zstd 工作线程。
- 中途放弃的 push 不会补发 DONE，可能在手机上留下写了一半的文件。
- 普通文件不要用 `dev:` 服务：不可轮询的文件描述符会让 adbd 的 epoll 注册失败而中止。

## Reverse

```rust,no_run
use interop_adb::{Client, OperationOptions, ReverseSocket};
# async fn example(client: &Client) -> interop_adb::Result<()> {
let binding = client.reverse_forward(
    &ReverseSocket::Tcp(0), "127.0.0.1:8080".parse().unwrap(), true,
    OperationOptions::default(),
).await?;
client.reverse_remove(&binding.device, OperationOptions::default()).await?;
# Ok(())
# }
```

- drop `ReverseBinding` 不会删除监听；要调用 `reverse_remove` 或断开连接。
- `reverse_remove_all` 删除手机上所有 reverse 监听，包括其他主机建立的。
- 官方 server 后端只删除自己在原 transport ID 上建立的映射。
- 类型化的 `host:forward` 不在 API 范围内。

## USB

- `usb` feature（默认开启）使用 nusb。
- Android 上 `usb::from_authorized_fd` 会复制一份已授权的文件描述符；Java 的 `UsbDeviceConnection` 必须在连接存续期间一直保留。
- 驱动和系统权限（entitlement）仍由各平台自己满足。iOS 只支持 TCP，不支持这个 USB 后端。

## TLS

- 连接 `_adb-tls-connect` 服务时，显式使用 `TlsPolicy::Required`。默认的 Optional 允许退回旧的明文连接。
- Required 会在暴露客户端身份前拒绝降级，但不校验（pin）服务器证书。
- 配对端口和连接端口不同。
- RustCrypto provider 需要显式开启实验选项，或由调用方提供一个经过审查的 provider。软件 RSA 的时序风险和 provider 成熟度需要在发布前评估。

## 设备发现

- 发现接口返回原始 mDNS 事件。是否信任、选哪个地址、何时重连、网络和多播权限都由调用方决定。
- 官方 server 使用 Required TLS 时，必须有一个与之匹配的已发现服务。
- 关闭授权请求的后台连接只会复用已经授权过的 transport。

## 测试

```sh
cargo test -p interop-adb
```

仓库检查（`scripts/check.sh`）还会用固定的 ADB 和 OpenSSL 测试向量运行身份集成测试 `cargo test -p interop-adb --test identity`，见[测试说明](../../test/README.md)。

## 协议来源

固定的 AOSP 协议源码：[`1cf2f017`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/)。
