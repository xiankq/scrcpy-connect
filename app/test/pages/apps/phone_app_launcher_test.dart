import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/core/control/models/keep_awake_snapshot.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/devices/device_apps.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/media_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/video_sessions.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';

import '../../support/fixed_state.dart';

void main() {
  testWidgets('同一应用不重复打开，换源及离页后的旧核验不继续导航', (tester) async {
    final previous = _Videos();
    final replacement = _Videos();
    final container = ProviderContainer(
      overrides: [videoSessionsProvider.overrideWithValue(previous)],
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

  for (final anchored in [false, true]) {
    testWidgets('应用已有独立画面时先选择移回或切回，取消后不再核验（${anchored ? '锚定菜单' : '底部面板'}）', (
      tester,
    ) async {
      final videos = _Videos();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceListProvider.overrideWith(FixedDeviceList.new),
            videoSessionsProvider.overrideWithValue(videos),
          ],
          child: MaterialApp(home: _Launcher(anchored: anchored)),
        ),
      );
      await tester.tap(find.text('open'));
      videos.reads.single.complete([_appView]);
      await tester.pumpAndSettle();
      expect(find.text('移回手机屏幕'), findsWidgets);
      expect(find.text('切回独立应用'), findsWidgets);
      if (anchored) {
        expect(find.byType(BottomSheet), findsNothing);
        await tester.tapAt(const Offset(760, 550));
      } else {
        await tester.tap(find.text('取消'));
      }
      await tester.pumpAndSettle();
      expect(find.text('切回独立应用'), findsNothing);
      expect(videos.reads, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}

const _appView = VideoSessionView(
  session: VideoSessionSnapshot(
    sessionId: 'app',
    deviceId: 'device',
    name: 'App',
    packageName: 'package',
    kind: .app,
    status: .streaming,
  ),
  wake: KeepAwakeSnapshot(deviceId: 'device'),
);

class _Launcher extends ConsumerWidget {
  const _Launcher({this.anchored = false});
  final bool anchored;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Builder(
      builder: (source) => TextButton(
        onPressed: () => openPhoneApp(
          context,
          ref,
          const DeviceSnapshot(id: 'device'),
          const DeviceApp(packageName: 'package', name: 'App'),
          source: anchored ? source : null,
        ),
        child: const Text('open'),
      ),
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
