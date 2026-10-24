import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/media/control_page_registry.dart';

void main() {
  test('a newer presentation owns the same real window and stale release cannot affect it', () {
    final pages = ControlPageRegistry();
    final old = pages.claim('phone', sessionId: 'same-window');
    final current = pages.claim('phone', sessionId: 'same-window');
    expect(pages.release(old), isFalse);
    expect(pages.hasPages('phone'), isTrue);
    expect(pages.release(current), isTrue);
    expect(pages.hasPages('phone'), isFalse);
  });
  test('the final distinct window includes independent sessions and stays scoped to its device', () {
    final pages = ControlPageRegistry();
    final phone = pages.claim('phone', sessionId: 'phone-screen');
    final app = pages.claim('phone', sessionId: 'app-window');
    final otherDevice = pages.claim('other', sessionId: 'other-screen');
    expect(pages.release(phone), isFalse);
    expect(pages.release(app), isTrue);
    expect(pages.hasPages('phone'), isFalse);
    expect(pages.hasPages('other'), isTrue);
    expect(pages.release(otherDevice), isTrue);
    expect(pages.release(app), isFalse);
  });
}
