import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_management.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';

void main() {
  testWidgets('同一应用不重复打开，换源及离页后的旧核验不继续导航', (tester) async {
    final previous = _Videos();
    final replacement = _Videos();
    final settings = settingsManagementProvider.overrideWithValue(_Settings());
    final container = ProviderContainer(
      overrides: [videoSessionsProvider.overrideWithValue(previous), settings],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _Launcher()),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.tap(find.text('open'));
    expect(previous.reads, hasLength(1));
    container.updateOverrides([
      videoSessionsProvider.overrideWithValue(replacement),
      settings,
    ]);
    await tester.pump();
    previous.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('open'));
    expect(replacement.reads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Launcher extends ConsumerWidget {
  const _Launcher();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      onPressed: () => openPhoneApp(
        context,
        ref,
        const DeviceSnapshot(id: 'device'),
        const DeviceApp(packageName: 'package', name: 'App'),
      ),
      child: const Text('open'),
    ),
  );
}

class _Videos implements VideoSessions {
  final reads = <Completer<List<VideoSessionView>>>[];
  @override
  Future<List<VideoSessionView>> readVideoSessions({String? deviceId}) {
    final result = Completer<List<VideoSessionView>>();
    reads.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsManagement {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
