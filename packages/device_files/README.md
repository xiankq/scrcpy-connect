# device_files

Dart owns remote directory presentation, filtering/sorting/paging, bounded search
and gallery snapshots, selected directory trees, conflict decisions, cancellation,
task history and recovery. `documents/` and system delivery retain their existing
platform integration responsibilities.

`RemoteFiles` takes a `RemoteFileExecutor`: typed `stat`/bounded `list` facts,
native source-to-part copy with progress, and explicit mutation/commit receipts.
The `device_runtime` assembly supplies `NativeFileExecutor`, native cache
reservations and imported-source publication leases. Bulk file bytes stay between
native file handles and ADB SYNC; they do not pass through Dart JSON or base64.
Directory events are bounded to 128 typed entries, with one pending event.

All selection facts are gathered before writes begin. Files use an unpublished
part and a separate commit after `finalizing` is flushed to the task journal.
Commit receipt loss is `result_unknown`; recovery preserves the destination and
never automatically replays the commit. Directory transfers are a bounded
selection snapshot, not a filesystem-wide transaction. Cancellation awaits the
execution worker and closes retained native part handles; it does not delete a
published file or undo completed siblings. History removal never deletes files.

`file_tasks.v2.journal` is an ordered, flushed append log with atomic compaction.
The old Rust `transfers.json`/`transfers.journal` are read only during migration
and remain unchanged. Invalid sequence, generation rollback or a torn tail fails
closed. Appending failure disables further writes for this owner. The runtime
assembly provides a single owner for the private data directory. Within its
Dart isolate, closing an attachment hands outstanding native cache leases to the
next owner of the normalized private directory. Reopening reuses those leases,
without an eviction gap or duplicate reservation. The cache executor must remain
the same backend instance; switching it fails closed while a handoff exists.
This handoff does not cross Dart isolate/process restart boundaries. File flushes
and atomic rename are used; host-specific sudden-power-loss durability of the
Dart journal has not been certified.

Search and gallery use fresh independent snapshots, at most four active and
sixteen retained. Traversal stops at 30 seconds, 50,000 entries and 32 levels;
one directory yields at most 4,096 facts. Gallery pages remain hidden until the
snapshot finishes, then use stable mtime/path order. Child symlinks are never
traversed; only explicit storage aliases can be roots. Permission failures,
invalid names, truncation and observed directory changes remain partial results.

See [validation](VALIDATION.md) for test boundaries and commands.
