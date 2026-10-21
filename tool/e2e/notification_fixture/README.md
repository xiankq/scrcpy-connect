# Independent notification receiver fixture

This API36-only APK creates synthetic notifications and receives their original
RemoteInput PendingIntent in a real AMS-managed app process. It has no product
dependency, ADB identity, network access, provider, or real message content.
Its receiver is not exported. The product and temporary companion JAR do not
include any of these classes.

This is an acceptance fixture, not an additional APK required by the product.
The older shell-JAR receiver probe remains a separate failing boundary on API36:
its null ApplicationThread is rejected by receiver registration. A system
PendingIntent acceptance result alone does not prove receipt by an application.

Build locally with the installed SDK 36 and build-tools 36.0.0:

```sh
dart tool/e2e/notification_fixture/build.dart
```

The signed APK is `/tmp/connect-notification-fixture/notification-fixture.apk`.
The disposable signing key and intermediate files also remain below `/tmp`.
The script neither accesses a device nor installs anything, changes permissions,
or rebuilds product artifacts. `--output` must stay below `/tmp`.

The package is `dev.scrcpyconnect.notificationfixture`; the exported Activity is
`.NotificationFixtureActivity`. Every command requires a string extra `runId`
matching `[A-Za-z0-9_-]{1,80}`. Use a fresh random UUID hex value per run.

| Activity action | Behavior |
| --- | --- |
| `dev.scrcpyconnect.notificationfixture.CREATE` | Creates this run's channel and four notifications; refuses to replace an existing run |
| `dev.scrcpyconnect.notificationfixture.OPEN` | Presents this original notification's fixture Activity |
| `dev.scrcpyconnect.notificationfixture.CLEANUP` | Closes this run's receiver eligibility, cancels its notifications and PendingIntents, preserves its final receipt in a cleanup record, deletes the original receipt/state/channel, then removes the Activity task |

Tag and channel ID are both `notification-fixture-<runId>`. Titles are exactly
`<runId>-0` through `<runId>-3`. IDs are scoped by the run's notification tag:

| Original notification ID | Fixture action |
| --- | --- |
| `0` | Mutable PendingIntent targeting the explicit, non-exported `ReplyReceiver`, with free-form RemoteInput |
| `1` | Immutable PendingIntent without RemoteInput; Android rejects immutable actions that carry RemoteInput at posting time |
| `2` | Mutable RemoteInput action marked `authenticationRequired` |
| `3` | Content PendingIntent canceled after posting |

The original RemoteInput result key is `original-result-key`. The receiver reads
the actual delivered intent via `RemoteInput.getResultsFromIntent`, then
atomically publishes only synthetic test data in private app files. It does not
write a receipt when the original result is missing or invalid.

After CREATE, poll with `adb -s <explicit-target> shell run-as
dev.scrcpyconnect.notificationfixture cat files/runs/<runId>.json` until it is:

```json
{"runId":"<runId>","status":"ready","tag":"notification-fixture-<runId>","channel":"notification-fixture-<runId>","notificationIds":[0,1,2,3]}
```

Creation errors instead publish `status: "error"` with an error string when
possible, and log under `NotificationFixture`. An `am start` return code is not
proof that posting or cleanup completed.

Read the independent reply receipt using `run-as` and
`files/receipts/<runId>.json`. A successful first reply to ID0 has this shape:

```json
{"runId":"<runId>","messageId":"<runId>:0","notificationId":0,"text":"the exact synthetic reply, including Unicode","count":1}
```

`count` increases for every valid delivery in this run, including delivery from
the authentication-required action if an erroneous caller bypasses its guard.
The driver must check all identity fields, exact text, and `count == 1`; checking
only that a receipt exists cannot detect a replay or wrong notification.

CLEANUP closes the run on the same main thread that executes the receiver,
cancels its PendingIntents, and atomically snapshots the final receipt into
`files/cleanup/<runId>.json` before deleting the original receipt and state:

```json
{"runId":"<runId>","status":"cleaned","finalReceipt":{"runId":"<runId>","messageId":"<runId>:0","notificationId":0,"text":"the exact synthetic reply, including Unicode","count":1}}
```

`finalReceipt` is null if no valid reply was received. The driver must read this
final snapshot before uninstalling, so a second delivery between its earlier
read and CLEANUP cannot silently lose the increased count. Callbacks queued
after eligibility closes cannot process the reply. Repeated CLEANUP preserves
the original final snapshot, and CREATE refuses reuse of a runId with existing
cleanup evidence. Uninstallation releases that run's cleanup record.

The harness owns installation and must follow this lifecycle on its explicitly
assigned emulator, without touching another emulator or existing package:

