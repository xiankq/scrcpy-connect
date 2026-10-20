import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/remote_launch_intent.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/connection_validation.dart';

import 'ios_pages_capture_test.dart' as fixtures;
import 'support/test_controller.dart';

enum _Scene {
  authorization('HevUb'),
  port('E0CAl'),
  pairingFailure('gOwYI'),
  paired('pFGBZ'),
  connecting('xq5If'),
  recovery('zLQT5'),
  reauthorize('zyRl5');

  const _Scene(this.sourceState);
  final String sourceState;
  bool get pairing => this == pairingFailure || this == paired;
}

/// Supplies bridge responses only. Every screenshot uses the existing typed
/// router and production page; no error panels or controls are rebuilt here.
class _Backend {
  _Backend(this.scene);
  final _Scene scene;
  final calls = <(String, Json)>[];
  final events = StreamController<Json>.broadcast(sync: true);
  final connection = Completer<Json>();
  late final controller = createTestController(request, events: events.stream)
    ..loading = false
    ..devices = [device]
    ..settings = {'appearance': 'light'};

  Json get device => {
    ...fixtures.device,
    'transport': 'tls',
    'status': scene == _Scene.reauthorize
        ? 'unauthorized'
        : scene == _Scene.recovery
        ? 'connected'
        : 'offline',
  };

  // An unverified retained record deliberately has no texture or decoded-frame
  // evidence. It cannot manufacture a live remote picture in a widget test.
  Json get session => {
    'id': 'screen',
    'sessionId': 'screen',
    'deviceId': 'fixture',
    'status': 'paused',
    'width': 1080,
    'height': 2400,
  };

  Future<Json> request(String command, [Json params = const {}]) async {
    calls.add((command, Map<String, dynamic>.from(params)));
    if (command == 'devices.connect') {
      if (scene == _Scene.authorization) {
        throw const RequestFailure(
          'device_error',
          'ADB I/O: received fatal alert: CertificateUnknown',
        );
      }
      if (scene == _Scene.connecting) return connection.future;
    }
    if (command == 'devices.pair' && scene == _Scene.pairingFailure) {
      throw const RequestFailure(
        'device_error',
        'pairing authentication failed (incorrect code or channel)',
      );
    }
    return switch (command) {
      'devices.list' => {
        'devices': [device],
      },
      'device.info' => device,
      'settings.get' => {'appearance': 'light'},
      'devices.add' => {'deviceId': 'fixture', 'device': device},
      'devices.pair' => {'deviceId': 'fixture', 'connected': false},
      'session.list' => {
        'sessions': [session],
      },
      'session.start' || 'session.resume' || 'session.get' => session,
      _ => <String, dynamic>{},
    };
  }
}

Future<void> _frames(WidgetTester tester, [int count = 6]) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _expose(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
}

