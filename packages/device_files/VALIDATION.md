# File-owner validation

Run the pure Dart owner checks from the repository root:

```sh
dart packages/device_files/tool/verify_file_owner.dart
```

`remote_files_test.dart` runs the same checks under Flutter Test: browsing/snapshots, conflicts, commit uncertainty, cancellation, journal recovery/compaction, lease handoff and history removal preserving files. Native metadata, publication and source-retention checks live in Rust `file_execution_facts`, `media_cache`, `share_import`, `remote_helper_android_tests` and `local_publication::tests`.

For the assembled real-device path, run in `packages/device_runtime`:

```sh
INTEROP_FILES_AVD=<authorized-endpoint> INTEROP_ADB_KEY=<test-identity> \
  flutter test --no-pub test/files_native_test.dart
```

Without `INTEROP_FILES_AVD` the test skips. `INTEROP_ADB_KEY` selects the authorized key (default `~/.android/adbkey`). Use a dedicated authorized target: the test creates unique remote/local trees and a private official ADB server, copies the test key only into its temporary runtime, then removes its resources. It verifies binary transfer, search/conflicts, composed activity state, cancellation and owner restart/journal recovery.

Linux x86_64/Android API 36 AVD runs passed on 2026-10-23; other hosts/OEMs require separate validation. Former Rust `files.*`/`transfers.*` owner commands return `owner_moved`: assembly tests must use the Dart owner.
