import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_capabilities_provider.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_focus_notifier.dart';
import 'package:scrcpy_connect/core/clipboard/clipboard_sync_notifier.dart';
import 'package:scrcpy_connect/core/clipboard/models/clipboard_sync_state.dart';
import 'package:scrcpy_connect/core/clipboard/models/remote_clipboard_changed.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/devices/device_reader.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/models/device_disconnect_requested.dart';
import 'package:scrcpy_connect/core/lifecycle/app_session_provider.dart';
import 'package:scrcpy_connect/core/lifecycle/models/app_state.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('剪贴板换源立即撤销原准入，重新建基线后仅同步新捕获事件', () async {
    final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    final dependencies = _Session(events.stream);
    final previous = _Clipboard();
    final replacement = _Clipboard();
    var local = 'local baseline';
    final writes = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': local};
      if (call.method == 'Clipboard.setData') {
        local = (call.arguments as Map)['text'] as String;
        writes.add(local);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final container = ProviderContainer(
      overrides: [
        appSessionProvider.overrideWithValue(dependencies),
        deviceReaderProvider.overrideWithValue(dependencies.devices),
        settingsManagementProvider.overrideWithValue(dependencies.settings),
        remoteClipboardProvider.overrideWithValue(previous),
      ],
    );
    container.listen(clipboardSyncProvider, (_, _) {});
    final focus = container
        .read(clipboardFocusProvider.notifier)
        .claim('device');
    focus.focus('session', true);
    container
        .read(clipboardSyncProvider.notifier)
        .setVisibility(foreground: true, focused: true);
    await flush(container);
    final oldTarget = previous.reads.single;
    expect(
      previous.admission!(
        'device',
        'session',
        oldTarget.synchronizationGeneration!,
      ),
      isTrue,
    );
    container.updateOverrides([
      appSessionProvider.overrideWithValue(dependencies),
      deviceReaderProvider.overrideWithValue(dependencies.devices),
      settingsManagementProvider.overrideWithValue(dependencies.settings),
      remoteClipboardProvider.overrideWithValue(replacement),
    ]);
    expect(
      previous.admission!(
        'device',
        'session',
        oldTarget.synchronizationGeneration!,
      ),
      isFalse,
    );
    await flush(container);
    expect(previous.releases, 1);
    expect(replacement.reads, hasLength(1));
    previous.reading.complete(
      const RemoteClipboardText(text: 'late old baseline'),
    );
    replacement.reading.complete(
      const RemoteClipboardText(
        text: 'new remote baseline',
        capture: ClipboardCapture(reference: 'capture', generation: 2),
      ),
    );
    await flush(container);
    expect(
      container.read(clipboardSyncProvider).status,
      ClipboardSyncStatus.watching,
    );
    expect(writes, isEmpty);
    for (final stale in [
      const RemoteClipboardChanged(
        deviceId: 'device',
        connectionId: 'previous-connection',
        sessionId: 'session',
        capture: ClipboardCapture(reference: 'capture', generation: 2),
        text: 'old connection',
      ),
      const RemoteClipboardChanged(
        deviceId: 'device',
        connectionId: 'connection',
        sessionId: 'session',
        capture: ClipboardCapture(reference: 'capture', generation: 1),
        text: 'old capture',
      ),
      const RemoteClipboardChanged(
        deviceId: 'device',
        connectionId: 'connection',
        sessionId: 'previous-session',
        capture: ClipboardCapture(reference: 'capture', generation: 2),
        text: 'old session',
      ),
    ]) {
      events.add(stale.toApplicationEvent());
    }
    await flush(container);
    expect(writes, isEmpty);
    events.add(
      const RemoteClipboardChanged(
        deviceId: 'device',
        connectionId: 'connection',
        sessionId: 'session',
        capture: ClipboardCapture(reference: 'capture', generation: 2),
        text: 'new copy',
      ).toApplicationEvent(),
    );
    await flush(container);
    expect(writes, ['new copy']);
    expect(container.read(clipboardSyncProvider).writeCount, 1);
    events.add(
      const DeviceDisconnectRequested('another-device').toApplicationEvent(),
    );
    await flush(container);
    expect(
      container.read(clipboardSyncProvider).status,
      ClipboardSyncStatus.watching,
    );
    events.add(const DeviceDisconnectRequested('device').toApplicationEvent());
    expect(
      replacement.admission!(
        'device',
        'session',
        replacement.reads.single.synchronizationGeneration!,
      ),
      isFalse,
    );
    await flush(container);
    expect(
      container.read(clipboardSyncProvider).status,
      ClipboardSyncStatus.waitingDevice,
    );
    expect(replacement.reads, hasLength(1));
    focus.dispose();
    container.dispose();
    expect(replacement.releases, 1);
    await events.close();
  });
}

Future<void> flush(ProviderContainer container) async {
  await Future<void>.delayed(Duration.zero);
  await container.pump();
  await Future<void>.delayed(Duration.zero);
}

class _Clipboard implements RemoteClipboard {
  final reading = Completer<RemoteClipboardText>();
  final reads = <WindowClipboardTarget>[];
  bool Function(String, String, int)? admission;
  int releases = 0;
  @override
  void Function() bindClipboardAdmission(
    bool Function(String, String, int) check,
  ) {
    admission = check;
    return () {
      releases++;
    };
  }

  @override
  Future<RemoteClipboardText> readClipboard(ClipboardTarget target) {
    reads.add(target as WindowClipboardTarget);
    return reading.future;
  }

  @override
  Future<void> writeClipboard(ClipboardTarget target, String text) async =>
      throw StateError('unexpected replay');
}

class _Session implements AppSession {
  _Session(this.events);
  @override
  final Stream<Map<String, dynamic>> events;
  @override
  final initialState = AppState(
    devices: [
      const DeviceSnapshot(
        id: 'device',
        status: .connected,
        connectionId: 'connection',
      ),
    ],
    focusedDeviceId: 'device',
    loading: false,
    settings: Preferences(
      deviceSettings: {'device': const DevicePreferences(clipboardSync: true)},
    ),
  );
  final DeviceReader devices = _Devices();
  final SettingsManagement settings = _Settings();
  @override
  bool get initialize => false;
  @override
  Future<void> Function()? get close => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Devices implements DeviceReader {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
