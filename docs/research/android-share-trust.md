# Android share trust and process engine ownership

Checked: 2026-10-17, against the current working tree. Rust owns incoming-file
copying, journals, transfer source leases and reconciliation. Android validates
URI authority and lends descriptors; Dart coordinates that handoff. Audio uses
engine-owned public fvp players and a thin Android focus/service adapter.

The current real Android nine-mode import/presentation/Cancel suite passed in
20 seconds: `/tmp/connect-incoming-share-final.log` contains passing app
assertions, and `/tmp/connect-e2e/incoming-share/result.json` lists every mode
with `shareAcceptanceComplete:true`. This verifies the exercised incoming-share
flow, not actual submission to a 被控设备, adversarial-provider pressure or every
task-return arrangement. The fixture corrections and remaining boundaries are
recorded below.

## Ownership and the actual handoff

| Layer | Current responsibility | Source |
| --- | --- | --- |
| Android `IncomingShares` | Validate incoming intents/grants; keep pending URI metadata; query/open a provider with cancellation; lend and close original asset FDs | [IncomingShares.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/IncomingShares.kt) |
| Dart `ShareIntake` | Configure the app cache root, deduplicate concurrent delivery by share ID, open each source, await Rust adoption, then consume native pending metadata and release originals | [share_intake.dart](../../packages/interop_bridge/lib/src/share_intake.dart) |
| Rust `ImportManager` and `Policy` | Reserve capacity, adopt sources, copy bytes, publish readiness, persist ownership, prevent duplicate task publication and reconcile durable transfers | [sharing/mod.rs](../../crates/interop_core/src/sharing/mod.rs), [policy.rs](../../crates/interop_core/src/sharing/policy.rs) |
| Rust `Source` | Validate exactly one FD/path, duplicate borrowed Android/Linux FDs, apply asset offset/length and validate source metadata | [source.rs](../../crates/interop_core/src/sharing/source.rs) |
| Process Flutter host | Keep one engine and platform/event channels; route Activity-dependent operations to the current weak Activity reference | [ProcessFlutterHost.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/ProcessFlutterHost.kt) |

`sharing.platform.*` methods belong to the Android adapter; `sharing.*` methods
belong to Rust. They are different ownership boundaries. A successful
`sharing.import` response means Rust has duplicated/adopted every accepted source
and scheduled the job; its initial status is `starting`, not proof of completed
copying. The final Rust `share.received` event and `sharing.pending` snapshot
report `ready` or `error`. Dart releases original FD leases in `finally`, including
when another original fails to close. Concurrent handoff deduplication is covered
by [the Dart intake tests](../../packages/interop_bridge/test/share_intake_test.dart).

## A received URI is not permission to read app-private data

Before any provider query/open, Android requires a `content` URI with an authority,
a resolvable provider, `FLAG_GRANT_READ_URI_PERMISSION`, and read access granted to
the receiving process. A provider belonging to the application's package **or
UID** is rejected, including an authority alias. This stops an incoming intent
from using the receiver's own privileges to read its private provider. The
adapter takes streams from `EXTRA_STREAM`, falling back to `ClipData` when that
list is empty, and deduplicates URIs. Both input list counts are bounded at 32;
native pending metadata is bounded at eight batches. See
[IncomingShares.accept](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/IncomingShares.kt).

