# interop-adb

Async ADB services over direct mobile TCP/authorized USB or the official desktop server. Desktop `Client::connect_server` pins transport IDs and never falls back to direct transport; the caller owns the server process and identity directory.

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

## Ownership and protocol

`Client` clones share one multiplexed connection. Drop streams and sync objects to abandon their work; retain and close external writers before awaiting connection shutdown. Cancellation signals an operation; it does not itself prove resource release or remote rollback.

Incoming data is acknowledged as consumed. Writes preserve stream order through bounded queues; priority cannot bypass already-sent frames or ACK credit. `burst_mode` defaults off and requires mutual delayed-ACK support. Legacy 1.0.0 retains checksums and negotiated payload bounds, including 4 KiB peers; USB preserves header/payload boundaries and ZLPs.

`is_closed()` is observed closure, not responsiveness. Compare `inbound_activity()` only for equality on the same connection. `tcp` options apply to `connect_tcp`, not supplied transports; keepalive and Android/Linux user timeout default off. Optional read tracing uses the caller's non-reentrant monotonic clock and excludes upstream buffering.

## Services

| API | Caller-visible contract |
| --- | --- |
| `shell`, `shell_session` | Binary stdout/stderr and v2 exit/EOF/PTY resize; legacy output is merged with unknown exit |
| `cmd`, `abb`, `abb_exec` | Shell quoting or Binder NUL-separated arguments |
| `open`, `exec`, `connect_socket` | Raw streams; no generic stdin half-close |
| `reboot`, `tcpip`, `usb`, `service_response` | Request/response only; caller handles reconnection |
| `sync` | Streaming files, byte paths and explicit compression; no shell expansion |
| `jdwp_processes`, `track_jdwp` | Bounded PID snapshots; PIDs are not app identities |

Legacy STAT has 32-bit fields and cannot distinguish missing from denied. V2 reports `Error::RemoteErrno`. Compression uses bounded Brotli/LZ4/Zstd workers. An abandoned push does not synthesize DONE and may leave a remote partial. `dev:` is unsuitable for ordinary files: non-pollable FDs can abort adbd's epoll registration.

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

Dropping `ReverseBinding` metadata does not remove the listener; remove it or disconnect. `reverse_remove_all` affects all device listeners, including other hosts. The official backend removes only its own mappings on the original transport ID; typed `host:forward` is outside the API.

## USB, TLS and discovery

The `usb` feature uses nusb. Android `usb::from_authorized_fd` duplicates an authorized FD; retain Java `UsbDeviceConnection` for the connection lifetime. Drivers and entitlements remain platform requirements; iOS supports TCP, not this USB backend.

For `_adb-tls-connect`, explicitly use `TlsPolicy::Required`; default Optional permits legacy plaintext. Required rejects downgrade before exposing client identity but does not add server certificate pinning. Pairing and connection ports differ. The RustCrypto provider requires explicit experimental opt-in or a reviewed caller-supplied provider; software-RSA timing and provider maturity need release assessment.

Discovery returns raw mDNS events. Trust, endpoint choice, reconnection and network/multicast permissions belong to callers. Official Required TLS needs a matching discovered service; authorization-disabled background connects reuse already authorized transports only.

## Tests and sources

```sh
cargo test -p interop-adb
INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  cargo test -p interop-adb --test reverse_adbd --test sync_adbd -- --ignored
```

Device tests need a dedicated authorized endpoint and clean only their temporary resources. BoringSSL interoperability tests require the helper documented in their source; ignored tests are not device evidence.

Fixed AOSP protocol source: [`1cf2f017`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/). Package management, incremental install and a 5037-compatible server are outside this crate.
