# External Android sharing fixture

Independent APK sends real intents/read grants to Connect through a non-exported provider. Build with `dart tool/e2e/share_fixture/build.dart`; APK/key/intermediates stay in `/tmp/connect-share-fixture`.

On the assigned isolated controller, require `pm path dev.scrcpyconnect.sharefixture` to be empty; never replace an existing install or run alongside another device owner. The driver installs and removes only its own fixture. Manual entry is `.ShareFixtureActivity` with string extra `mode`:

| Mode | Input and expected boundary |
| --- | --- |
| `text` | Unicode text → ready text share |
| `image` | Granted PNG pipe + ClipData → exact bytes/Unicode name |
| `multi` | Two granted files → one batch |
| `alias` | Alternate declared authority → accepted foreign provider |
| `no-grant` | No read flag → reject before open |
| `self-sentinel` | Own-provider URI → reject without copying |
| `file-uri` | Nonexistent file URI → OS/product rejects |
| `too-many` | 33 URIs → reject before copying |
| `oversize` | Readable pipe declares 513 MiB → Rust rejects before copying |
| `slow` | One byte/sec, at most 180 sec → cancellation/deadline publishes no partial |

`self-sentinel` is only `content://dev.scrcpyconnect.scrcpy_connect.fileProvider.com.crazecoder.openfile/media/share-trust-sentinel.txt`. An optional known harmless marker may be placed at debug-product `files/media/share-trust-sentinel.txt`; never substitute credentials, identities or user files.

```sh
cd app
env CONNECT_E2E_DEVICE=emulator-5554 \
  CONNECT_E2E_ADB=/absolute/android-sdk/platform-tools/adb \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/incoming_share.dart \
  --target=integration_test/incoming_share_test.dart
```

Use `--dart-define=CONNECT_SHARE_MODES=text,image` for a subset. The driver uses `CLEAR_TOP|SINGLE_TOP`/`onNewIntent` and validates actual batches, bytes and route, requiring `shareAcceptanceComplete=true`. Reports default to `/tmp/connect-e2e/incoming-share`.

Additional manual boundaries: retain eight pending `slow` batches and confirm the next request creates no files; consume a batch during transfer and verify its source remains until durable reconciliation. See [share trust research](../../../docs/research/android-share-trust.md).
