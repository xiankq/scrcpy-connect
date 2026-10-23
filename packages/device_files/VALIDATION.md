# File ownership migration validation

2026-10-23, Linux x86_64 host. These results describe this workspace revision;
they do not establish Android/OEM or all desktop-host compatibility.

The pure Dart owner checks run with:

```sh
dart packages/device_files/tool/verify_file_owner.dart
```

Seventeen checks passed: filtering/sorting/paging and raw-name action boundaries;
frozen gallery order; finalizing-before-commit; conflict/keepBoth; cancellation
worker draining; read-only legacy migration; unknown commit refusing replay;
durable descendant/batch history removal preserving files; failed persistence
preserving memory and disabling reuse; sequence/torn-tail/generation rejection;
bounded journal compaction without resurrecting removals; unpublished selection snapshot cancellation; continuous uncertain cache lease handoff across four attachments, rejected backend changes and final lease release after explicit history removal; directory destination
remapping and empty directories; accessible partial galleries with protected
tree exclusions; device-scoped bounded scan cancellation and retention; wide
metadata with truncated directories. `remote_files_test.dart` runs the same
checks under Flutter Test.

Rust execution evidence is separate:

* `file_execution_facts`: four host/adbd fixture tests passed. They preserve raw
  names and >4 GiB sizes, reject child/local directory symlinks, distinguish
  masked empty-DONE permission failures, detect directory metadata changes,
  retain legacy storage alias fallback and bounded cancellation.
* `media_cache`: five host tests passed; one actual Android preview/thumbnail
  case remains explicitly ignored. Copy/commit/cache reservation tests no longer
  manufacture a Rust transfer owner.
* `share_import`: fifteen host tests passed, including retained source ownership
  when Dart has not supplied a complete durable publication proof.
* Existing native-helper Android race/atomic assertions remain in
  `remote_helper_android_tests`; calls use the current execution options API.
* `local_publication::tests`: retained source inode replacement is rejected
  before replacing an existing target; the target and replacement source both
  remain intact. A valid explicit replace then publishes successfully.

`file_execution_android` passed against the explicitly authorized
`emulator-5556` endpoint through an isolated official ADB server. It executed
typed list/stat, exact 4,096-byte binary push/pull, remote and local no-replace
publication, pre-cancellation and local absent-path metadata. Only its unique
`/data/local/tmp/interop-file-<UUID>` fixture was created and removed.

The former Rust task journal/state/removal and gallery traversal tests moved to
Dart ownership checks plus typed native-fact tests. Former Rust `files.*` and
`transfers.*` owner commands intentionally return `owner_moved`; tests must enter
through the Dart assembly rather than revive a second production task owner.

`packages/device_runtime/test/files_native_test.dart` is the explicit real-device
assembly check. Set `INTEROP_FILES_AVD` to an authorized endpoint and
`INTEROP_ADB_KEY` to its test identity; otherwise it is skipped. It creates only
a unique temporary remote directory and a private temporary local directory.
The actual Linux-host/AVD assembly run passed. It verified directory facts,
exact 4,096-byte binary push/pull equality, real remote search, ask-conflict,
`state.snapshot` transfer/activity composition, `activities.stop` cancellation,
Dart owner dispose/reinitialize with journal recovery, and batch history removal
preserving the downloaded file. It then removed its unique remote tree,
disconnected its test transport and shut down its private official ADB server.
The existing Settings foreground and other hosts' ADB servers were untouched.
The authorized SDK key was copied only into the temporary runtime directory;
requestAuthorization was explicitly enabled for this manual connection because
an isolated official server initially has no already-known transport.