On API 35+, MainActivity captures `initialCaller` for its initial intent or
`currentCaller` while handling `onNewIntent`. A missing caller, denied check or
exception rejects a content URI. Android documents that
`ComponentCaller.checkContentUriPermission` uses launch-time permission evidence
for URIs in intent data, `EXTRA_STREAM` or `ClipData`; it is not a live permission
query. The receiver must also have access. Before API 35 the receiver grant and
provider ownership checks remain, without equivalent caller attribution.
[ComponentCaller reference](https://developer.android.com/reference/android/app/ComponentCaller#checkContentUriPermission(android.net.Uri,%20int)),
[Activity caller API](https://developer.android.com/reference/android/app/Activity#getCurrentCaller()).

The source resource [filepaths.xml](../../app/android/app/src/main/res/xml/filepaths.xml)
restricts outgoing FileProvider paths to `files/screenshots`, `files/media`,
`cache/documents`, `cache/outgoing` and `cache/share_plus`. It exposes no root,
whole files directory, whole cache directory or `cache/incoming` journal. Android
requires configured directory paths for FileProvider sharing and recommends
narrow exposure. The merged APK resource and real outgoing/open-file behavior
still need independent acceptance; source XML alone does not prove the final
merge. [FileProvider paths and grants](https://developer.android.com/reference/androidx/core/content/FileProvider),
[directory exposure guidance](https://developer.android.com/privacy-and-security/risks/file-providers).

## Opening, admission and cancellation are separate stages

Android currently queries **only `DISPLAY_NAME`**, then calls
`openAssetFileDescriptor(uri, "r", signal)`. The handoff includes its FD,
`startOffset` and nonnegative `declaredLength`, not the provider's `SIZE` column.
The native open executor has one worker and a queue of eight. Registration
rejects when eight open jobs or 256 existing original descriptor leases are
observed; this check does not reserve descriptor capacity for queued opens. A separate
one-worker/eight-queue executor dispatches `CancellationSignal.cancel()`.
Activity destruction cancels that Activity's pending opens and closes its
originals. These are platform resource bounds, not Rust cache admission.
[IncomingShares.open/releaseOwner](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/IncomingShares.kt).

Dart opens the source descriptors **before** calling Rust `sharing.import`.
Therefore the current implementation does not guarantee cache admission before
provider opening. Each Dart open has a 120-second timeout that requests native
cancellation; bridge disposal also cancels tracked opens. Android provides
cancellation-aware query/open APIs, but an uncooperative provider can still hold
the bounded worker until its call returns. A late cancelled result closes the
returned original instead of publishing a new lease.
[ContentResolver descriptor/cancellation contract](https://developer.android.com/reference/android/content/ContentResolver#openAssetFileDescriptor(android.net.Uri,%20java.lang.String,%20android.os.CancellationSignal)).

Rust defaults are eight visible pending batches, 64 batch directories, 128
transfer leases, 32 sources per batch, 512 MiB per file, 1 GiB per batch and 2 GiB
retained payload. Text is limited separately: native Kotlin checks 1,048,576 UTF-16
code units; Rust checks 1,048,576 Unicode scalar values. MIME metadata is bounded
at 256 bytes in Rust. Unknown/damaged ownership records block new admission
instead of being deleted to make room. These limits are defined by
[Limits/Policy.reserve](../../crates/interop_core/src/sharing/policy.rs).

Rust reserves its batch before adopting sources. On Android/Linux it duplicates
borrowed FDs with `F_DUPFD_CLOEXEC` and enables nonblocking reads; the caller's
original remains its responsibility. Declared oversize lengths fail before Rust
duplicates/opens that source, but the Android provider has already been opened.
Regular files support the declared asset offset/range and are checked for size
or modification changes after copying; nonseekable sources reject nonzero
offsets. Display names are metadata, normalized separately from opaque generated
cache filenames. [Source.open](../../crates/interop_core/src/sharing/source.rs).

Copying uses one batch worker and one blocking-I/O permit, in chunks up to 64 KiB.
Actual copied bytes are checked against file/batch/retained limits before each
write. On Android/Linux a successful free-space probe enforces a 32 MiB reserve;
an unavailable probe is not a confirmed reserve. The Rust job has its own
120-second deadline, beginning after source adoption, rather than a single
end-to-end deadline covering all preceding provider opens. Cancellation/deadline
fails the batch and does not publish partial files as ready. A blocking OS read
already in progress cannot be forcibly cancelled by dropping its async waiter;
the separate I/O permit bounds that outstanding work.
[ImportManager.copy_file/import](../../crates/interop_core/src/sharing/mod.rs).

## Persistent sources and transfer publication

Rust stores batch journals at `cache/incoming/<share UUID>/.share` and lease
journals under `cache/incoming/.leases`. Journal writes use private temporary
files, file sync, rename and, on Unix, directory sync. Registered paths are built
from validated batch IDs and generated child names, never from a display name or
arbitrary transfer path. The root must resolve to the authorized cache's exact
`incoming` child. Legacy Java-properties records can be migrated; this is legacy
data compatibility, not a remaining Kotlin import owner.
[policy.rs](../../crates/interop_core/src/sharing/policy.rs),
[legacy.rs](../../crates/interop_core/src/sharing/legacy.rs).

| Rust operation | Ownership contract |
| --- | --- |
| `sharing.pending` | Visible batches with status, text, MIME, files and errors |
| `sharing.sources` | Exact registered source paths, leases and reconciliation limits |
| `sharing.retain` / `sharing.bind` | Idempotent batch lease; a different existing transfer binding cannot be overwritten |
| `sharing.consume` | Cancel import/remove UI ownership; keep any leased sources |
| `sharing.release` | Direct release refuses a lease already bound to a task or an uncertain publication |
| `sharing.reconcile` | Reclaim only from complete, validated ownership evidence; keep failed/unknown/ambiguous references |

Task publication is also Rust-owned. `submit_checked` serializes a share's
submission and persists a fingerprint of the complete selected-source request.
A known receipt is reused; an uncertain publication retains its sources and
refuses automatic replay. A definitely unpublished validation failure can reset
the attempt. Repeated engine delivery of an already registered import reuses the
existing batch; a late platform rejection cannot replace it.
[ImportManager submission/command paths](../../crates/interop_core/src/sharing/mod.rs).

`reconcile_shares_from_transfers` groups the relevant push batches in Rust,
preserves each whole group's completion status and first persists/syncs the same
transfer snapshot. Failed persistence prevents reclamation. Reconciliation checks
at most 1,024 references, 2,048 source paths per reference, 8,192 total path entries
and 4,096 characters per path before changing ownership. Oversize/malformed input
does not truncate a supposedly complete snapshot. An incomplete snapshot cannot
authorize release. Unleased pending batches older than one day are candidates
only after complete reference evidence; unknown/damaged directories remain for
review. [Runtime reconciliation](../../crates/interop_core/src/sharing/mod.rs),
[Policy.reconcile](../../crates/interop_core/src/sharing/policy.rs).

Journals preserve application ownership across restart, not the availability of
Android cache storage. Interrupted imports are restored as failures when safe;
unknown ownership is retained. Android may remove cache files independently, and
a missing transfer source must remain a real error.

## Activity and audio boundaries

`ProcessFlutterHost` retains one Flutter engine and installs its custom channels
once. MainActivity supplies that engine and opts out of destroying it with the
Activity. Its weak host reference routes Activity-dependent SAF/share/USB
operations to the current Activity; `usb.release` runs directly in the process
host, so the Rust handoff acknowledgement does not require a live Activity.
The incoming-share observer itself belongs to the process host, so
releasing an old Activity's URI opens does not unbind that observer. A new Dart
bridge configures intake and pulls native pending metadata, covering events
published before its event subscription was ready.
[MainActivity.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/MainActivity.kt),
[ProcessFlutterHost.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/ProcessFlutterHost.kt),
[InteropBridge](../../packages/interop_bridge/lib/interop_bridge.dart).

This does not make multiple native Activities interchangeable views. With the
former `singleTop` launch mode, external shares could create another MainActivity
in another task and evict the original from the shared engine. The local Flutter
SDK's `FlutterActivity.detachFromFlutterEngine` destroys its Flutter view and
detaches its delegate; `onStart`/`onResume` only forward events while the delegate
is still attached, so returning to that original Activity does not reattach it.
The real regression log `/tmp/connect-share-launcher-before.log` records HOME,
MAIN/LAUNCHER return, two UI hosts, detached lifecycle callbacks and SurfaceSync
timeouts, then fails the host-count assertion.

MainActivity now uses `singleTask`. Existing task-root MainActivity instances
receive new intents instead of a second host being created in the exercised
launcher/SEND paths. No explicit Flutter reattachment is needed for that invariant.
The retained engine also retains Dart navigation; Android's task-stack clearing
does not clear Flutter's internal routes. The minimal repeated text/image share,
HOME and launcher regression passed in seven seconds in
`/tmp/connect-share-launcher-after.log`, with one host confirmed by dumpsys and
app assertions for resumed lifecycle and usable device-list UI. This verifies
those routes, not every possible task/document/multi-display arrangement.

`taskAffinity=""` remains intentional: it gives the Activity no task affinity.
It does not itself disable component-based reuse of its existing root task.
`singleTask` clears native Activities above the target in that task; a system
picker above MainActivity may therefore be cancelled by a concurrent incoming
intent. That SAF/result path still needs a dedicated regression. See the
[Android task/back-stack guide](https://developer.android.com/guide/components/activities/tasks-and-back-stack),
[Activity manifest reference](https://developer.android.com/guide/topics/manifest/activity-element),
and [AOSP task matching](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android16-release/services/core/java/com/android/server/wm/RootWindowContainer.java).

The first fixture driver treated `am start` exit zero as proof of sending the
next share. A later run returned “intent has been delivered to currently running
top-most instance” while image still failed. The fixture now reads mode in
`onNewIntent` as well as `onCreate`, and the driver uses `CLEAR_TOP|SINGLE_TOP` to
bring the sender itself to the top and deliver that mode. Text+image then passed;
this is evidence for the combined fixture correction, not an isolated proof
that either change alone fixes all external-app task arrangements. See
[sender](../../tool/e2e/share_fixture/src/dev/scrcpyconnect/sharefixture/ShareFixtureActivity.java)
and [driver](../../tool/driver/incoming_share.dart).

An intermediate full run passed the first four modes, then found that its intended
`no-grant` input arrived ready. Android 16's
`Intent.migrateExtraStreamToClipData` returns early when ClipData already exists;
otherwise its ACTION_SEND/EXTRA_STREAM migration builds ClipData and adds the
read-grant flag. Omitting that flag in the original Java fixture was therefore
insufficient to create a real negative-grant test. The fixture now explicitly
sets ClipData for every URI mode before conditionally adding the flag, preserving
the intended no-grant/self-provider cases through intent preparation. This
explains that fixture's invalid expectation, not a product permission bypass.
[AOSP Android 16 Intent source](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android16-release/core/java/android/content/Intent.java).

The slow fixture also initially failed inside its own metadata query: a nested
Java numeric conditional unboxed the unknown `null` size. It now initializes a
nullable `Long` and assigns known sizes explicitly. The final run therefore
reached an actual `importing` slow pipe before UI cancellation, rather than
mistaking that provider exception for cancellation coverage.

The accompanying native ownership correction gives each Activity/service an
independent discovery-lock token. USB descriptor handoff uses a process registry
capped at 16: Activity destruction abandons only its unhanded leases; once a
descriptor is handed to the asynchronous Rust operation, only the exact lease
acknowledgement releases that original. This prevents a late old Activity cleanup
from closing another Activity's resources. The E2E owner reports JVM contracts
and complete Kotlin compilation passed; physical USB remains unverified.
[NativeLeaseOwnership.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/NativeLeaseOwnership.kt),
[DiscoveryNetwork.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/DiscoveryNetwork.kt).

Audio players now live in Dart `PortableAudioOutputs`/`FvpAudioPlayer` in that
retained engine. `NativeAudioRuntime` owns OS focus leases, visibility and media
foreground-service eligibility; it owns no PCM copy loop or AudioTrack player.
Owner IDs and monotonic focus epochs reject stale cross-owner cleanup/events.
An unfinished focus acquire and its actual release remain barriers before a new
acquire, including after caller timeout. Manual, focus and visibility/background
pause reasons are combined in Dart. Playback readiness requires media information,
confirmed playing state, source PCM packets and an advancing native clock;
receipts explicitly do not claim verified speaker samples.
[portable_audio.dart](../../packages/interop_bridge/lib/src/media/portable_audio.dart),
[fvp_audio_player.dart](../../packages/interop_bridge/lib/src/media/fvp_audio_player.dart),
[NativeAudioRuntime.kt](../../app/android/app/src/main/kotlin/dev/scrcpyconnect/scrcpy_connect/NativeAudioRuntime.kt).

There is no `audio.attach` adoption of old native players. A Dart isolate restart
loses its player objects and one-use streams; bridge initialization retires
unowned Rust captures. Engine restart/destruction releases native system leases.
Explicit Stop stops the OS owner, Rust activities and Dart outputs; Activity
detach alone does not stop approved background audio. Process death, long
background/system reclamation and other platforms remain separate boundaries.
For targets API 35+, Android requires top-app or foreground-service eligibility
for audio-focus requests; requesting a background preference alone is insufficient.
[Android audio focus guide](https://developer.android.com/media/optimize/audio-focus).

Separate real Android evidence is complete for the exercised audio scenarios:
`/tmp/connect-shared-audio-recreate-final.log` records HOME with default pause and
explicit background playback, each with a changed MainActivity identity in the
same PID, followed by passing app assertions. Its
`/tmp/connect-e2e/shared-audio-recreate-final/result.json` contains
`audioAcceptanceComplete:true`. Two real device audio outputs exercised transient
loss, manual pause, gain and permanent loss against an independent AudioManager
fixture; `/tmp/connect-shared-audio-focus-fixed.log` and
`/tmp/connect-e2e/shared-audio-focus-fixed/audio-focus-result.json` record passing
assertions and `audioFocusAcceptanceComplete:true`. These temporary evidence files
were read for this note; they are not committed artifacts and do not verify
speaker content or process recovery.

## Checks and remaining acceptance

The source-level regression suites are now Rust
[share_import.rs](../../crates/interop_core/tests/share_import.rs) and Dart
[share_intake_test.dart](../../packages/interop_bridge/test/share_intake_test.dart).
They cover real host files/FDs, asset ranges, pipes/cancel/deadline, bounds, exact
source ownership, journal restart/migration/failure, duplicate delivery,
publication uncertainty and durable transfer reconciliation. Native ownership
and audio-focus JVM scripts exercise their current Kotlin coordination classes;
they no longer constitute Kotlin filesystem-import tests. These test descriptions
are coverage inventory, not a new execution result from this documentation edit.

```sh
cargo +stable test -p interop-core --test share_import
dart tool/native_contracts.dart ownership
dart tool/native_contracts.dart audio
dart tool/e2e/share_fixture/build.dart
# From packages/interop_bridge:
flutter test test/share_intake_test.dart
```

The real-device target is
[incoming_share_test.dart](../../app/integration_test/incoming_share_test.dart)
with [its external driver](../../tool/driver/incoming_share.dart).
Its nine modes are text, image, multi, alias, no-grant, self-sentinel, too-many,
oversize and slow. A complete run must verify exact provider bytes, errors with
no published files, typed Flutter presentation and cancellation cleanup. The final
metadata records text ready/0 files, image ready/1, multi ready/2, alias ready/1,
no-grant/self-sentinel/too-many/oversize error/0, and slow importing/0 before
Cancel. The source test checks imported image/text bytes and lengths, the expected
error reasons, empty pending shares after Cancel, and deletion of the unsubmitted
ready files. Its completion marker is written only after the whole loop passes.

The standalone nine-mode evidence is `/tmp/connect-incoming-share-final.log`.
The final combined nine-mode, HOME and launcher run passed in 16 seconds in
`/tmp/connect-share-acceptance-final.log`; that log and the final
`/tmp/connect-e2e/incoming-share/result.json` were read for this note. The receipt
contains all nine outcomes above, `launcherResumeWaitMs:4` and
`shareAcceptanceComplete:true`. Host dumpsys confirmed one Android UI host, and
Dart required the real resumed lifecycle and usable device-list UI. The E2E owner
also visually inspected `/tmp/connect-e2e/incoming-share/incoming-image-share.png`:
the shared Unicode filename, 68-byte file and no-connected-device prompt displayed
normally. The same owner visually checked
`/tmp/connect-e2e/incoming-share/devices-after-share-launcher-return.png` and
confirmed the device-list empty state displayed normally after launcher return.
The earlier `/tmp/connect-incoming-share-real.log` is failed diagnostic
evidence, not the acceptance result. APK builds, `am start` exit zero and a
screenshot alone are not substitutes for the complete app assertions/receipt.

Still unverified by this suite: submitting a share to a real 被控设备, retaining
sources through an actual in-flight transfer and process restart, saturation and
malicious/uncooperative providers, the full 120-second deadline, final outgoing
FileProvider resource merging/open-file behavior, Recents/document/multi-display
task arrangements, and a concurrent share while a SAF picker awaits its result.
An earlier combined run in `/tmp/connect-share-nine-launcher-final.log` reached
one host but tested lifecycle immediately after `am start -W`, while Flutter was
still `inactive`. That command does not wait for Flutter window focus. The final
test instead waits at most five seconds for actual `resumed`, preserving the
state requirement; the final receipt above records success after four
milliseconds. The screenshot helper also converts the Flutter surface only once,
as required by the integration-test callback.
The slow case exercises explicit
Cancel while importing; it does not wait for the deadline. The own-provider case
verifies rejection but does not independently demonstrate an attempted provider
open count or a copied private sentinel. Physical USB remains unverified.

**Oversize boundary and former fixture gap:** the original
[FixtureProvider](../../tool/e2e/share_fixture/src/dev/scrcpyconnect/sharefixture/FixtureProvider.java)
advertised 513 MiB via `SIZE` but threw from its own `openFile`, which could not
prove receiver rejection. The corrected fixture supplies a real readable FD in
an `AssetFileDescriptor` with `declaredLength=513 MiB`; the product assertion now
requires the capacity-limit error. That tests Rust's declared-length admission
after the provider was opened, not rejection before provider open and not the
actual-byte overrun path. Android still queries only `DISPLAY_NAME`. The fixture
README's earlier metadata-before-`openFile` expectation is not a current
implementation guarantee. The invalid `file-uri` fixture mode exists but is
outside the default nine-mode test loop.
