# fvp source patch

Source: the official pub.dev **fvp 0.39.1** archive, downloaded from
<https://pub.dev/api/archives/fvp-0.39.1.tar.gz>.

Original archive SHA-256:
`2f4607e07748856dbe268a3b968efe973c27f85ea4e7621c4209783a6dad26a0`.
The example application is omitted. All plugin platform sources, public Dart
APIs and the upstream BSD-3-Clause license are retained. Generated files,
downloaded SDK binaries and native build outputs are not vendored.

The workspace overrides both fvp dependencies to this source directory. The
root lockfile records a path dependency; the original archive digest above
identifies the input, not the modified source. Git records the resulting fork.

## Patch

`MdkSnapshot` dereferenced the nullable result supplied by MDK's snapshot
callback. On failure it now posts an empty Uint8List. The existing Dart handler
interprets this as `null`, completing the pending snapshot instead of crashing
or leaving its Future pending. Valid pixel buffers retain their existing
stride-based length and copy behavior.

The same change is present in all five upstream callback source copies:
`lib/src`, `darwin/Classes`, `darwin/fvp/Sources/fvp`, `ios/Classes`, and
`macos/Classes`. No new platform API or Android implementation is introduced.

Run `dart tool/fvp_snapshot_regression.dart` from the workspace root. This
compiles the actual function body with the real Dart message headers and injects
results at the MDK callback boundary. It checks failed and successful completion,
row padding, unknown handles, and consistency of the platform copies. Against
the original archive (`--package-root <extracted-archive>`) the null case exits
with SIGSEGV. This is a source-boundary regression, not a real renderer test or
a reproduction of the separate MDK empty-`std::function` crash.
The probe also loads that function into a real Dart VM and verifies delivery of
both empty and populated Uint8List messages through `Dart_PostCObject`. It needs
a POSIX host, a C++20 compiler and `dart` on PATH (or `--dart <executable>`).

## SDK and platform validation

CMake defaults to the official MDK v0.39.0 release and requires its archive
SHA-256. `cmake/mdk-release.json` records the official GitHub release API asset
digests; `cmake/mdk-release.cmake` supplies the matching platform pins. Windows
uses the release's VS 2026 archive names. `FVP_DEPS_URL` still supports mirrors;
without an explicit digest override, mirrors must serve those same release bytes.
A custom SDK requires an explicit 64-character `FVP_DEPS_SHA256`; checksum
mismatches fail before replacing the cached SDK. `FVP_DEPS_LATEST` cannot override
these pins. CocoaPods requires exactly `mdk 0.39.0`; SwiftPM already pins the
matching release URL and checksum.

Provenance: [official v0.39.0 release API](https://api.github.com/repos/wang-bin/mdk-sdk/releases/tags/v0.39.0).
The pre-existing Android nightly archive in a developer cache had SHA-256
`70d9dffb289a26054567e51088786af730bb1ffc46bffdf2f09e10d7ebf7b012`, which differs
from the official release archive. It is not accepted as the release cache.
`dart tool/check_native_deps.dart` (also invoked by `tool/check.sh`) runs the
offline CMake dependency tests, including bad-hash
rejection and preservation of the previous SDK on a failed fetch. CI builds and
checks final applications on Android, iOS, macOS and Windows; adding these jobs
does not establish that they have run successfully on their remote hosts.
