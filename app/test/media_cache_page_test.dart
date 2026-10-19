import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'settings reaches cache page and clear reports actual bytes while protecting active content',
    (tester) async {
      var clears = 0;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'media.cache.status') {
          return {
            'budgetBytes': 536870912,
            'usedBytes': clears == 0 ? 3072 : 1024,
            'protectedBytes': 1024,
            'reclaimableBytes': clears == 0 ? 2048 : 0,
            'reservedBytes': 0,
          };
        }
        if (command == 'media.cache.clear') {
          clears++;
          return {'deletedBytes': 2048, 'protectedBytes': 1024};
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          home: SettingsPage(controller: controller),
          theme: ConnectTokens.theme(Brightness.light),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('媒体暂存'), 250);
      await tester.tap(find.text('媒体暂存'));
      await tester.pumpAndSettle();
      expect(find.text('已用 3.0 KB'), findsOneWidget);
      expect(find.text('受保护'), findsOneWidget);
      await tester.ensureVisible(find.text('清理可回收暂存'));
      await tester.tap(find.text('清理可回收暂存'));
      await tester.pumpAndSettle();
      expect(clears, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(clears, 0);
      await tester.tap(find.text('清理可回收暂存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理暂存'));
      await tester.pumpAndSettle();
      expect(clears, 1);
      expect(find.text('已用 1.0 KB'), findsOneWidget);
      await tester.ensureVisible(find.text('已回收 2.0 KB，受保护内容已保留。'));
      expect(find.text('已回收 2.0 KB，受保护内容已保留。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '清理可回收暂存'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
