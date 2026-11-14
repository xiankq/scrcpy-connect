import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/exit_handle.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/glass/glass_preferences.dart';
import 'package:scrcpy_connect/widgets/overlays.dart';

void main() {
  test('initial remote control handle follows the design right edge', () {
    final bounds = ExitHandle.initialBoundsFor(
      const Size(402, 874),
      const MediaQueryData(
        padding: EdgeInsets.only(right: 12),
        systemGestureInsets: EdgeInsets.only(right: 12),
      ),
    );

    expect(bounds.left, 338);
    expect(bounds.right, 390);
    expect(bounds.top, closeTo(384.56, 0.01));
  });

  testWidgets('remote control panel uses an opaque content surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: GlassPreferences(
          reduceTransparency: true,
          child: Scaffold(
            body: ExitHandle(deviceLabel: '测试设备', onExit: () {}),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remote-tool-handle')));
    await tester.pump();

    expect(find.byKey(const ValueKey('remote-tool-panel')), findsOneWidget);
    final handle = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('remote-tool-handle-position')),
    );
    expect(handle.localToGlobal(Offset.zero).dx, greaterThan(300));
    expect(
      tester.widget<ContentSurface>(
        find.byKey(const ValueKey('remote-tool-panel')),
      ),
      isA<ContentSurface>(),
    );
  });
}
