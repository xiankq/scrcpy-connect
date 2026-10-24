# interop-adb

Asynchronous ADB services with two transport backends:

- Mobile connects directly to adbd over TCP or authorized USB.
- Desktop selects `ConnectOptions::adb_server` or `Client::connect_server` and uses the bundled official server's smart socket. The host owns its process, binaries and identity directory. Device authentication and USB stay with official adb; failures never fall back to direct transport.

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

## Ownership and flow control

`Client` clones share a connection and multiplex independent streams. Incoming data is acknowledged as consumed. Dropping a stream closes it; dropping all connection/stream owners stops transport tasks. Operations carry deadlines and cancellation. Interrupted writes or failed sync operations close the affected stream; abandon an in-progress sync operation by dropping its sync object.

Direct transport uses bounded queues: 64 ordinary data frames, 16 priority frames and 128 reader-generated control responses. `AdbStream::set_write_priority` selects the priority writer; ACKs/credit and same-stream ordering still apply. Control responses do not wait for data capacity; overflow closes the connection. Ordered close drains accepted frames, and closed routes reject late OPEN/WRTE. `max_payload` exposes the negotiated limit for batching complete fields, without bypassing flow control.

Legacy ADB 1.0.0 retains checksums and its advertised payload limit, including 4 KiB peers. Modern negotiated frames omit payload checksums. USB preserves header/payload boundaries and required zero-length packets. Explicit authorization may reoffer the same key while a booting daemon's framework becomes ready, within the connection deadline.

`ConnectOptions::burst_mode` defaults to false. Mutual `delayed_ack` support enables experimental byte-credit flow control; `Client::burst_mode()` reports negotiation. Empty OKAY replies are idempotent and do not accumulate future readiness. External connectors may use `from_negotiated_transport_with_burst` only after advertising the feature; the ordinary constructor uses classic framing. Existing connections are not renegotiated when preferences change.

Burst streams reserve a 64 KiB receive window, one maximum-payload overshoot and bounded metadata; a connection caps reservations at 128 MiB. Reservations survive close until the tail is consumed or dropped. Partial reads return byte credit; signed deltas may temporarily make sender credit negative.

## Connection health and diagnostics

`ConnectOptions::tcp` defaults to nodelay, with keepalive and Android/Linux TCP user timeout disabled. These options affect only `connect_tcp`, not caller-supplied transports.

`is_closed()` reports observed closure, not remote responsiveness. Compare `inbound_activity()` only for equality on the same connection: it advances on nonempty reads, including partial frames, and is neither a timestamp nor validated-frame count. Application health probes belong to callers.

`AdbStream::set_read_trace_clock` enables constant-space diagnostics using a quick, non-reentrant monotonic microsecond clock. `read_trace()` retains the latest WRTE's payload-read start/completion, routing and first consumption in that clock domain. Partial reads retain the receipt sequence; several service packets may share it. Receipt timing excludes buffering before the ADB header. Replacing/disabling the clock discards stale metadata without discarding data; an in-flight call may finish on the old clock. With no subscribers, new WRTEs sample no clock and take no additional route lock.

## Services

| API | Contract |
| --- | --- |
| `shell` | Byte-preserving stdout/stderr; shell_v2 exit status, absent on legacy shell |
| `shell_session` | Raw/PTY stdin, close-stdin, resize and cancellation-safe incremental output |
| `cmd`, `abb`, `abb_exec` | Quoted shell arguments or Binder NUL-separated arguments |
| `open`, `exec`, `connect_socket`, `reboot` | Raw streams, typed TCP/local/JDWP/vsock destinations and reboot targets |
| `tcpip`, `usb`, `service_response` | Original bounded response bytes; no reconnect, record update or inferred success |
| `sync` | Bounded streaming push/pull, 64-bit stat/list v2 and legacy fallbacks; byte paths, never shell interpolation |
| `jdwp_processes`, `track_jdwp` | Initial or incremental length-framed updates, including empty lists; partial frames survive dropped reads. PIDs are not stable application identities |

