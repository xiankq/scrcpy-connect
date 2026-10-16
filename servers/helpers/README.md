# Atomic Android file operations

`crates/android_helper` is an independent, pinned Rust package. It runs as the
already-authorized ADB shell UID, uses the system libc and does not install an
APK, request root, change SELinux, or create a persistent service.

The executable accepts exactly three independent OS arguments:

```
interop-rename rename-no-replace SOURCE DESTINATION
interop-rename publish-replace SOURCE DESTINATION
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

Sources: [Bionic syscall declarations](https://android.googlesource.com/platform/bionic/+/master/libc/SYSCALLS.TXT),
[Linux VFS rename contract](https://www.kernel.org/doc/html/latest/filesystems/vfs.html).

## Rebuild

Install Rust **1.99.1**, NDK **28.2.13676358**, and Rust targets
`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`,
`i686-linux-android`. On Linux x86_64:

```sh
rtk proxy python3 servers/helpers/build.py
```

`ANDROID_NDK_HOME` may select another installation of the same pinned NDK.
The script builds against Android API 21, remaps checkout/Cargo paths, removes
linker build IDs and strips symbols. Committed artifacts and `manifest.json`
allow ordinary application builds to embed the helpers without needing an NDK
or a temporary directory. The manifest records source, lockfile, script and
artifact SHA256 hashes; changing source requires rebuilding all four artifacts.
The helper's independent Cargo workspace prevents ordinary app builds from
trying to compile this Android executable as part of the host library workspace.

## Deployment

`remote_helper.rs` selects an ABI reported by the connected target, verifies the
embedded artifact against the embedded manifest, and creates a random 0700
directory under `/data/local/tmp`. It pushes a fresh helper with mode 0700 for
each operation. It opens the executable on a standard descriptor, hashes that
descriptor, and executes `/proc/self/fd/0`; substituting the pathname after the
hash cannot redirect execution to another inode. There is no remote executable
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
rtk proxy env INTEROP_ADBD_ADDRESS=127.0.0.1 INTEROP_ADBD_PORT=15556 \
  /home/xiankq/.cargo/bin/cargo test -p interop-core --test remote_helper_android \
  -- --ignored --nocapture
```

This test uses only unique fixture paths. It checks EEXIST preserves both names,
directory contents, symlink identity, non-UTF8 names with trailing newlines,
competing no-replace operations, and concurrent atomic source replacement.
