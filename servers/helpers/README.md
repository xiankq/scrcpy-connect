# Android filesystem operations

`crates/android_helper` is an independent, pinned Rust package. It runs as the
already-authorized ADB shell UID, uses the system libc and does not install an
APK, request root, change SELinux, or create a persistent service.

The executable accepts exactly three independent OS arguments:

```
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename publish-replace SOURCE DESTINATION
interop-rename stat PATH UNUSED
interop-rename lstat PATH UNUSED
interop-rename list PATH LIMIT
```

Arguments retain arbitrary Unix path bytes. Standard output is one bounded JSON
result, `{"protocol":1,"ok":false,"errno":17}` for an existing destination.
Paths are never printed. `rename-no-replace` directly invokes the architecture's
`renameat2` syscall with `RENAME_NOREPLACE`; `publish-replace` uses `renameat`.
There is no copy, hard-link, preflight-stat, source-unlink, or non-atomic fallback.
The operation therefore moves whichever directory entry the source name denotes
at the kernel's serialization point. A later replacement of that source name is
never deleted by an additional cleanup operation. Directory and symlink entries
have the same atomic semantics. Cross-filesystem moves fail with `EXDEV`.
`ENOSYS`, unsupported-flag `EINVAL`, and `EOPNOTSUPP` are honest capability errors.

Metadata operations use the same executable and protocol version. `stat` follows
the final symlink; the caller permits it only for known Android shared-storage
root aliases. `lstat` reports the final named entry without following a symlink.
Both return `mode`, unsigned 64-bit `size`, and signed 64-bit `modifiedSeconds`
alongside `protocol:1`, `ok:true`, and `errno:0`. Their third argument is ignored.
Android's 32-bit API 21 libc still has its native 32-bit timestamp range; the JSON
field widens that value without further truncation. File sizes remain 64-bit on
all four ABIs through `fstatat64`.

`list` accepts a decimal limit from 1 through 10000. It opens the directory with
`O_DIRECTORY|O_NOFOLLOW`, transfers its FD to `fdopendir`, and streams `readdir`
entries in filesystem order without collecting or sorting the directory.
Child metadata uses `fstatat64` relative to that opened FD with
`AT_SYMLINK_NOFOLLOW`, so replacing the directory's pathname cannot redirect
subsequent metadata lookups. Names are lowercase `nameHex` of the original Unix
bytes; no pathname decoding or shell tools are involved. Each entry contains
`nameHex`, `mode`, `size`, `modifiedSeconds`, and `errno`. If a child disappears or
denies metadata access, its name remains with the actual errno and zero metadata.
`.` and `..` are omitted. The result has `entries` and `truncated`; truncation is
true only after observing another non-dot entry beyond the requested limit.

Directory open or enumeration errors return `ok:false` and the actual errno.
An enumeration failure may retain previously emitted entries, but never reports
that partial list as successful. A final directory symlink, including one with
redundant trailing slashes, is rejected. An explicitly authorized root alias may
be passed as `alias/.`; the caller owns that exception and authorization.
Intermediate path components retain normal kernel pathname resolution. These
read-only operations do not change the rename operations' interfaces or atomic
semantics.

Sources: [Bionic syscall declarations](https://android.googlesource.com/platform/bionic/+/master/libc/SYSCALLS.TXT),
[Linux VFS rename contract](https://www.kernel.org/doc/html/latest/filesystems/vfs.html).

## Rebuild

Install Rust **1.99.1**, NDK **30.0.16248370**, and Rust targets
`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`,
`i686-linux-android`. On Linux x86_64:

```sh
dart servers/helpers/build.dart
```

`dart servers/helpers/build.dart --check` verifies source/tool and artifact hashes offline; `--rebuild` builds and compares all four ABIs without replacing artifacts.
Run `flutter pub get` once at the repository root to prepare the Dart dependencies.
The script locates the repository from its own path and also works outside the root working directory.

`ANDROID_NDK_HOME` may select another installation of the same pinned NDK.
The script builds against Android API 21, remaps checkout/Cargo paths, removes
linker build IDs and strips symbols. Committed artifacts and `manifest.json`
allow ordinary application builds to package the helpers without needing an NDK
or a temporary directory. Shared compressed packaging is described in the
[tooling contract](../../docs/implementation/repository-tooling.md#被控执行产物的共享打包).
The manifest records source, lockfile, script and
artifact SHA256 hashes; changing source requires rebuilding all four artifacts.
The helper's independent Cargo workspace prevents ordinary app builds from
trying to compile this Android executable as part of the host library workspace.

Host CLI tests cover sparse files over 4 GiB, raw-byte names, final symlinks,
per-entry permission errors, 4096/10000-entry limits, and directory-path
replacement during a blocked listing:

```sh
cargo +1.99.1 test --locked \
  --manifest-path crates/android_helper/Cargo.toml
```

## Deployment

`remote_helper.rs` selects an ABI reported by the connected target, verifies the
packaged artifact against the compiled manifest, and creates a random 0700
directory under `/data/local/tmp`. It pushes a fresh helper with mode 0700 for
each operation. A raw-exec creator holds a directory lease and installs cleanup
only after exclusive creation succeeds. Losing the creation receipt or dropping
the host future releases the lease through stdin EOF; a directory collision does
not authorize cleanup of the existing directory.

It opens the executable on a standard descriptor and returns that descriptor's
bytes to the host. Only after comparing every byte and an independent random
end marker against the verified packaged artifact does the host send a one-time
execution token. The bootstrap then executes `/proc/self/fd/0`; substituting the
pathname cannot redirect execution to another inode. No device-side hash tool
is required. There is no remote executable
cache. Other Android app UIDs cannot access the private deployment directory.
An attacker already holding the same ADB shell UID has the same filesystem and
process privileges as the authorized controller.

The bootstrap disables PTY echo before receiving any path bytes, then accepts a
bounded host-generated script on stdin. This supports arbitrary bytes and long
paths without treating them as shell syntax or exceeding old ADB service-name
limits. A sentinel preserves trailing newlines in command substitution.
Deployment cleanup runs on normal completion, failure, and future cancellation.
If the transport is lost after invocation, callers receive `result_unknown` and
must refresh; the operation is never repeated through copy/delete.

## Actual Android verification

```sh
env INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  /home/xiankq/.cargo/bin/cargo test -p interop-core --test remote_helper_android \
  -- --ignored --nocapture
```

This test uses only unique fixture paths. It checks EEXIST preserves both names,
directory contents, symlink identity, non-UTF8 names with trailing newlines,
competing no-replace operations, and concurrent atomic source replacement.
