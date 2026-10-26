# Android input and lifecycle fixture

`dart scripts/build_fixture.dart input` writes the independent APK and test signing cache to `/tmp/connect-input-fixture`. `InputReceiverActivity` records real input delivery. `ActivityLifecycle` calls real `setAlwaysFinish`, not just the settings database.

For a dedicated authorized controller/target, run:

```sh
cd app
env CONNECT_E2E_DEVICE=emulator-5554 \
  CONNECT_E2E_ADB=/absolute/android-sdk/platform-tools/adb \
  CONNECT_E2E_AUDIO_LIFECYCLE=1 CONNECT_E2E_RECREATE_ACTIVITY=1 \
  CONNECT_E2E_ACTIVITY_FIXTURE=/tmp/connect-input-fixture/input-fixture.apk \
  CONNECT_E2E_CAPTURE_DIR=/tmp/connect-e2e/shared-audio-recreate \
  flutter drive -d emulator-5554 --no-pub \
  --driver=../test/driver/integration_test.dart \
  --target=integration_test/audio_lifecycle_test.dart \
  --dart-define=CONNECT_E2E_ADDRESS=10.0.2.2 \
  --dart-define=CONNECT_E2E_PORT=15556 \
  --dart-define=CONNECT_E2E_AUDIO_LIFECYCLE=true
```

The driver restores the original Activity setting and removes its archive. Use a dedicated authorized target; this covers Activity recreation, not process death or audible output.

Input-release coverage uses `driver/input.dart` with `integration_test/native_input_release_test.dart`. Explicitly set `CONNECT_E2E_DEVICE` and `CONNECT_E2E_TARGET` to distinct dedicated emulators, and `CONNECT_E2E_INPUT_APK` to this APK.
