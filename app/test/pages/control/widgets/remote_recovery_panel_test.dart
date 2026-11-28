import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_recovery_panel.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('画面中断时显示已暂停、原因和检查连接，点按后重试', (tester) async {
    final presentation = RemotePresentation()
      ..deferStart()
      ..failInput('这台设备当前没有可用连接。', 'connection_lost');
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: RemoteRecoveryPanel(
            presentation: presentation,
            independent: false,
            onManageActivities: () {},
            onContinueOnPhoneScreen: () {},
            onCloseUnknownAppLaunch: () {},
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('这台设备当前没有可用连接。'), findsOneWidget);
    await tester.tap(find.text('检查连接'));
    expect(retries, 1);
  });
}