1. Read `pm path dev.scrcpyconnect.notificationfixture` and refuse to continue
   if stdout names an existing installation. Do not use `install -r` or remove
   an installation that predates this run.
2. Install the freshly built APK and record successful ownership of this new
   installation. Only then grant this fixture package's declared
   `android.permission.POST_NOTIFICATIONS` runtime permission. Do not change
   the product's permissions, listener grants, AppOps, or background settings.
3. Launch the explicit CREATE Activity action with this runId, wait for its
   private `ready` state, and find its exact tagged notifications through the
   real product path. Read receipts through `run-as`, not through the product.
4. In `finally`, send the explicit CLEANUP action for this runId. Independently
   verify that its receipt/state files are absent and its active notifications
   are absent. Read the cleanup snapshot and verify its final receipt identity,
   exact text and count. Android may retain deleted channel metadata; it is not
   an active notification.
5. Uninstall only the fixture installation created by this run, including after
   test failure, and verify `pm path` no longer reports it. Preserve earlier
   failures when reporting cleanup errors.

No physical device, notification permission, install, or receiver delivery was
validated by a local APK build. The independently observed receipt and cleanup
are required runtime evidence.


## Flutter acceptance driver

Use two isolated API36 AVDs and a prepared legacy TCP endpoint. The driver refuses
any pre-existing installation, installs without replacement, grants only this
new fixture's requested POST_NOTIFICATIONS permission, and uninstalls only its
owned installation. It never modifies the product's permissions or AppOps.
Before the copy check, put a known temporary plain-text clipboard baseline on
the controller. The test requires a readable text baseline before writing and
restores that text; it does not claim restoration of arbitrary ClipData/MIME or
an originally empty clipboard.

From `app/`, with Flutter on PATH:

```sh
env CONNECT_E2E_ADB=/absolute/android-sdk/platform-tools/adb \
  CONNECT_E2E_TARGET=emulator-5556 \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/notification-reply \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/notification_reply.dart \
  --target=integration_test/notification_reply_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556
```

A fresh run ID is delivered through a runtime handshake. The UI submits the
original reply, returns to it, clears only notification 0, then copies the
retained text from its expired route. The driver checks the receiver's private
AtomicFile receipt and its final cleanup snapshot for exactly one matching
Unicode reply. Missing UI/report/receipt, a duplicate, mismatched text, failure
to restore the text baseline, or unconfirmed cleanup fails acceptance.
`notificationReplyComplete` is scoped to this fixture; neither a product-wide
completion nor delivery by a real chat application/message service is claimed.


## Notification requirements mode

`CREATE_REQUIREMENTS` creates two clearable sources (IDs 0 and 1) and a source
with Android's `FLAG_NO_CLEAR` (ID 4). `POST_REQUIREMENT` adds ID 5;
`WITHDRAW_REQUIREMENT` cancels ID 5 from inside the source application. These
commands use a fresh run ID and are separate from the original reply scenario.
The application declares its actual application icon so `apps.icon` can return
it; the source small icon is not substituted for the application icon.
An original content PendingIntent writes `files/opens/<runId>.json` with the run,
notification ID and invocation count. CLEANUP deletes that receipt as well as
the run and reply receipts and cancels IDs 0 through 5.

The scoped driver is `tool/driver/notification_requirements.dart`, paired with
`app/integration_test/notification_requirements_test.dart`. It requires distinct
isolated API36 controller and target AVDs, the same endpoint defines as above,
and `CONNECT_E2E_DEVICE` for the controller. The target must contain only test
data because the real **全部已读** UI intentionally clears all clearable sources.
The driver checks independent Android source/host records and the original OPEN
receipt, including a temporary target PIN/keyguard round trip. Its finally path
removes that PIN, cancels only its own sources and removes only its owned APK.
The target AVD is kept running for subsequent acceptance.

When Flutter integration instrumentation owns Android UiAutomation, set
`CONNECT_E2E_MANUAL_SYSTEM_UI=1` to leave normal notification-permission and ADB
authorization dialogs to the operator. Approve the visible system dialogs; do
not grant the product permission or authorization with shell commands. The
source, OPEN, keyguard, clearing, OS mirror and withdrawal assertions still run
automatically. The report records this mode.

## Snapshot consistency mode

`CREATE_SNAPSHOT` posts BigText (different collapsed/expanded title), Inbox
(two actual message lines), and MessagingStyle notifications for a fresh run.
`UPDATE_SNAPSHOT` replaces only this run's ID0 with a new expanded title/body.
The companion `notification-snapshot.dart` probe compares the real target
service snapshot, checks stable ownership and changed action revisions, then
uses CLEANUP and verifies removal before uninstalling its owned APK.
These actions never enter the product APK or companion JAR.
