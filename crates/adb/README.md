# interop-adb

An independent asynchronous ADB host. It connects directly to adbd over TCP or
USB; it never invokes an adb executable or relies on a local adb server.

```rust,no_run
use interop_adb::{Client, ConnectOptions, Identity, OperationOptions};

# async fn example() -> interop_adb::Result<()> {
let identity = Identity::generate()?; // Persist securely and reuse across connections.
let client = Client::connect_tcp("192.0.2.10:5555", ConnectOptions {
    identity: Some(identity),
    request_authorization: true, // Explicitly allow the Android authorization dialog.
    ..Default::default()
}).await?;
let output = client.shell("printf hello", 4096, OperationOptions::default()).await?;
assert_eq!(output.stdout, b"hello");
# Ok(())
# }
```

`Client` clones share one device connection and multiplex independent logical
streams. Incoming data is acknowledged as consumed. Queues, frame sizes, shell
output and directory results have explicit limits. Dropping a stream closes it;
dropping the last connection/stream owner stops the underlying transport tasks.
Operation options carry timeouts and a cancellation token. Interrupted writes and
failed sync operations close their affected stream rather than reuse uncertain
protocol state. Callers should drop a sync object when abandoning an in-progress
operation.

`shell` preserves stdout/stderr bytes and shell_v2 exit status; legacy shell has
no exit status. `shell_session` exposes raw/PTY stdin, close-stdin, terminal resize
and cancellation-safe incremental output events. `cmd` quotes each argument;
`abb`/`abb_exec` encode Binder arguments with their protocol's NUL separators.
`connect_socket` has typed TCP/local/JDWP/vsock destinations, and `reboot` has typed
targets. `exec` and `open` expose unmodified byte streams. `sync` supports
64-bit stat/list v2, legacy fallbacks, and bounded streaming push/pull; paths are
bytes and never interpolated into shell commands. `push_compressed` and
`pull_compressed` add Brotli/LZ4/Zstd via bounded pure Rust codec workers; their
codec round trips and cancellation are tested, while compressed sync still needs
official adbd interoperability validation.

The default `usb` feature uses nusb's native Android/Linux, WinUSB and IOKit
backends. `usb::list_devices` and `UsbDevice::open` support platform enumeration.
On Android, the platform requests UsbManager permission and passes an authorized
`BorrowedFd` to `usb::from_authorized_fd`; this duplicates the descriptor and
leaves the Java-owned FD intact. Keep UsbDeviceConnection alive for the device
connection lifetime. USB ADB header and payload transfer boundaries and required
zero-length packets are preserved. iOS compiles the TCP core and reports USB
unavailable. Platform USB access/driver entitlements still apply.

For modern wireless debugging, `wireless::pair` runs TLS-bound AOSP SPAKE2 pairing;
`ConnectOptions::tls` enables STLS/TLS connection with the same host identity.
Pairing and connection ports differ. The supplied RustCrypto TLS provider is
explicitly experimental; applications must deliberately call
`TlsConfig::experimental_rustcrypto` or supply their own reviewed provider.
Software RSA uses the RustCrypto rsa crate with blinding for private operations;
its outstanding timing advisory and the provider's maturity require a release
security assessment. Successful interoperability alone is not that assessment.
The discovery module exposes mDNS events and trusted-GUID reconnect selection.
Mobile applications manage local-network/multicast authorization outside this
crate.

Validation distinguishes wire fixtures from device interoperability:

```sh
cargo test -p interop-adb
cargo test -p interop-adb --test wireless_boringssl -- --ignored
```

The optional ignored tests use an independently built official BoringSSL helper;
their source documents setup. Actual device tests need a reachable authorized
adbd endpoint and separate platform evidence. Generic `open` permits adbd service
access, but this crate does not yet provide typed forward/reverse, package
management, delayed ACK, incremental
install or a 5037 smart-socket compatibility server.