void main() {
  final output = Platform.environment['CONNECT_CONNECTION_CAPTURE_DIR'];
  if (output == null) return;

  testWidgets('capture actual connection and recovery branches', (
    tester,
  ) async {
    for (final font in [
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final cjk = File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc');
    if (cjk.existsSync()) {
      for (final family in ['Roboto', 'ConnectCaptureCJK', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(cjk.readAsBytesSync())),
            ))
            .load();
      }
    }
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });

    final directory = Directory(output);
    final capturedAt = DateTime.now().toUtc().toIso8601String();
    final captures = <String, Object?>{};
    await tester.runAsync(() => directory.create(recursive: true));

    for (final scene in _Scene.values) {
      final backend = _Backend(scene);
      final boundary = GlobalKey();
      final location = scene == _Scene.reauthorize
          ? const AddDeviceRoute(deviceId: 'fixture').location
          : scene == _Scene.recovery
          ? const DevicesRoute().location
          : ConnectionFormRoute(
              deviceId: 'fixture',
              address: '192.168.1.8',
              port: scene == _Scene.port
                  ? '70000'
                  : scene.pairing
                  ? '37151'
                  : '37123',
              pairing: scene.pairing,
            ).location;
      final router = createAppRouter(initialLocation: location);
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: TestProviderScope(
              controller: backend.controller,
              child: MaterialApp.router(
                theme: fixtures.captureTheme(Brightness.light),
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                builder: (context, child) => GlassMaterial.wrap(child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (scene == _Scene.recovery) {
          router.go(
            const RemoteRoute(deviceId: 'fixture').location,
            extra: const RemoteLaunchIntent(),
          );
          await tester.pumpAndSettle();
          backend.events.add({
            'type': 'session.disconnected',
            'deviceId': 'fixture',
            'data': {
              'sessionId': 'screen',
              'reason': '连接已中断，当前画面已暂停。恢复首帧后才能继续操作。',
            },
          });
          await tester.pumpAndSettle();
          expect(find.textContaining('连接已中断，当前画面已暂停'), findsOneWidget);
          expect(find.text('重新检查'), findsOneWidget);
          expect(find.byType(Texture), findsNothing);
        } else if (scene == _Scene.reauthorize) {
          expect(find.text('重新授权'), findsOneWidget);
          expect(find.textContaining('旧记录不代表当前授权'), findsOneWidget);
          for (final label in ['无线调试连接', 'USB 数据线', 'IP 地址连接']) {
            expect(find.text(label), findsOneWidget);
          }
        } else {
          if (scene.pairing) {
            await tester.enterText(find.byType(TextFormField).at(2), '123456');
          }
          FocusManager.instance.primaryFocus?.unfocus();
          final submit = find.text(scene.pairing ? '配对并连接' : '连接设备');
          await _expose(tester, submit);
          await tester.tap(submit);
          if (scene == _Scene.connecting) {
            await _frames(tester);
            expect(find.text('取消本次尝试'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(
              tester
                  .widget<TextFormField>(find.byType(TextFormField).first)
                  .enabled,
              isFalse,
            );
          } else {
            await tester.pumpAndSettle();
            switch (scene) {
              case _Scene.authorization:
                expect(find.text('手机未授权本机，请重新配对。'), findsOneWidget);
                await _expose(tester, find.text('重新配对'));
              case _Scene.port:
                expect(find.text(validatePort('70000')!), findsOneWidget);
                expect(
                  backend.calls.where((c) => c.$1 == 'devices.add'),
                  isEmpty,
                );
              case _Scene.pairingFailure:
                expect(find.textContaining('配对验证未通过'), findsOneWidget);
                expect(
                  tester
                      .widget<TextFormField>(find.byType(TextFormField).at(2))
                      .controller!
                      .text,
                  isEmpty,
                );
              case _Scene.paired:
                expect(find.text('已配对，尚未连接'), findsOneWidget);
                await _expose(tester, find.text('填写连接端口'));
              default:
                break;
            }
          }
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await _frames(tester, 2);
        expect(tester.takeException(), isNull, reason: scene.sourceState);

        final screenshot = '${scene.sourceState}-light.png';
        final layout = fixtures.captureLayout(boundary);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          final entry = {
            'screenshot': screenshot,
            'screenshotSha256': sha256.convert(bytes).toString(),
            'sourceState': scene.sourceState,
            'scene': scene.name,
            'brightness': 'light',
            'captureScope': 'production-router-with-fixture-bridge',
            'route': router.routeInformationProvider.value.uri.toString(),
            'materialBackend': 'widget-test-fallback',
            'nativeRemoteTextureSupplied': false,
            'requests': [
              for (final call in backend.calls)
                {'command': call.$1, 'params': call.$2},
            ],
            ...layout,
          };
          captures[screenshot] = entry;
          await File('${directory.path}/$screenshot').writeAsBytes(bytes);
          await File('${directory.path}/${scene.sourceState}-layout.json')
              .writeAsString(
                '${const JsonEncoder.withIndent('  ').convert(entry)}\n',
              );
          image.dispose();
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (!backend.connection.isCompleted) backend.connection.complete({});
        await tester.pumpAndSettle();
        router.dispose();
        backend.controller.dispose();
        await backend.events.close();
      }
    }
    await tester.runAsync(() async {
      await File('${directory.path}/layout-contract.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'capturedAtUtc': capturedAt,
          'referenceViewport': [402, 874],
          'safeArea': {'top': 54, 'bottom': 34},
          'font': 'ConnectCaptureCJK; production sizes and weights',
          'materialBackend': 'widget-test-fallback',
          'visualAcceptanceComplete': false,
          'captures': captures,
        })}\n',
      );
    });
  });
}
