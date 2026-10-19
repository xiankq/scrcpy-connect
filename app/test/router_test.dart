import 'support/test_controller.dart';

import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/pages/devices/devices_page.dart';
import 'package:scrcpy_connect/pages/connection_form/connection_form_page.dart';
import 'package:scrcpy_connect/pages/device_details/device_details_page.dart';
import 'package:scrcpy_connect/pages/device_workspace/device_workspace_page.dart';
import 'package:scrcpy_connect/pages/files/files_page.dart';
import 'package:scrcpy_connect/pages/incoming_share/incoming_share_page.dart';
import 'package:scrcpy_connect/pages/remote/remote_page.dart';
import 'package:scrcpy_connect/pages/route_error/route_error_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const phone = <String, dynamic>{
  'id': 'phone',
  'name': '路由测试手机',
  'status': 'connected',
};

class _Backend {
  final calls = <(String, Json)>[];
  final events = StreamController<Json>.broadcast();
  final shares = <Json>[];
  final sessions = <Json>[];
  bool deleted = false;
  int starts = 0;
  late final controller = createTestController(request, events: events.stream)
    ..loading = false
    ..devices = [phone];
  Future<Json> request(String command, [Json params = const {}]) async {
    calls.add((command, params));
    switch (command) {
      case 'devices.list':
        return {
          'devices': deleted ? <Json>[] : [phone],
        };
      case 'device.info':
        if (deleted || params['deviceId'] != 'phone') {
          throw const RequestFailure('not_found', '设备已移除，请重新选择。');
        }
        return phone;
      case 'devices.add':
        return {'device': phone};
      case 'files.list':
        return {
          'entries': params['path'] == '/sdcard'
              ? [
                  {
                    'name': 'Download',
                    'path': '/sdcard/Download',
                    'isDirectory': true,
                    'canOpen': true,
                    'canManage': true,
                  },
                ]
              : <Json>[],
        };
      case 'sharing.pending':
        return {'shares': shares};
      case 'sharing.consume':
        shares.removeWhere((share) => share['shareId'] == params['shareId']);
        return {};
      case 'clipboard.set':
        return {'applied': true};
      case 'session.start':
        final session = <String, dynamic>{
          'sessionId': 'session-${++starts}',
          'deviceId': 'phone',
          'textureId': starts,
          'width': 200,
          'height': 400,
          'status': 'streaming',
        };
        sessions.add(session);
        return session;
      case 'session.list':
        return {'sessions': sessions};
      case 'session.pause':
      case 'session.resume':
        final session = sessions.singleWhere(
          (item) => item['sessionId'] == params['sessionId'],
        );
        session['status'] = command == 'session.pause' ? 'paused' : 'streaming';
        session['capturePaused'] = command == 'session.pause';
        return {
          ...session,
          'firstFrameDecoded': true,
          'evidence': 'mdk.snapshot',
        };
      case 'session.stop':
        sessions.removeWhere(
          (session) => session['sessionId'] == params['sessionId'],
        );
        return {};
      case 'transfers.list':
        return {'transfers': <Json>[], 'batches': <Json>[]};
      case 'transfers.get':
        throw const RequestFailure('not_found', '传输任务已移除。');
      case 'settings.update':
        return params;
      default:
        return {};
    }
  }
}

