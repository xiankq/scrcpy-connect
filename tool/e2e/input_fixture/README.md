# Independent Android input and lifecycle fixture

Build with `dart tool/e2e/input_fixture/build.dart`. The APK, classes,
and test signing key stay in `/tmp/connect-input-fixture`. They are not product
dependencies. `InputReceiverActivity` records actual Android input delivery for
the opt-in input-release test.

`ActivityLifecycle` is a separate host shell entrypoint in the same test archive.
The audio driver pushes that archive to a unique `/data/local/tmp` path and runs
it through `app_process`, without installing it. It calls ActivityManager's
`setAlwaysFinish` using the authorized test shell, so leaving the foreground
actually destroys the Activity. Changing the settings database alone does not
change the runtime flag; see [AOSP implementation](https://android.googlesource.com/platform/frameworks/base/+/2f5bb9c5ff88/services/core/java/com/android/server/am/ActivityManagerService.java).
This is a testing mechanism, not a permission or debugging requirement for users.

For an isolated controller, run from 仓库根目录 after ensuring the target is
authorized and reachable:

```sh
cd app
env CONNECT_E2E_DEVICE=emulator-5554 \
  CONNECT_E2E_ADB=/absolute/android-sdk/platform-tools/adb \
  CONNECT_E2E_AUDIO_LIFECYCLE=1 CONNECT_E2E_RECREATE_ACTIVITY=1 \
  CONNECT_E2E_ACTIVITY_FIXTURE=/tmp/connect-input-fixture/input-fixture.apk \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/shared-audio-recreate \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../tool/driver/integration_test.dart \
  --target=integration_test/audio_lifecycle_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_E2E_AUDIO_LIFECYCLE=true
```

The host verifies a different actual Activity identity in the same PID, while
the existing Dart isolate/source continues. It checks paused or progressing
playback clocks according to policy and the actual mediaPlayback foreground
service type. Cleanup restores the previous runtime/database setting and removes
the pushed archive before the host driver exits. Process death, Doze and physical
speaker output are separate tests; this fixture does not prove them.
