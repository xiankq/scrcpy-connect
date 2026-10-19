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

Legacy adbd's ADB 1.0.0 transport retains checksum validation and 4 KiB payload
fragmentation when that is the daemon's advertised limit. Wire fixtures cover
both unauthenticated connections and RSA AUTH, legacy shell and sync v1
stat/list/push/pull. Normal stream closes with a zero sender ID, used by older
daemons, preserve queued tails and other streams. Explicitly requested
authorization may reoffer the same public key when a booting daemon retries
after Android's authorization framework becomes ready; the connection deadline
and cancellation still bound the handshake. These fixtures establish protocol
compatibility, not a tested minimum Android release for every service.

`Client::is_closed()` reports an observed close/cancellation, not proof that the
remote daemon is responsive. `inbound_activity()` provides an opaque snapshot:
compare only for equality on the same connection. It advances on nonempty reads,
including partial headers and payloads; it is neither a validated-frame count nor
a timestamp. The library does not start application health probes. The product
Core uses this signal to probe idle connections without interrupting active reads.

`ConnectOptions::burst_mode` opts into AOSP's experimental `delayed_ack` byte-credit
flow control; it defaults to `false`. Both peers must advertise support, and
`Client::burst_mode()` reports the actual negotiated mode. Without mutual support
the connection retains classic per-packet acknowledgements. External connectors
must use `from_negotiated_transport_with_burst` only when their own handshake
advertised the feature; `from_negotiated_transport` always keeps classic framing.
Changing an application's preference does not renegotiate an existing connection.

Burst streams reserve a 64 KiB receive window plus one negotiated maximum-payload
overshoot and conservative queue metadata. A connection caps these reservations
at 128 MiB; ownership persists through close until the consumer drains or drops
the tail. Partial reads return consumed byte credit, and signed credit deltas may
temporarily take a sender below zero. This is a protocol capability, not a promise
of lower video latency. Wire tests cover negotiation, credit, backpressure, reverse
streams, cancellation and TLS; real-device/platform coverage is reported separately.

For opt-in receive diagnostics, `AdbStream::set_read_trace_clock` accepts a quick,
non-reentrant monotonic microsecond clock. `read_trace()` returns only the latest
WRTE receipt: payload read start/completion, routing and first consumption in
that same clock domain. It keeps constant storage and does not change byte or
ACK handling. Partial reads from one WRTE retain its sequence and first-consumed
time; several service packets can share that receipt. Reception begins after
the ADB header, so it excludes earlier device, kernel and transport buffering.
Replacing or disabling the clock drops stale diagnostics, including queued
receipts, while retaining data. A payload already in flight may finish one call
to its old clock before its receipt is discarded. With no subscriptions, new
WRTEs do not sample clocks or take an additional route lock; an atomic check and
the optional metadata fields remain.

`shell` preserves stdout/stderr bytes and shell_v2 exit status; legacy shell has
no exit status. `shell_session` exposes raw/PTY stdin, close-stdin, terminal resize
and cancellation-safe incremental output events. `cmd` quotes each argument;
`abb`/`abb_exec` encode Binder arguments with their protocol's NUL separators.
`connect_socket` has typed TCP/local/JDWP/vsock destinations, and `reboot` has typed
targets. `exec` and `open` expose unmodified byte streams. `sync` supports
64-bit stat/list v2, single-path no-follow `lstat`, legacy fallbacks, and bounded
streaming push/pull; paths are bytes and never interpolated into shell commands. `push_compressed` and
`pull_compressed` add Brotli/LZ4/Zstd via bounded pure Rust codec workers; their
decoders have been checked against official adbd in both directions, including
empty, binary, compressible and incompressible files. Decompression output limits,
interrupted push input, cancellation and reuse of healthy sync streams have
separate real-device checks. `lstat` uses LST2 or legacy no-follow STAT; legacy
metadata has 32-bit size/time and cannot distinguish permission errors from
absence. The tested Android SELinux policy denies adbd metadata access to some
shell-created symlinks; this remains a remote permission error. A system symlink
was verified to remain a symlink with LST2 and become its target with STA2.

