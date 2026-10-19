# External Android sharing fixture

This separate APK sends real Android intents and OS read grants to Connect. It
does not link product code, expose a product test route, or access an ADB key.
The provider is not exported; the receiver can read it only after a URI grant.

Build using the installed SDK, without Gradle or a device:

```sh
dart tool/e2e/share_fixture/build.dart
```

The default output is `/tmp/connect-share-fixture/share-fixture.apk`. The generated
test signing key and intermediates stay outside the repository. The key is for
this fixture only. Install/operate only the controller assigned by the E2E owner:

```sh
/home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 install -r /tmp/connect-share-fixture/share-fixture.apk
/home/xiankq/Android/Sdk/platform-tools/adb -s emulator-5554 shell am start -n dev.scrcpyconnect.sharefixture/.ShareFixtureActivity --es mode image
```

Replace `image` with a mode below. Each launch targets the real product Activity.
The buttons offer the same operations interactively. Do not run commands while
another agent owns that controller or an existing drive is in progress.

| Mode | Actual input | Expected product boundary |
| --- | --- | --- |
| `text` | Unicode text, no stream | One ready text share |
| `image` | Tiny PNG through provider pipe + read grant + ClipData | File bytes and Unicode display name preserved |
| `multi` | Text and PNG, separate granted URIs | One batch, two files |
| `alias` | Same provider, alternative declared authority | Valid foreign alias accepted |
| `no-grant` | Foreign provider URI without read flag | Rejected before opening |
| `self-sentinel` | Product's own provider URI, no read grant | Rejected as own-provider input, no sentinel copied |
| `file-uri` | Nonexistent `file://` path | OS or product rejects; no file read |
| `too-many` | 33 distinct granted content URIs | Rejected before copying any file |
| `oversize` | Readable pipe with an AssetFileDescriptor declaring 513 MiB | Rust rejects declared capacity before copying; fixture does not throw the rejection itself |
| `slow` | Pipe producing one byte/sec for at most 180 sec | Cancel/deadline publishes no partial file; UI remains responsive |

`self-sentinel` names only
`content://dev.scrcpyconnect.scrcpy_connect.fileProvider.com.crazecoder.openfile/media/share-trust-sentinel.txt`.
For a stronger E2E assertion, the test owner may create a harmless known string at
the debug product's `files/media/share-trust-sentinel.txt` and assert it never
appears in incoming batches. This fixture must never be changed to use a real
identity, credential or user file. It never reads the sentinel itself.

For queue admission, repeatedly send `slow`, retaining each pending share, until
the eight-batch visible guard rejects the next request. Confirm no directory/file
appears for the rejected request. For consume/transfer ownership, first submit a
ready batch through normal UI, consume it while its transfer is running, and
assert its registered source remains until the complete transfer reconciliation.
An Activity recreation should keep the same playing source ID without a new
remote audio capture; full process death is a separate boundary.

The automated driver launches the sender with `CLEAR_TOP | SINGLE_TOP` and the
sender accepts `onNewIntent`. Without those flags, Android may only foreground
the existing task: an exit code of zero does not prove another share was sent.
The product's real pending batch, file bytes and live Flutter route are the
acceptance signal. The nine-mode run is:

```sh
env CONNECT_E2E_DEVICE=emulator-5554 \
  CONNECT_E2E_ADB=/home/xiankq/Android/Sdk/platform-tools/adb \
  flutter drive -d emulator-5554 --no-pub \
  --driver=tool/driver/incoming_share.dart \
  --target=integration_test/incoming_share_test.dart
```

For a minimized run add `--dart-define=CONNECT_SHARE_MODES=text,image`.
The driver requires `shareAcceptanceComplete=true` and stores metadata and
screenshots in `/tmp/connect-e2e/incoming-share`. Build success alone does not
establish device acceptance. See the [research record](../../../docs/research/android-share-trust.md)
for completed checks and outstanding boundaries.
