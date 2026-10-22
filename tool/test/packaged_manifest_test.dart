import 'package:flutter_test/flutter_test.dart';

import '../check_android.dart';

const manifest =
    '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<application android:allowBackup="false" android:usesCleartextTraffic="false">
<activity android:name="dev.scrcpyconnect.MainActivity" android:launchMode="singleTask"/>
<service android:name="dev.scrcpyconnect.ConnectionService" android:exported="false" android:foregroundServiceType="connectedDevice"/>
<service android:name="dev.scrcpyconnect.AudioPlaybackService" android:exported="false" android:foregroundServiceType="mediaPlayback"/>
</application></manifest>''';

void main() {
  test('accepts packaged enum names and compiled numeric values', () {
    for (final mode in ['singleTask', '2', '0x2']) {
      for (final connectionType in ['connectedDevice', '16', '0x10']) {
        for (final audioType in ['mediaPlayback', '2', '0x2']) {
          expect(
            () => verifyManifest(
              manifest
                  .replaceFirst('singleTask', mode)
                  .replaceFirst('connectedDevice', connectionType)
                  .replaceFirst('mediaPlayback', audioType),
            ),
            returnsNormally,
          );
        }
      }
    }
  });
  test(
    'rejects missing components, exposed services and relaxed manifest flags',
    () {
      for (final mutation in [
        manifest.replaceFirst(
          'android:allowBackup="false"',
          'android:allowBackup="true"',
        ),
        manifest.replaceFirst('android:usesCleartextTraffic="false"', ''),
        manifest.replaceFirst('singleTask', 'singleTop'),
        manifest.replaceFirst('.MainActivity', '.OtherActivity'),
        manifest.replaceFirst(
          'ConnectionService" android:exported="false"',
          'ConnectionService" android:exported="true"',
        ),
        manifest.replaceFirst(
          'AudioPlaybackService" android:exported="false"',
          'AudioPlaybackService" android:exported="true"',
        ),
        manifest.replaceFirst('ConnectionService', 'OtherConnectionService'),
        manifest.replaceFirst(
          'AudioPlaybackService',
          'OtherAudioPlaybackService',
        ),
        manifest.replaceFirst(
          'android:foregroundServiceType="connectedDevice"',
          'android:foregroundServiceType="mediaPlayback"',
        ),
        manifest.replaceFirst(
          'android:foregroundServiceType="mediaPlayback"',
          'android:foregroundServiceType="connectedDevice"',
        ),
        manifest.replaceFirst(
          'connectedDevice',
          'connectedDevice|mediaPlayback',
        ),
        manifest.replaceFirst('mediaPlayback', 'mediaPlayback|location'),
        manifest.replaceFirst(
          'android:name="dev.scrcpyconnect.MainActivity"',
          'android:name="dev.scrcpyconnect.OtherActivity"',
        ),
        '<manifest/>',
      ]) {
        expect(
          () => verifyManifest(mutation),
          throwsStateError,
          reason: mutation,
        );
      }
    },
  );
}
