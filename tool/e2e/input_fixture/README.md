# Android input and lifecycle fixture

`dart tool/e2e/input_fixture/build.dart` writes the independent APK/classes/key to `/tmp/connect-input-fixture`. `InputReceiverActivity` records real input delivery. The same archive's `ActivityLifecycle` shell entrypoint calls ActivityManager `setAlwaysFinish`; changing only the settings database cannot force recreation.

For a dedicated authorized controller/target, run:

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

The driver pushes the archive to a unique target path without installation, checks a new Activity in the same PID/isolate with policy-correct audio clocks/FGS, then restores the prior runtime/database setting and removes the archive. This does not cover process death, Doze or physical speakers.
