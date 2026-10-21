import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'remote image uses the complete viewport beneath host top safe area',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final controller = _controller([]);
      controller.settings = {
        'deviceSettings': {
          'phone': {'showNavigationBar': false},
        },
      };
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
        expect(
          tester.getRect(find.byType(Texture)),
          const Rect.fromLTWH(0, 0, 400, 800),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  for (final showNavigationBar in [true, false]) {
    testWidgets(
      'system back controls Android and only close exits with navigation $showNavigationBar',
      (tester) async {
        final commands = <(String, Json)>[];
        final controller = _controller(commands);
        controller.settings = {
          'deviceSettings': {
            'phone': {if (!showNavigationBar) 'showNavigationBar': false},
          },
        };
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              devices: const [
                {'id': 'phone'},
              ],
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openRemoteRoute(context, deviceId: 'phone'),
                  child: const Text('打开画面'),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开画面'));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(RemotePage), findsOneWidget);
          expect(commands.where((c) => c.$1 == 'session.pause'), isEmpty);
          expect(
            commands
                .where((c) => c.$1 == 'session.key')
                .map((c) => (c.$2['keyCode'], c.$2['action'])),
            [(4, 'down'), (4, 'up')],
          );
          for (final button in [('返回', 4), ('主屏幕', 3), ('最近任务', 187)]) {
            final finder = find.byTooltip(button.$1);
            expect(finder, showNavigationBar ? findsOneWidget : findsNothing);
            if (showNavigationBar) {
              await tester.tap(finder);
              await tester.pump();
              expect(commands.where((c) => c.$1 == 'session.key').last.$2, {
                'sessionId': 'original',
                'keyCode': button.$2,
                'action': 'up',
              });
            }
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(commands.where((c) => c.$1 == 'session.key').last.$2, {
            'sessionId': 'original',
            'keyCode': 4,
            'action': 'up',
          });
          await tester.tap(find.bySemanticsLabel(RegExp('展开画面工具，')));
          await tester.pump();
          await tester.ensureVisible(find.text('关闭画面'));
          await tester.tap(find.text('关闭画面'));
          await tester.pumpAndSettle();
          expect(find.byType(RemotePage), findsNothing);
          expect(commands.where((c) => c.$1 == 'session.stop'), hasLength(1));
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'frame edge rounding and outside drags never pause the view or leave a pointer held',
    (tester) async {
      final commands = <(String, Json)>[];
      final controller = _controller(commands);
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
        final frame = tester.getRect(find.byType(Texture));
        await tester.tapAt(Offset(frame.right - 0.01, frame.center.dy));
        await tester.pumpAndSettle();
        expect(find.text('画面已暂停'), findsNothing);
        expect(find.text('触控位置超出画面。'), findsNothing);
        final active = await tester.startGesture(frame.center, pointer: 101);
        await active.moveTo(Offset(frame.left - 10, frame.center.dy));
        await active.moveTo(frame.center);
        await active.up();
        await tester.tapAt(Offset(frame.left - 10, frame.center.dy));
        await tester.pumpAndSettle();
        final touches = commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2)
            .toList();
        expect(touches.map((p) => p['action']), [
          'down',
          'up',
          'down',
          'cancel',
        ]);
        expect(touches.take(2).map((p) => p['x']), [199, 199]);
        expect(touches.last['x'], touches[2]['x']);
        expect(touches.last['y'], touches[2]['y']);
        expect(touches.last['pressure'], 0);
        expect(commands.where((c) => c.$1 == 'session.pause'), isEmpty);
        expect(find.text('画面已暂停'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}

AppController _controller(List<(String, Json)> commands) =>
    createTestController((command, [params = const {}]) async {
      commands.add((command, params));
      if (command == 'session.start') {
        return {
          'sessionId': 'original',
          'deviceId': 'phone',
          'textureId': 1,
          'width': 200,
          'height': 400,
        };
      }
      if (command == 'session.touch' &&
          ((params['x'] as int) >= 200 || (params['y'] as int) >= 400)) {
        throw const RequestFailure('invalid_argument', '触控位置超出画面。');
      }
      return {};
    });
