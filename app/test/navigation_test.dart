import 'package:scrcpy_connect/application/transport/json_readers.dart';
import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'support/page_back.dart';

import 'package:scrcpy_connect/router/app_router.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/flows.dart';

void main() {
  testWidgets(
    'file return scopes its back action during route animation and restores the lazy hero',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = createTestController(
        (command, [params = const {}]) async =>
            command == 'files.list' ? {'entries': <Json>[]} : {},
      );
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          devices: const [device],
          theme: ConnectTokens.theme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    WorkspaceRoute(deviceId: value(device, 'id'))
                        .push<void>(context),
                child: const Text('进入工作台'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入工作台'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.scrollUntilVisible(
          find.text('文件管理'),
          250,
          scrollable: find
              .descendant(
                of: find.byType(DeviceWorkspacePage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('文件管理')),
          alignment: .5,
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('文件管理'));
        // 有意让两条路由都处在转场中，真实列表可能先于进入动画完成。
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pump();
        expect(find.byType(FilesPage), findsOneWidget);
        expect(pageBackButton(tester), findsNWidgets(2));
        expect(
          ModalRoute.of(tester.element(find.byType(FilesPage)))
              ?.animation
              ?.status,
          isNot(AnimationStatus.completed),
        );
        await returnFromFiles(tester);
        expect(find.text('打开手机屏幕'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
