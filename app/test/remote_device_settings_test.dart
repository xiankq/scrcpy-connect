import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/index/devices_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/app_state.dart';
import 'package:scrcpy_connect/services/remote_display_settings.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'a rejected viewport resize reports failure and preserves its last confirmed size',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final commands = <(String, Json)>[];
      final controller = createTestController(
        (command, [params = const {}]) async {
          commands.add((command, params));
          if (command == 'session.start') {
            return {
              'sessionId': 'screen',
              'textureId': 1,
              'width': params['displayWidth'],
              'height': params['displayHeight'],
              'displayAuto': true,
              'displaySize': {
                'width': params['displayWidth'],
                'height': params['displayHeight'],
              },
            };
          }
          if (command == 'session.display') {
            throw const RequestFailure(
              'display_resize_failed',
              'fixture rejected resize',
            );
          }
          return {};
        },
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {
                'remoteAspectRatio': 'auto',
                'showNavigationBar': false,
              },
            },
          },
        ),
      );
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(RemotePage));
        final Object? confirmed = state.appliedDisplaySize;
        tester.view.physicalSize = const Size(800, 400);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.textContaining('fixture rejected resize'), findsOneWidget);
        expect(commands.where((c) => c.$1 == 'session.display'), hasLength(1));
        expect(state.requestedDisplaySize, isNot(confirmed));
        expect(state.appliedDisplaySize, confirmed);
        expect(state.resizingDisplay, isFalse);
        await tester.pump(const Duration(seconds: 6));
        expect(
          commands.where((c) => c.$1 == 'session.display'),
          hasLength(1),
          reason: 'An unconfirmed mutation is not automatically replayed.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'closing the final application window keeps its task and locks by device preference',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final semantics = tester.ensureSemantics();
      final commands = <(String, Json)>[];
      const app = {
        'sessionId': 'app',
        'id': 'app',
        'deviceId': 'phone',
        'packageName': 'com.example.app',
        'status': 'paused',
        'textureId': 1,
        'width': 400,
        'height': 800,
      };
      final controller = createTestController(
        (command, [params = const {}]) async {
          commands.add((command, params));
          if (command == 'session.list') {
            return {
              'sessions': [app],
            };
          }
          if (command == 'session.resume') {
            return {
              ...app,
              'firstFrameDecoded': true,
              'evidence': 'media_codec.snapshot',
            };
          }
          return {};
        },
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {'lockOnClose': true},
            },
          },
        ),
      );
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: const [
              {'id': 'phone', 'name': '测试手机'},
            ],
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => const RemoteSessionRoute(
                    deviceId: 'phone',
                    sessionId: 'app',
                  ).push<void>(context),
                  child: const Text('恢复应用'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复应用'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<RemotePage>(find.byType(RemotePage)).packageName,
          'com.example.app',
        );
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await tester.pumpAndSettle();
        expect(find.byType(RemotePage), findsNothing);
        expect(
          commands.where(
            (c) => c.$1 == 'session.key' && c.$2['keyCode'] == 223,
          ),
          hasLength(2),
        );
        expect(commands.where((c) => c.$1 == 'session.stop').single.$2, {
          'sessionId': 'app',
          'keepTask': true,
        });
        expect(commands.where((c) => c.$1 == 'session.start'), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'bridge wake failure stays visible through initial device refresh',
    (tester) async {
      final events = StreamController<Json>.broadcast(sync: true);
      final calls = <String>[];
      const devices = [
        {
          'id': 'phone',
          'name': '测试手机',
          'status': 'connected',
          'connectionId': 'one',
        },
      ];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        calls.add(command);
        if (command == 'devices.list') return {'devices': devices};
        return {};
      }, events: events.stream);
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            devices: devices,
            home: DevicesPage(controller: controller),
          ),
        );
        events.add({
          'type': 'device.screen.failed',
          'deviceId': 'phone',
          'data': {'connectionId': 'one', 'reason': 'wake result unknown'},
        });
        await controller.refreshDevices();
        await tester.pumpAndSettle();
        expect(
          find.textContaining('未能自动点亮设备：wake result unknown'),
          findsOneWidget,
        );
        expect(
          calls.where((command) => command == 'devices.wake'),
          isEmpty,
          reason: 'Only the bridge owns connection wake policy',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
      }
    },
  );

  for (final scenario in [(false, false), (true, false), (false, true)]) {
    final fails = scenario.$1;
    final anotherPhonePage = scenario.$2;
    testWidgets(
      'phone exit sends sleep only for last page, failure=$fails another=$anotherPhonePage',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final semantics = tester.ensureSemantics();
        final commands = <(String, Json)>[];
        final controller = createTestController(
          (command, [params = const {}]) async {
            commands.add((command, params));
            if (command == 'session.start') {
              return {
                'sessionId': 'screen',
                'textureId': 1,
                'width': 400,
                'height': 800,
              };
            }
            if (fails && command == 'session.key' && params['keyCode'] == 223) {
              throw const RequestFailure('disconnected', 'lock failed');
            }
            return {};
          },
          initialState: AppState(
            settings: const {
              'deviceSettings': {
                'phone': {'lockOnClose': true},
              },
            },
          ),
        );
        final releaseOtherPage = anotherPhonePage
            ? controller.claimPhoneControlPage('phone')
            : null;
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [
                {'id': 'phone', 'name': '测试手机'},
              ],
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        openRemoteRoute(context, deviceId: 'phone'),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
          await tester.pump();
          await tester.ensureVisible(find.text('关闭画面'));
          await tester.tap(find.text('关闭画面'));
          await tester.pumpAndSettle();
          expect(find.byType(RemotePage), findsNothing);
          final sleep = commands.indexWhere(
            (c) => c.$1 == 'session.key' && c.$2['keyCode'] == 223,
          );
          final pause = commands.indexWhere((c) => c.$1 == 'session.stop');
          if (anotherPhonePage) {
            expect(sleep, -1);
            expect(pause, greaterThanOrEqualTo(0));
          } else {
            expect(sleep, greaterThanOrEqualTo(0));
            expect(pause, greaterThan(sleep));
          }
          if (fails) expect(find.textContaining('锁屏尚未确认'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox());
          releaseOtherPage?.call();
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }

  for (final onScreenKeyboard in [true, false]) {
    testWidgets(
      'pending IME preserves the retained display and permits hardware keyboard resizing: screenKeyboard=$onScreenKeyboard',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        // A newly entered route sees the old status bar until Android finishes
        // switching to immersive mode; the retained window was already sized.
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);
        final commands = <(String, Json)>[];
        const retained = <String, dynamic>{
          'sessionId': 'screen',
          'deviceId': 'phone',
          'status': 'paused',
          'textureId': 1,
          'width': 640,
          'height': 1280,
          'displayAuto': true,
          'displaySize': {'width': 960, 'height': 1920},
        };
        final controller = createTestController(
          (command, [params = const {}]) async {
            commands.add((command, params));
            if (command == 'session.resume') {
              return {
                ...retained,
                'status': 'streaming',
                'firstFrameDecoded': true,
                'evidence': 'media_codec.snapshot',
              };
            }
            return {};
          },
          initialState: AppState(
            settings: const {
              'deviceSettings': {
                'phone': {
                  'remoteAspectRatio': 'auto',
                  'showNavigationBar': false,
                },
              },
            },
          ),
        );
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              home: RemotePage(
                controller: controller,
                device: const {'id': 'phone'},
                existingSession: retained,
                requestKeyboard: true,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1500));
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            commands.where((call) => call.$1 == 'session.display'),
            isEmpty,
            reason: 'A slow IME cannot be mistaken for a hardware keyboard.',
          );
          if (!onScreenKeyboard) {
            tester.view.physicalSize = const Size(800, 400);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final resized = commands
                .singleWhere((call) => call.$1 == 'session.display')
                .$2;
            expect(
              resized['displayWidth'] / resized['displayHeight'],
              closeTo(800 / 400, .005),
              reason:
                  'A real host resize must adapt even without an IME inset.',
            );
            return;
          }
          tester.view.padding = FakeViewPadding.zero;
          tester.view.viewPadding = const FakeViewPadding(bottom: 24);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            commands.where((call) => call.$1 == 'session.resume'),
            hasLength(1),
          );
          expect(
            commands.where((call) => call.$1 == 'session.display'),
            isEmpty,
            reason: 'Neither a queued transition size nor the IME may resize the retained target.',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      },
    );
  }

  testWidgets(
    'auto sizes the remote display from space below navigation and adapts after navigation hides',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final events = StreamController<Json>.broadcast(sync: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      final commands = <(String, Json)>[];
      final controller = createTestController(
        (command, [params = const {}]) async {
          commands.add((command, params));
          if (command == 'session.start') {
            return {
              'sessionId': 'screen',
              'textureId': 1,
              'width': params['displayWidth'],
              'height': params['displayHeight'],
              'displayAuto': true,
              'displaySize': {
                'width': params['displayWidth'],
                'height': params['displayHeight'],
              },
            };
          }
          return {};
        },
        events: events.stream,
        initialState: AppState(
          settings: const {
            'deviceSettings': {
              'phone': {'remoteAspectRatio': 'auto'},
            },
          },
        ),
      );
      try {
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            home: RemotePage(
              controller: controller,
              device: const {'id': 'phone'},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final start = commands.singleWhere((c) => c.$1 == 'session.start').$2;
        // The startup request is measured before the navigation band exists.
        final startup = const RemoteDisplaySettings({
          'remoteAspectRatio': 'auto',
        }).dimensions(const Size(400, 800))!;
        expect(start['displayWidth'], startup.width);
        expect(start['displayHeight'], startup.height);
        expect(find.bySemanticsLabel(RegExp('展开画面工具，')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        final navigation = commands
            .singleWhere((c) => c.$1 == 'session.display')
            .$2;
        final withNavigation = const RemoteDisplaySettings({
          'remoteAspectRatio': 'auto',
        }).dimensions(const Size(400, 724))!;
        expect(navigation['displayWidth'], withNavigation.width);
        expect(navigation['displayHeight'], withNavigation.height);
        controller.settings = const {
          'deviceSettings': {
            'phone': {'remoteAspectRatio': 'auto', 'showNavigationBar': false},
          },
        };
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(commands.where((c) => c.$1 == 'session.display'), hasLength(2));
        final resized = commands
            .where((c) => c.$1 == 'session.display')
            .last
            .$2;
        expect(
          resized['displayWidth'] / resized['displayHeight'],
          closeTo(400 / 800, .002),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          commands.where((c) => c.$1 == 'session.display'),
          hasLength(2),
          reason: 'IME visibility must not redefine the remote display',
        );
        tester.view.resetViewInsets();
        tester.view.physicalSize = const Size(800, 400);
        await tester.pump();
        // A live stream continues producing state updates during rotation.
        // Rebuilding with the same viewport must not postpone its resize.
        for (var frame = 0; frame < 6; frame++) {
          events.add({
            'type': 'session.updated',
            'deviceId': 'phone',
            'data': {'sessionId': 'screen', 'status': 'streaming'},
          });
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          commands.where((c) => c.$1 == 'session.display'),
          hasLength(3),
          reason: 'Live updates cannot starve a stable landscape viewport.',
        );
        await tester.pumpAndSettle();
        final landscape = commands
            .where((c) => c.$1 == 'session.display')
            .last
            .$2;
        expect(
          landscape['displayWidth'] / landscape['displayHeight'],
          closeTo(800 / 400, .005),
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.view.physicalSize = const Size(400, 800);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(commands.where((c) => c.$1 == 'session.display'), hasLength(3));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          commands.where((c) => c.$1 == 'session.display'),
          hasLength(4),
          reason: 'A short inactive transition cannot lose a pending viewport.',
        );
        await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(800, 400);
        await tester.pump();
        await tester.ensureVisible(find.text('关闭画面'));
        await tester.tap(find.text('关闭画面'));
        await tester.pumpAndSettle();
        expect(
          commands.where((c) => c.$1 == 'session.display'),
          hasLength(4),
          reason: 'Closing cancels the pending viewport adjustment.',
        );
        expect(commands.where((c) => c.$1 == 'session.stop'), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await events.close();
        semantics.dispose();
      }
    },
  );
}
