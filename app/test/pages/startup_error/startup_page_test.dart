import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/startup_error/startup_error_page.dart';

void main() {
  testWidgets('startup loading page provides an immediate opaque surface', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: const StartupLoadingPage()));

    expect(find.text('正在启动邻接'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
