import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/remote_input.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  test('source input preserves aspect ratio and excludes letterbox space', () {
    const viewport = Size(400, 800);
    const landscape = Size(1920, 1080);
    expect(
      sourcePoint(const Offset(200, 400), viewport, landscape),
      const Offset(960, 540),
    );
    expect(sourcePoint(const Offset(200, 20), viewport, landscape), isNull);
    expect(sourcePoint(const Offset(200, 799), viewport, landscape), isNull);
    expect(
      sourcePoint(const Offset(200, 20), viewport, landscape, clamp: true),
      const Offset(960, 0),
    );
    expect(
      sourcePoint(const Offset(399, 400), viewport, landscape)!.dx,
      closeTo(1915.2, .01),
    );
    expect(sourcePoint(Offset.zero, viewport, Size.zero), isNull);
  });

  testWidgets(
    'physical modifiers, repeat and mouse input retain capture identity',
    (tester) async {
      final commands = <(String, Json)>[];
      final controller = _controller(commands, captureGeneration: 7);
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
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        final center = tester.getCenter(find.byType(Texture));
        await tester.sendEventToBinding(
          PointerHoverEvent(position: center, kind: PointerDeviceKind.mouse),
        );
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: const Offset(0, 20),
            kind: PointerDeviceKind.mouse,
          ),
        );
        final mouse = await tester.startGesture(
          center,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.up();
        await tester.pumpAndSettle();
        final keys = commands
            .where((c) => c.$1 == 'session.key' && c.$2['keyCode'] == 29)
            .map((c) => c.$2)
            .toList();
        expect(keys.map((p) => p['action']), ['down', 'down', 'up']);
        expect(keys.map((p) => p['metaState']), everyElement(0x1000));
        expect(keys[1]['repeat'], 1);
        final touches = commands
            .where((c) => c.$1 == 'session.touch')
            .map((c) => c.$2)
            .toList();
        expect(touches.map((p) => p['action']), ['hover', 'down', 'up']);
        expect(touches.map((p) => p['mouse']), everyElement(isTrue));
        expect(touches[1]['actionButton'], kSecondaryMouseButton);
        expect(touches.last['pressure'], 0);
        expect(
          commands.where((c) => c.$1 == 'session.scroll').single.$2['vscroll'],
          -1,
        );
        expect(
          commands
              .where(
                (c) => [
                  'session.touch',
                  'session.scroll',
                  'session.key',
                ].contains(c.$1),
              )
              .map((c) => c.$2['captureGeneration']),
          everyElement(7),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

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

  for (final (showNavigationBar, brightness) in [
    (true, Brightness.light),
    (true, Brightness.dark),
    (false, Brightness.light),
  ]) {
    testWidgets(
      'system back controls Android and only close exits with navigation $showNavigationBar in ${brightness.name} theme',
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
              theme: ConnectTokens.theme(brightness),
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
              final context = tester.element(finder);
              final colors = Theme.of(context).colorScheme;
              final icon = tester.widget<Icon>(
                find.descendant(of: finder, matching: find.byType(Icon)),
              );
              final bar = tester.widget<ColoredBox>(
                find
                    .ancestor(of: finder, matching: find.byType(ColoredBox))
                    .first,
              );
              expect(icon.color, colors.onSurface);
              expect(bar.color, colors.surface);
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

  testWidgets('missing live texture reports failure and blocks remote input', (
    tester,
  ) async {
    final calls = <String>[];
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      calls.add(command);
      return {'sessionId': 'actual-session', 'reason': '设备未提供解码画面'};
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        home: RemotePage(
          controller: controller,
          device: const {'id': 'phone', 'name': '测试手机'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法打开实时画面'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    await tester.tapAt(const Offset(400, 500));
    await tester.pump();
    expect(calls.where((call) => call == 'session.touch'), isEmpty);
  });

  testWidgets(
    'multitouch uses source pixels and preserves pointer identities',
    (tester) async {
      final touches = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'session.touch') {
          touches.add(Map<String, dynamic>.from(params));
        }
        return command == 'session.start'
            ? {
                'sessionId': 'session',
                'textureId': 1,
                'width': 200,
                'height': 400,
              }
            : {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: RemotePage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final frame = tester.getRect(find.byType(Texture));
      final one = await tester.startGesture(
        const Offset(400, 300),
        pointer: 101,
      );
      final two = await tester.startGesture(
        const Offset(475, 450),
        pointer: 102,
      );
      await one.moveBy(const Offset(15, 0));
      await one.up();
      await two.cancel();
      await tester.pumpAndSettle();
      expect(touches.first['x'], 100);
      expect(
        touches.first['y'],
        ((300 - frame.top) / frame.height * 400).round(),
      );
      expect(touches.first['screenWidth'], 200);
      expect(touches.first['screenHeight'], 400);
      expect(
        touches.where((p) => p['pointerId'] == 101).map((p) => p['action']),
        ['down', 'move', 'up'],
      );
      expect(
        touches.where((p) => p['pointerId'] == 102).map((p) => p['action']),
        ['down', 'cancel'],
      );
    },
  );
}

AppController _controller(
  List<(String, Json)> commands, {
  int? captureGeneration,
}) => createTestController((command, [params = const {}]) async {
  commands.add((command, params));
  if (command == 'session.start') {
    return {
      'sessionId': 'original',
      'captureGeneration': ?captureGeneration,
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
