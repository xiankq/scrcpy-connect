# Android filesystem helper

`crates/android_helper` is a pinned independent Rust package run as the authorized ADB shell UID. It accepts three OS arguments, preserving arbitrary Unix path bytes:

```text
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename publish-replace SOURCE DESTINATION
interop-rename stat PATH UNUSED
interop-rename lstat PATH UNUSED
interop-rename list PATH LIMIT
```

Stdout is one bounded JSON result (`protocol:1`, `ok`, `errno`); paths are not printed. Rename uses atomic `renameat2(RENAME_NOREPLACE)` or `renameat`, with no copy/delete fallback. Cross-filesystem and unsupported operations retain their actual errno.

`stat` follows the final symlink only for caller-authorized storage aliases; `lstat` does not. Metadata retains 64-bit size and the platform's actual timestamp range. `list` accepts limits 1–10000, opens the final directory without following symlinks, and uses FD-relative child metadata. Names are original bytes as `nameHex`; vanished/denied children retain their errno. Enumeration failure is never a successful partial list. `truncated` requires observing an extra entry. Explicit root aliases may use `alias/.`; intermediate components follow normal kernel resolution.

## Build and tests

After root `flutter pub get`, use Rust 1.99.1, NDK 30.0.16248370 and Android targets aarch64, armv7, x86_64 and i686. `ANDROID_NDK_HOME` may select another installation of that pinned NDK.

```sh
dart servers/helpers/build.dart
dart servers/helpers/build.dart --check
dart servers/helpers/build.dart --rebuild
cargo +1.99.1 test --locked --manifest-path crates/android_helper/Cargo.toml
```

`--check` verifies hashes offline; `--rebuild` compares all four ABI builds without replacing artifacts. Source changes require all artifacts and manifest to be rebuilt. Ordinary app builds use those controlled inputs; shared packaging follows the [tooling contract](../../docs/implementation/repository-tooling.md).

## Deployment

`remote_helper.rs` verifies the selected ABI artifact and creates a fresh private 0700 directory per operation. A creation lease authorizes cleanup only after exclusive creation. The host verifies the opened executable's bytes before issuing a one-time token; execution uses the same FD, so pathname replacement cannot substitute code. No executable cache or device hash tool is required.

The bounded stdin bootstrap preserves raw paths without shell interpolation. EOF/cancellation releases its lease. Lost transport after invocation yields `result_unknown`; callers refresh instead of replaying via copy/delete. Broader ownership rules are in [architecture](../../docs/implementation/architecture.md).

On a dedicated authorized target:

```sh
INTEROP_CORE_TEST_ENDPOINT=127.0.0.1:15556 \
  INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  cargo test -p interop-core --lib remote_helper::android_tests -- --ignored --nocapture
```

Only unique fixture paths are used. Tests cover atomic no-replace races, source replacement, raw names, symlinks and directory contents. Host tests additionally cover >4GiB metadata and bounded/FD-relative listing.
