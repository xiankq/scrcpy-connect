import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/search/devices_workspace_files_search_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'file type selection retains the chosen scope and search filter',
    (tester) async {
      final searches = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'files.search.start') {
          searches.add(Map.of(params));
          return {
            ...params,
            'searchId': 'selection-search',
            'status': 'completed',
            'complete': true,
            'entries': <Json>[],
          };
        }
        return {};
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FileSearchPage(
            controller: controller,
            device: const {'id': 'phone', 'name': '手机'},
            initialPath: '/sdcard/Download',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.widgetWithText(FilledButton, '搜索');
      expect(tester.widget<FilledButton>(search).onPressed, isNull);

      await tester.tap(find.byType(ConnectSelectionField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('图片').last);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(searches.single, {
        'deviceId': 'phone',
        'path': '/sdcard/Download',
        'query': '',
        'filter': 'images',
      });

      await tester.tap(find.text('整个共享存储'));
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(searches.last['path'], '/sdcard');
      expect(searches.last['filter'], 'images');

      await tester.tap(find.byType(ConnectSelectionField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部').last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(search).onPressed, isNull);
      expect(searches, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
