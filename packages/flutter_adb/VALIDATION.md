# Validation on 2026-10-23

Host: Linux x86_64, Dart 3.13.5 / Flutter 3.47.7, official platform-tools
37.0.1-15733141. Device fixture: authorized Android AVD `emulator-5556`, explicitly
enabled adbd TCP 5555 and SDK forward `127.0.0.1:15556`. Every test server used a
new private directory/loopback port and was stopped afterward; tests did not
replace the SDK server on 5037 or other devices' transports.

Passed:

- Four Dart tests cover typed binary channels, pull-based event backpressure,
  cancellation of a pending native read, idempotent cleanup, and missing bundled
  binary failure without a PATH fallback.
- Real Dart official-server integration verifies startup/exit and released port,
  binary stdout/stderr with exit 7, 131073-byte push/pull, maximum pull bytes,
  partial-file cleanup, refusal to overwrite, and cancellation of sleeping shell.
- Two Rust smart-socket wire fixtures verify exact host framing, transport-ID
  pinning, unchanged raw bytes, client retirement closing idle sockets, and
  secure mDNS selection without plaintext fallback.
- Actual Rust service codecs over an isolated official server passed the
  existing reverse-adbd suite (TCP/Unix, concurrency, no-rebind/rebind/removal,
  JDWP) and sync-adbd suite (Brotli/LZ4/Zstd in both directions, empty/binary/
  incompressible input, byte bounds, cancellation, and genuine stat/lstat errno).
- `cargo clippy -p interop-adb -p interop-core --all-targets -- -D warnings`.

This is Linux host and AVD protocol evidence. Windows/macOS execution, physical
USB identity handoff, mobile generic FRB calls, and actual wireless pairing/TLS
require separate platform/device validation. A wire fixture establishes the
secure-service routing rule, not successful real wireless pairing.