`reverse_forward` installs an adbd device-side TCP or Unix listener and bridges
accepted connections to an explicitly supplied host TCP address. TCP port zero
returns the allocated device port. Rebind, no-rebind, listing and removal use the
direct `reverse:` protocol; device-initiated streams are accepted only for random
opaque service names registered by this client. Both bridge directions progress
independently under backpressure. Listeners persist until removal or transport
disconnection, so dropping `ReverseBinding` metadata does not remove a listener.
`reverse_remove_all` affects adbd's entire listener table, potentially including
other hosts; prefer removing an individual owned binding.

```rust,no_run
use interop_adb::{Client, OperationOptions, ReverseSocket};
# async fn example(client: &Client) -> interop_adb::Result<()> {
let host = "127.0.0.1:8080".parse().unwrap();
let binding = client.reverse_forward(
    &ReverseSocket::Tcp(0), host, true, OperationOptions::default(),
).await?;
// Device connections to binding.device now reach the host's port 8080.
client.reverse_remove(&binding.device, OperationOptions::default()).await?;
# Ok(())
# }
```

This is distinct from `host:forward`, which belongs to the adb server's 5037
smart-socket protocol. This crate does not connect to that server. Use
`connect_socket` to open a device socket directly; an application can expose its
own host listener if it needs forward-like behavior.

`jdwp_processes` reads the initial length-framed `track-jdwp` update, including an
empty list, instead of relying on legacy `jdwp` closing an empty response.
`track_jdwp` provides bounded incremental updates and preserves partial frames
when a read future is dropped. Returned PIDs are process handles, not stable
application identities.

Generic `open` also permits advanced adbd services. In particular, `dev:` is not
a general file API: an actual non-pollable `/dev/zero` descriptor caused the tested
official daemon to abort while adding it to epoll (`EPERM`). There is deliberately
no typed generic device-file API; use sync for files. Only use low-level serial
services with a known pollable device and the relevant platform support.

The default `usb` feature uses nusb's native Android/Linux, WinUSB and IOKit
backends. `usb::list_devices` and `UsbDevice::open` support platform enumeration.
On Android, the platform requests UsbManager permission and passes an authorized
`BorrowedFd` to `usb::from_authorized_fd`; this duplicates the descriptor and
leaves the Java-owned FD intact. Keep UsbDeviceConnection alive for the device
connection lifetime. USB ADB header and payload transfer boundaries and required
zero-length packets are preserved. iOS compiles the TCP core and reports USB
unavailable. Platform USB access/driver entitlements still apply.

For modern wireless debugging, `wireless::pair` runs TLS-bound AOSP SPAKE2 pairing;
`ConnectOptions::tls` configures STLS/TLS with the same host identity; it alone
does not require encryption. Set `tls_policy: TlsPolicy::Required` for a modern
wireless endpoint. This rejects plaintext CNXN and AUTH before sending a
signature or public key, and rejects missing TLS configuration before sending
the initial handshake. `TlsPolicy::Optional` is the default for legacy TCP/USB
compatibility and may accept plaintext AUTH/CNXN. `Discovery::reconnect_next`
always requires TLS for its selected `_adb-tls-connect` services.

This follows the fixed AOSP TLS negotiation path: adbd sends STLS as the first
response in TLS mode even when host authorization is disabled, and AUTH does
not provide a fallback for a TLS transport. See
[`adb.cpp`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/adb.cpp).
The required policy prevents plaintext downgrade; it does not add server
certificate pinning or change ADB's self-signed certificate verification model.
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
INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  cargo test -p interop-adb --test reverse_adbd --test sync_adbd -- --ignored
```

The optional ignored tests use an independently built official BoringSSL helper;
their source documents setup. Actual device tests need a reachable authorized
adbd endpoint. The reverse test checks TCP/Unix listeners, concurrent bridging,
rebind/no-rebind, removal and JDWP updates. The sync test checks all three codecs
against the daemon, output bounds and interrupted input, using only a unique
temporary device directory. Neither test invokes an adb executable. A wire
fixture additionally withholds a write ACK until input is consumed to check
full-duplex bridge progress, and rejects unapproved device OPENs.

Protocol behavior is checked against fixed AOSP revision
[`1cf2f017d312f73b3dc53bda85ef2610e35a80e9`](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/):
[reverse requests](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/adb.cpp),
[listener handling](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/adb_listeners.cpp),
[JDWP](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/daemon/jdwp_service.cpp),
and [sync](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/daemon/file_sync_service.cpp).

Typed host forwarding, package management, incremental install and
a 5037 smart-socket compatibility server remain outside this crate's current API.