Future<GoRouter> _mountRouter(
  WidgetTester tester,
  _Backend backend, {
  String location = '/devices',
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

Future<void> _disposeRouter(
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
    'changing an existing-session route resolves the new session identity without replaying a launch',
    (tester) async {
      final backend = _Backend();
      backend.sessions.addAll([
        {
          'sessionId': 'first',
          'deviceId': 'phone',
          'status': 'streaming',
          'textureId': 9,
          'width': 200,
          'height': 400,
        },
        {
          'sessionId': 'second',
          'deviceId': 'phone',
          'status': 'streaming',
          'textureId': 10,
          'width': 200,
          'height': 400,
        },
      ]);
      final router = await _mountRouter(
        tester,
        backend,
        location: '/devices/phone/sessions/first',
      );
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 9);
      router.goNamed(
        'remote-session',
        pathParameters: {'deviceId': 'phone', 'sessionId': 'second'},
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 10);
      expect(backend.starts, 0);
      expect(
        backend.calls
            .where((call) => call.$1 == 'session.pause')
            .single
            .$2['sessionId'],
        'first',
      );
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'restoring the app restores the selected shell branch without starting any device stream',
    (tester) async {
      final backend = _Backend();
      await tester.pumpWidget(
        TestProviderScope(
          controller: backend.controller,
          child: const ConnectApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      await tester.restartAndRestore();
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      expect(backend.starts, 0);
      await tester.pumpWidget(const SizedBox());
      backend.controller.dispose();
      await backend.events.close();
    },
  );
  testWidgets(
    'an explicit existing-session entry with a missing identity never falls back to a new screen',
    (tester) async {
      final backend = _Backend();
      final router = await _mountRouter(tester, backend);
      // Use a context inside the router rather than the outer MaterialApp.
      unawaited(
        openRemoteRoute(
          tester.element(find.byType(DevicesPage)),
          deviceId: 'phone',
          sessionId: '',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RouteErrorPage), findsOneWidget);
      expect(backend.starts, 0);
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'device tab is the initial route and branch state and back history survive tab switches',
    (tester) async {
      final backend = _Backend();
      final router = await _mountRouter(tester, backend);
      expect(router.routeInformationProvider.value.uri.path, '/devices');
      expect(find.text('路由测试手机'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '保留搜索');
      await tester.tap(find.text('传输').last);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/transfers');
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/transfers');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/devices');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '保留搜索',
      );
      expect(
        backend.calls.where((call) => call.$1 == 'session.start'),
        isEmpty,
      );
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'device detail and files reload identifiers then back returns to the same detail route',
    (tester) async {
      final backend = _Backend();
      final router = await _mountRouter(tester, backend);
      unawaited(
        router.pushNamed(
          'device-details',
          pathParameters: {'deviceId': 'phone'},
        ),
      );
      await tester.pumpAndSettle();
      final detail = tester.element(find.byType(DeviceDetailsPage));
      unawaited(
        router.pushNamed(
          'files',
          pathParameters: {'deviceId': 'phone'},
          queryParameters: {'path': '/sdcard'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilesPage), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(
        backend.calls.where((call) => call.$1 == 'device.info'),
        hasLength(3),
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(DeviceDetailsPage)), same(detail));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/devices/phone/details',
      );
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'missing records and restored remote URLs show a useful recovery without creating a session',
    (tester) async {
      for (final location in [
        '/devices/deleted/details',
        '/transfers/deleted',
        '/devices/phone/sessions/deleted',
        '/devices/phone/file?path=/gone',
        '/devices/phone/remote',
        '/devices/phone/apps/com.example.test/remote',
        '/unrecognized',
      ]) {
        final backend = _Backend();
        final router = await _mountRouter(tester, backend, location: location);
        expect(find.byType(RouteErrorPage), findsOneWidget, reason: location);
        expect(find.text('返回设备列表'), findsOneWidget);
        expect(backend.starts, 0, reason: location);
        await tester.tap(find.text('返回设备列表'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/devices');
        expect(tester.takeException(), isNull);
        await _disposeRouter(tester, router, backend);
      }
    },
  );

  testWidgets(
    'full-screen remote keeps its session across rebuilds and return pauses only its own identity',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final backend = _Backend();
      backend.sessions.add({
        'sessionId': 'other-session',
        'deviceId': 'phone',
        'packageName': 'com.example.other',
        'status': 'streaming',
      });
      final router = await _mountRouter(
        tester,
        backend,
        location: '/devices/phone',
      );
      unawaited(
        router.pushNamed(
          'remote',
          pathParameters: {'deviceId': 'phone'},
          extra: const RemoteLaunchIntent(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      final remote = tester.element(find.byType(RemotePage));
      backend.events.add({
        'type': 'settings.changed',
        'data': {'appearance': 'dark'},
      });
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        TestProviderScope(
          controller: backend.controller,
          child: MaterialApp.router(
            routerConfig: router,
            theme: ConnectTokens.theme(Brightness.dark),
          ),
        ),
      );
      await tester.pumpAndSettle();
      router.refresh();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(RemotePage)), same(remote));
      expect(backend.starts, 1);
      await tester.tap(find.bySemanticsLabel(RegExp('退出控制，返回')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceWorkspacePage), findsOneWidget);
      expect(
        backend.calls
            .where((call) => call.$1 == 'session.pause')
            .map((call) => call.$2['sessionId']),
        ['session-1'],
      );
      expect(backend.sessions.map((item) => item['sessionId']).toSet(), {
        'other-session',
        'session-1',
      });
      expect(backend.calls.where((call) => call.$1 == 'session.stop'), isEmpty);
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'an existing remote route reattaches once while declarative removal pauses and retains it',
    (tester) async {
      final backend = _Backend();
      backend.sessions.add({
        'sessionId': 'existing',
        'deviceId': 'phone',
        'status': 'streaming',
        'textureId': 9,
        'width': 200,
        'height': 400,
      });
      final router = await _mountRouter(
        tester,
        backend,
        location: '/devices/phone/sessions/existing',
      );
      expect(find.byType(Texture), findsOneWidget);
      expect(backend.starts, 0);
      router.goNamed('devices');
      await tester.pumpAndSettle();
      expect(
        backend.calls
            .where((call) => call.$1 == 'session.pause')
            .single
            .$2['sessionId'],
        'existing',
      );
      expect(backend.starts, 0);
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'directory route returns a typed selection and cancel returns null without consuming a share',
    (tester) async {
      final backend = _Backend();
      final router = await _mountRouter(tester, backend);
      final selected = router.pushNamed<String>(
        'share-directory',
        pathParameters: {'deviceId': 'phone'},
        queryParameters: {'path': '/sdcard'},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用这个目录'));
      await tester.pumpAndSettle();
      expect(await selected, '/sdcard/Download');
      final cancelled = router.pushNamed<String>(
        'share-directory',
        pathParameters: {'deviceId': 'phone'},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(await cancelled, isNull);
      expect(
        backend.calls.where((call) => call.$1 == 'sharing.consume'),
        isEmpty,
      );
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'sharing return acknowledges the specific share and leaves the source route',
    (tester) async {
      final backend = _Backend();
      backend.shares.add({'shareId': 'incoming', 'text': 'draft'});
      final router = await _mountRouter(tester, backend);
      unawaited(
        router.pushNamed(
          'incoming-share',
          pathParameters: {'shareId': 'incoming'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(IncomingSharePage), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/devices');
      expect(
        backend.calls.where((call) => call.$1 == 'sharing.consume').single.$2,
        {'shareId': 'incoming'},
      );
      expect(backend.calls.where((call) => call.$1 == 'files.push'), isEmpty);
      await _disposeRouter(tester, router, backend);
    },
  );

  testWidgets(
    'successful connection replaces its form with the connected workspace',
    (tester) async {
      final backend = _Backend();
      final router = await _mountRouter(tester, backend);
      unawaited(router.pushNamed('connection-form'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'phone.local');
      await tester.enterText(find.byType(TextFormField).at(1), '37123');
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      expect(
        find.byType(ConnectionFormPage, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(DeviceWorkspacePage), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/devices');
      expect(
        find.byType(ConnectionFormPage, skipOffstage: false),
        findsNothing,
      );
      await _disposeRouter(tester, router, backend);
    },
  );
}
