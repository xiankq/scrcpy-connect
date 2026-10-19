import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/notifications/notifications_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets(
    'empty group summaries do not obscure current actionable content',
    (tester) async {
      const device = {'id': 'phone', 'name': '手机', 'status': 'connected'};
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'notifications.list') {
          return {
            'status': 'available',
            'notifications': [
              {'id': 'summary', 'appName': '空白汇总', 'groupSummary': true},
              {
                'id': 'message',
                'appName': '消息应用',
                'title': '当前消息',
                'body': '仍然显示原内容',
                'canReply': true,
              },
              {
                'id': 'useful-summary',
                'appName': '有内容的汇总',
                'groupSummary': true,
                'body': '三条未读消息',
              },
              {'id': 'private', 'appName': '隐藏正文的应用'},
            ],
          };
        }
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: NotificationsPage(controller: controller, device: device),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('空白汇总'), findsNothing);
      expect(find.text('当前消息'), findsOneWidget);
      expect(find.text('仍然显示原内容'), findsOneWidget);
      expect(find.text('快捷回复'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('三条未读消息'), 200);
      expect(find.text('三条未读消息'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('此通知未提供预览内容'), 200);
      expect(find.text('隐藏正文的应用'), findsOneWidget);
      expect(find.text('此通知未提供预览内容'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
