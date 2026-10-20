import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/remote_display_settings.dart';
import 'package:scrcpy_connect/services/device_screen_policy.dart';

void main() {
  test('custom ratios reject non-finite and extreme dimensions', () {
    for (final input in [
      '0:1',
      '-1:2',
      'NaN:2',
      'Infinity:1',
      '6:1',
      '1',
      '1:2:3',
    ]) {
      expect(RemoteDisplaySettings.parseRatio(input), isNull, reason: input);
    }
    expect(RemoteDisplaySettings.parseRatio(' 9 ： 16 '), 9 / 16);
  });
  test(
    'only the final phone page can trigger lock; repeated release is inert',
    () {
      final policy = DeviceScreenPolicy();
      final first = policy.claimPhonePage('phone');
      final second = policy.claimPhonePage('phone');
      final other = policy.claimPhonePage('other');
      expect(policy.releasePhonePage(first), isFalse);
      expect(policy.releasePhonePage(second), isTrue);
      expect(policy.releasePhonePage(second), isFalse);
      expect(policy.hasPhonePages('other'), isTrue);
      expect(policy.releasePhonePage(other), isTrue);
    },
  );
}
