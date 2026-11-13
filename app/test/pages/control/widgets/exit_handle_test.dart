import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/exit_handle.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

void main() {
  testWidgets('remote control panel uses an opaque content surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: GlassPreferences(
          reduceTransparency: true,
          child: Scaffold(
            body: ExitHandle(
              deviceLabel: '测试设备',
              onExit: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remote-tool-handle')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('remote-tool-panel')),
      findsOneWidget,
    );
    expect(
      tester.widget<ContentSurface>(
        find.byKey(const ValueKey('remote-tool-panel')),
      ),
      isA<ContentSurface>(),
    );
  });
}
