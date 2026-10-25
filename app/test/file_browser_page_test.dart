import 'package:scrcpy_connect/application/transport/application_request.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/router/app_router.dart';

import 'support/router_test_app.dart';
import 'support/page_back.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('root back exits the file route for header and system back', (
    tester,
  ) async {
    const device = {'id': 'phone', 'name': '我的手机'};
    final controller = createTestController((
      command, [
      params = const {},
    ]) async {
      if (command == 'files.list') {
        return {
          'entries': <Json>[
            if (params['path'] == '/sdcard')
              {
                'name': 'Download',
                'path': '/sdcard/Download',
                'isDirectory': true,
              }
            else
              {
                'name': 'inside.txt',
                'path': '/sdcard/Download/inside.txt',
                'mime': 'text/plain',
              },
          ],
        };
      }
      return {};
    });
    await tester.pumpWidget(
      RouterTestApp(
        controller: controller,
        theme: ConnectTokens.theme(Brightness.light),
        devices: const [device],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => FilesRoute(deviceId: 'phone').push<void>(context),
            child: const Text('打开文件'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(pageBackButton(tester));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
    await tester.tap(pageBackButton(tester));
    await tester.pumpAndSettle();
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);

    await tester.tap(find.text('打开文件'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('打开文件'), findsOneWidget);
    expect(find.byType(FilesPage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
