import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/device_screen_policy.dart';

void main() {
  test('a newer presentation owns the same real window and stale release cannot affect it', () {
    final policy = DeviceScreenPolicy();
    final old = policy.claimPhonePage('phone', sessionId: 'same-window');
    final current = policy.claimPhonePage('phone', sessionId: 'same-window');
    expect(policy.releasePhonePage(old), isFalse);
    expect(policy.hasPhonePages('phone'), isTrue);
    expect(policy.releasePhonePage(current), isTrue);
    expect(policy.hasPhonePages('phone'), isFalse);
  });
  test('the final distinct window includes independent sessions and stays scoped to its device', () {
    final policy = DeviceScreenPolicy();
    final phone = policy.claimPhonePage('phone', sessionId: 'phone-screen');
    final app = policy.claimPhonePage('phone', sessionId: 'app-window');
    final otherDevice = policy.claimPhonePage(
      'other',
      sessionId: 'other-screen',
    );
    expect(policy.releasePhonePage(phone), isFalse);
    expect(policy.releasePhonePage(app), isTrue);
    expect(policy.hasPhonePages('phone'), isFalse);
    expect(policy.hasPhonePages('other'), isTrue);
    expect(policy.releasePhonePage(otherDevice), isTrue);
    expect(policy.releasePhonePage(app), isFalse);
  });
}
