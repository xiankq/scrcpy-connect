import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scrcpy_connect/pages/device_workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/gallery/gallery_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/clipboard_coordinator.dart';

import 'support/test_controller.dart';

const _devices = <Json>[
  {'id': 'a', 'name': '设备 A', 'status': 'connected'},
  {'id': 'b', 'name': '设备 B', 'status': 'connected'},
  {'id': 'c', 'name': '设备 C', 'status': 'connected'},
];

class _Backend {
  final calls = <(String, Json)>[];
  final events = StreamController<Json>.broadcast(sync: true);
  final lookups = <String, Future<Json>>{};
  final sessions = <String, Json>{};
  String? audioDevice;
  late final controller = createTestController(request, events: events.stream)
    ..loading = false
    ..devices = _devices;

  Future<Json> request(String command, [Json params = const {}]) async {
    calls.add((command, params));
    switch (command) {
      case 'device.info':
        final id = value(params, 'deviceId');
        final lookup = lookups[id];
        if (lookup != null) return lookup;
        return _devices.firstWhere((device) => device['id'] == id);
      case 'devices.list':
        return {'devices': _devices};
      case 'files.list':
        return {'entries': <Json>[]};
      case 'media.list':
        return {'items': <Json>[]};
      case 'clipboard.get':
        return {'text': '${params['deviceId']} baseline'};
      case 'audio.sources':
        return {
          'sources': [
            if (audioDevice != null)
              {
                'sourceId': 'source-$audioDevice',
                'deviceId': audioDevice,
                'status': 'playing',
              },
          ],
        };
      case 'audio.start':
        audioDevice = value(params, 'deviceId');
        return {'status': 'playing', 'sourceId': 'source-$audioDevice'};
      case 'audio.stop':
        audioDevice = null;
        return {};
      case 'settings.update':
        return params;
      case 'session.start':
        final id = value(params, 'deviceId');
        return sessions['session-$id'] = {
          'sessionId': 'session-$id',
          'deviceId': id,
          'textureId': 1,
          'width': 200,
          'height': 400,
          'status': 'streaming',
          'firstFrameDecoded': true,
          'evidence': 'mdk.snapshot',
        };
      case 'session.resume':
        return sessions[value(params, 'sessionId')]!;
      default:
        return {};
    }
  }
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Backend backend, {
  String location = '/devices/a',
}) async {
  final router = createAppRouter(initialLocation: location);
  await tester.pumpWidget(
    TestProviderScope(
      controller: backend.controller,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ConnectTokens.theme(Brightness.light),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _dispose(
  WidgetTester tester,
  GoRouter router,
  _Backend backend,
) async {
  await tester.pumpWidget(const SizedBox());
  router.dispose();
  backend.controller.dispose();
  await backend.events.close();
}

void main() {
  testWidgets(
    'returning from device B restores the retained workspace A focus',
    (tester) async {
      final backend = _Backend();
      final router = await _mount(tester, backend);
      try {
        final workspaceA = tester.element(find.byType(DeviceWorkspacePage));
        expect(backend.controller.snapshot().focusedDeviceId, 'a');
        unawaited(const WorkspaceRoute(deviceId: 'b').push<void>(workspaceA));
        await tester.pumpAndSettle();
        expect(backend.controller.snapshot().focusedDeviceId, 'b');

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(
          tester.element(find.byType(DeviceWorkspacePage)),
          same(workspaceA),
        );
        expect(backend.controller.snapshot().focusedDeviceId, 'a');
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, router, backend);
      }
    },
  );

  for (final mode in ['follow', 'fixed']) {
    testWidgets(
      'files and gallery restore focus while $mode clipboard and audio keep their intended device',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        var local = 'local baseline';
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.getData') return {'text': local};
          if (call.method == 'Clipboard.setData') {
            local = (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        });
        final backend = _Backend()..audioDevice = 'c';
        backend.controller.settings = {
          'audioMode': mode,
          'audioDevices': ['c'],
          'clipboardSync': true,
          'clipboardMode': mode,
          'clipboardDevice': 'c',
        };
        final router = await _mount(
          tester,
          backend,
          location: '/devices/a/files',
        );
        try {
          testContainer(backend.controller).read(clipboardCoordinatorProvider);
          await tester.pumpAndSettle();
          expect(backend.audioDevice, mode == 'follow' ? 'a' : 'c');
          final filesA = tester.element(find.byType(FilesPage));
          unawaited(const GalleryRoute(deviceId: 'b').push<void>(filesA));
          await tester.pumpAndSettle();
          expect(backend.controller.snapshot().focusedDeviceId, 'b');
          expect(backend.audioDevice, mode == 'follow' ? 'b' : 'c');
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(FilesPage)), same(filesA));
          expect(backend.controller.snapshot().focusedDeviceId, 'a');
          final target = mode == 'follow' ? 'a' : 'c';
          expect(backend.audioDevice, target);
          expect(
            backend.calls.where((call) => call.$1 == 'clipboard.get').last.$2,
            {'deviceId': target},
          );
          backend.events.add({
            'type': 'clipboard.changed',
            'deviceId': 'b',
            'data': {'text': 'hidden B content'},
          });
          await tester.pumpAndSettle();
          expect(local, 'local baseline');
          backend.events.add({
            'type': 'clipboard.changed',
            'deviceId': target,
            'data': {'text': 'intended device content'},
          });
          await tester.pumpAndSettle();
          expect(local, 'intended device content');
          if (mode == 'fixed') {
            expect(
              backend.calls.where((call) => call.$1.startsWith('audio.')),
              isEmpty,
            );
            expect(backend.controller.settings['audioDevices'], ['c']);
            expect(backend.controller.settings['clipboardDevice'], 'c');
          }
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, router, backend);
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        }
      },
    );
  }

  testWidgets('a late device lookup cannot override its replacement route', (
    tester,
  ) async {
    final backend = _Backend();
    final oldLookup = Completer<Json>();
    backend.lookups['b'] = oldLookup.future;
    final router = await _mount(tester, backend);
    try {
      final workspaceA = tester.element(find.byType(DeviceWorkspacePage));
      unawaited(const FilesRoute(deviceId: 'b').push<void>(workspaceA));
      await tester.pump();
      const GalleryRoute(deviceId: 'c').replace(workspaceA);
      await tester.pumpAndSettle();
      expect(find.byType(GalleryPage), findsOneWidget);
      expect(backend.controller.snapshot().focusedDeviceId, 'c');
      oldLookup.complete(_devices[1]);
      await tester.pumpAndSettle();
      expect(backend.controller.snapshot().focusedDeviceId, 'c');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(backend.controller.snapshot().focusedDeviceId, 'a');
      expect(tester.takeException(), isNull);
    } finally {
      if (!oldLookup.isCompleted) oldLookup.complete(_devices[1]);
      await _dispose(tester, router, backend);
    }
  });

  testWidgets(
    'same-frame reconciliation rearms visible audio and waits through background recovery',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final backend = _Backend()..audioDevice = 'c';
      backend.controller.settings = {
        'audioMode': 'follow',
        'audioDevices': ['c'],
      };
      final router = await _mount(
        tester,
        backend,
        location: '/devices/a/files',
      );
      void reconcile(int sequence) {
        backend.events.add({
          'type': 'state.resync',
          'data': <String, dynamic>{},
        });
        backend.events.add({
          'type': 'state.resynced',
          'data': {
            'devices': _devices,
            'settings': backend.controller.settings,
            'sessions': <Json>[],
            'shares': <Json>[],
            'sequence': sequence,
          },
        });
      }

      int audioChecks() =>
          backend.calls.where((call) => call.$1 == 'audio.sources').length;
      try {
        final initialChecks = audioChecks();
        reconcile(1);
        await tester.pumpAndSettle();
        expect(audioChecks(), initialChecks + 1);
        expect(backend.audioDevice, 'a');
        unawaited(
          const GalleryRoute(deviceId: 'b')
              .push<void>(tester.element(find.byType(FilesPage))),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        final beforeBackground = audioChecks();
        reconcile(2);
        await tester.pumpAndSettle();
        expect(audioChecks(), beforeBackground);
        expect(backend.controller.snapshot().focusedDeviceId, 'b');
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(audioChecks(), beforeBackground + 1);
        expect(backend.controller.snapshot().focusedDeviceId, 'b');
        expect(backend.audioDevice, 'b');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(backend.controller.snapshot().focusedDeviceId, 'a');
        expect(backend.audioDevice, 'a');
        expect(tester.takeException(), isNull);
      } finally {
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (tester.binding.lifecycleState == AppLifecycleState.inactive) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await _dispose(tester, router, backend);
      }
    },
  );

  testWidgets('a root remote surface owns focus until files A become visible', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final backend = _Backend();
    final router = await _mount(tester, backend, location: '/devices/a/files');
    try {
      final filesA = tester.element(find.byType(FilesPage));
      unawaited(openRemoteRoute(filesA, deviceId: 'b'));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePage), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(backend.controller.snapshot().focusedDeviceId, 'b');
      await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(FilesPage)), same(filesA));
      expect(backend.controller.snapshot().focusedDeviceId, 'a');
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, router, backend);
    }
  });
}
