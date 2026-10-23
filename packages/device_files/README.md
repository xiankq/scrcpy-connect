# device_files

`RemoteFiles` owns remote browsing, filtering/sorting/paging, bounded search and gallery snapshots, selection, conflicts, cancellation, task history and recovery. It takes a `RemoteFileExecutor` for typed metadata, native copy/progress and mutation receipts; `device_runtime` supplies native cache and publication leases. Bulk bytes remain native. See [architecture](../../docs/implementation/architecture.md) for platform and resource ownership.

Selections are gathered before writing. Each file uses an unpublished part, a flushed `finalizing` record and a separate commit. A lost commit receipt stays `result_unknown` and is never replayed automatically. Cancellation drains workers; it does not undo published files or completed siblings. History removal preserves files.

`file_tasks.v2.journal` is a flushed ordered log with atomic compaction. Legacy Rust journals are read-only migration inputs. Invalid sequence/generation or torn tails fail closed; persistence failure disables further writes. One owner serves the private directory. Within its isolate, attachment handoff retains cache leases for the same normalized directory and executor instance; this does not survive isolate/process restart. Sudden-power-loss durability is unverified.

Search/gallery allow four active and sixteen retained snapshots, bounded to 30 seconds, 50,000 entries, 32 levels and 4,096 facts per directory. Gallery order freezes after completion. Child symlinks are excluded; only explicit storage aliases may be roots. Permission failures, truncation and observed changes remain partial results.

[Test commands and device isolation](VALIDATION.md).
