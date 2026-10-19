import 'package:flutter_test/flutter_test.dart';

import '../check_android.dart';

const manifest =
    '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<application android:allowBackup="false" android:usesCleartextTraffic="false">
<activity android:name="dev.scrcpyconnect.MainActivity" android:launchMode="singleTask"/>
<service android:name="dev.scrcpyconnect.ConnectionService" android:exported="false" android:foregroundServiceType="connectedDevice|mediaPlayback"/>
</application></manifest>''';

void main() {
  test('accepts packaged enum names and compiled numeric values', () {
    for (final mode in ['singleTask', '2', '0x2']) {
      for (final types in [
        'connectedDevice|mediaPlayback',
        'mediaPlayback|connectedDevice',
        '18',
        '0x12',
      ]) {
        expect(
          () => verifyManifest(
            manifest
                .replaceFirst('singleTask', mode)
                .replaceFirst('connectedDevice|mediaPlayback', types),
          ),
          returnsNormally,
        );
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
          'android:exported="false"',
          'android:exported="true"',
        ),
        manifest.replaceFirst('connectedDevice|mediaPlayback', 'mediaPlayback'),
        manifest.replaceFirst(
          'connectedDevice|mediaPlayback',
          'connectedDevice|mediaPlayback|location',
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
