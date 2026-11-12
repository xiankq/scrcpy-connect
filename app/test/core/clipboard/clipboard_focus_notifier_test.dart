import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/events/runtime_events_provider.dart';

void main() {
  test('同一会话的新页面接管焦点后，旧页面失焦及离页不撤销新租约', () {
    final container = ProviderContainer(
      overrides: [
        runtimeEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);
    final focus = container.read(clipboardFocusProvider.notifier);
    final previous = focus.claim('device');
    final current = focus.claim('device');
    previous.focus('session', true);
    current.focus('session', true);
    previous.focus('session', false);
    previous.dispose();
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    current.focus('session', false);
    expect(container.read(clipboardFocusProvider), isNull);
    current.focus('other-session', true);
    current.dispose();
    expect(container.read(clipboardFocusProvider), isNull);
    current.focus('session', true);
    expect(container.read(clipboardFocusProvider), isNull);
  });

  test('换源立即撤销旧焦点准入，旧页面的迟到焦点不写入新作用域', () async {
    final container = ProviderContainer(
      overrides: [runtimeEventsProvider.overrideWithValue(Stream.empty())],
    );
    addTearDown(container.dispose);
    final previous = container
        .read(clipboardFocusProvider.notifier)
        .claim('device');
    previous.focus('session', true);
    container.updateOverrides([
      runtimeEventsProvider.overrideWithValue(Stream.empty()),
    ]);
    previous.focus('late-session', true);
    await container.pump();
    expect(container.read(clipboardFocusProvider), isNull);
    final current = container
        .read(clipboardFocusProvider.notifier)
        .claim('device');
    current.focus('session', true);
    previous.focus('late-session', true);
    previous.dispose();
    expect(container.read(clipboardFocusProvider)?.sessionId, 'session');
    container.dispose();
    current.dispose();
  });
}