`lstat` uses no-follow LST2 or legacy STAT. Legacy metadata has 32-bit size/time and cannot distinguish absence from permission failure. V2 errno replies use `Error::RemoteErrno { operation, errno }`. Android SELinux may deny metadata access to shell-created symlinks; such errors remain permission failures.

`push_compressed`/`pull_compressed` use bounded Brotli/LZ4/Zstd workers. Push batches SEND/SND2, DATA and DONE into at most one negotiated-payload buffer and flushes before reading the reply; each DATA record remains at most 64 KiB. Other requests and interactive streams do not wait for batching. Abandonment discards pending bytes without synthesizing DONE.

Generic `open` permits advanced services, but `dev:` is not a general file API: non-pollable descriptors can abort adbd's epoll registration. Use sync for files and low-level serial services only with known pollable devices and platform support.

## Reverse connections

`reverse_forward` creates a device TCP/Unix listener and bridges it to an explicit host TCP address. Port zero returns an allocated device port. Rebind/no-rebind, list and removal use `reverse:`; direct device OPENs are accepted only for random service names registered by this client. Both bridge directions progress under backpressure.

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

Dropping `ReverseBinding` metadata does not remove the listener; remove it explicitly or disconnect. `reverse_remove_all` affects adbd's entire listener table, including other hosts.

The official-server backend instead owns bounded loopback listeners and `tcp:port` mappings. Cancellation closes listeners and removes only its matching mappings on the original transport ID. This differs from `host:forward`, which is outside the crate's typed API.

## USB, authorization and discovery

The default `usb` feature uses nusb's Android/Linux, WinUSB and IOKit backends. `usb::list_devices` and `UsbDevice::open` enumerate/open devices. Android obtains UsbManager permission and passes a `BorrowedFd` to `usb::from_authorized_fd`, which duplicates it; retain the Java UsbDeviceConnection for the connection lifetime. Platform drivers and entitlements still apply. iOS supports TCP and reports USB unavailable.

`wireless::pair` implements TLS-bound AOSP SPAKE2 pairing. `ConnectOptions::tls` configures STLS/TLS with the same identity but does not require encryption. For `_adb-tls-connect` endpoints, explicitly select `TlsPolicy::Required`: it rejects missing TLS configuration before handshake and plaintext CNXN/AUTH before exposing a signature or public key. Default `Optional` permits legacy plaintext. Required TLS prevents downgrade without adding server certificate pinning to ADB's self-signed model. Pairing and connection ports differ.

The RustCrypto TLS provider is experimental and requires explicit `TlsConfig::experimental_rustcrypto` or a caller-supplied reviewed provider. Software RSA uses blinding; the rsa timing advisory and provider maturity still require release assessment. Discovery exposes raw mDNS events and resolver restart; trust, endpoint selection, reconnect and local-network/multicast permissions belong to callers.

Official-server services pin transport IDs so replacement devices with the same serial cannot receive old work. Shell/sync codecs and cancellation bounds are shared, but WRTE diagnostics are unavailable. Required TLS resolves a matching official `_adb-tls-connect._tcp` service or fails. Authorization-disabled background connections reuse only already authorized official transports.

## Validation and sources

```sh
cargo test -p interop-adb
cargo test -p interop-adb --test wireless_boringssl -- --ignored
INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  cargo test -p interop-adb --test reverse_adbd --test sync_adbd -- --ignored
```

Ignored BoringSSL tests require the independently built helper documented in their source. Device tests require an authorized endpoint and use a unique temporary directory without invoking an adb executable. Wire fixtures cover legacy/authenticated transports, credit/backpressure, close, TLS and reverse allowlists; device tests cover reverse/JDWP and sync codec interoperability. These are separate from platform/product validation in [the validation record](../../../docs/implementation/validation.md).

Protocol sources at fixed AOSP revision `1cf2f017d312f73b3dc53bda85ef2610e35a80e9`:
[handshake/reverse requests](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/adb.cpp),
[listeners](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/adb_listeners.cpp),
[JDWP](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/daemon/jdwp_service.cpp),
[sync](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/daemon/file_sync_service.cpp).

Typed host forwarding, package management, incremental install and a 5037 compatibility server are outside the API.
