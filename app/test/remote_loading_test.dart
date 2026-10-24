import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final (packageName, semanticsLabel) in [
    (null, '正在打开手机屏幕'),
    ('com.example.editor', '正在打开独立窗口'),
  ]) {
    testWidgets(
      '$semanticsLabel uses the ambient field until its first frame',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final semantics = tester.ensureSemantics();
        final pending = Completer<Json>();
        const screen = {
          'sessionId': 'loading-session',
          'deviceId': 'phone',
          'status': 'ready',
          'textureId': 7,
          'width': 200,
          'height': 400,
          'firstFrameDecoded': true,
          'evidence': 'media_codec.snapshot',
        };
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          return switch (command) {
            'session.list' => {'sessions': <Json>[]},
            'session.start' => pending.future,
            'device.screen.state' => {
              'deviceId': 'phone',
              'screenOn': true,
              'locked': false,
            },
            _ => <String, dynamic>{},
          };
        });
        try {
          await tester.pumpWidget(
            RouterTestApp(
              controller: controller,
              home: RemotePage(
                controller: controller,
                device: const {'id': 'phone', 'name': '我的手机'},
                packageName: packageName,
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(AmbientLoadingField), findsOneWidget);
          expect(find.bySemanticsLabel(semanticsLabel), findsOneWidget);
          expect(find.text(semanticsLabel), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('取消打开'), findsOneWidget);

          pending.complete(screen);
          await tester.pumpAndSettle();
          expect(find.byType(AmbientLoadingField), findsNothing);
          expect(find.byType(Texture), findsOneWidget);
        } finally {
          if (!pending.isCompleted) pending.complete(screen);
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
          controller.dispose();
        }
      },
    );
  }
}
