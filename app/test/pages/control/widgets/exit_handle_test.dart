import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/exit_handle.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: ConnectTokens.theme(Brightness.light),
      home: Scaffold(
        body: ExitHandle(deviceLabel: '测试设备', onExit: () {}),
      ),
    ),
  );
  final handle = find.byKey(const ValueKey('remote-tool-handle'));
  final panel = find.byKey(const ValueKey('remote-tool-panel'));

  testWidgets('拖动把手只停靠到左右边缘，不展开工具面板', (tester) async {
    await show(tester);
    await tester.drag(handle, const Offset(-90, 36));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.getRect(handle).right, 800);

    await tester.drag(handle, const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.getRect(handle).left, 0);
  });

  testWidgets('点按把手展开工具面板，收起途中再点把手重新展开', (tester) async {
    await show(tester);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(handle, findsNothing);
    for (final action in ['设备声音', '熄屏', '键盘']) {
      expect(find.text(action), findsOneWidget);
    }

    await tester.tap(find.byTooltip('收起画面工具'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(handle, findsOneWidget);
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);

    await tester.tap(find.byTooltip('收起画面工具'));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(handle, findsOneWidget);
  });
}
