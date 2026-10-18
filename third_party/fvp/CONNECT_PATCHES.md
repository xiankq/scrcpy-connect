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

Run `python3 tool/fvp_snapshot_regression.py` from the workspace root. This
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

The upstream native SDK resolution is unchanged: CMake supports `FVP_DEPS_URL`
and `FVP_DEPS_SHA256`, while its default URL uses nightly binaries. CocoaPods
uses `mdk ~> 0.39.0`; SwiftPM pins its existing release URL and checksum. This
source patch does not establish a reproducible SDK closure or successful builds
on every platform. Those remain separate acceptance tasks. See the workspace's
current status and performance evidence for actual Android validation.
