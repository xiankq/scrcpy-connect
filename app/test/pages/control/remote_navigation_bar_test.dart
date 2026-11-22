import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_navigation_bar.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';

void main() {
  testWidgets('uses the design spacing at the 402 point reference width', (
    tester,
  ) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio;
    });
    tester.view
      ..physicalSize = Size(
        DesignTokens.componentPhoneWidth,
        DesignTokens.componentRemoteNavigationHeight,
      )
      ..devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: _Subject()));

    final positions = [
      tester.getCenter(find.byType(IconButton).at(0)).dx,
      tester.getCenter(find.byType(IconButton).at(1)).dx,
      tester.getCenter(find.byType(IconButton).at(2)).dx,
    ];

    expect(find.byType(IconButton), findsNWidgets(3));
    expect(
      positions,
      orderedEquals([
        DesignTokens.componentRemoteNavigationPadding +
            DesignTokens.componentIconButtonSize / 2,
        DesignTokens.componentPhoneWidth / 2,
        DesignTokens.componentPhoneWidth -
            DesignTokens.componentRemoteNavigationPadding -
            DesignTokens.componentIconButtonSize / 2,
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrinks edge padding when the remote view is narrower', (
    tester,
  ) async {
    final oldSize = tester.view.physicalSize;
    final oldRatio = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view
        ..physicalSize = oldSize
        ..devicePixelRatio = oldRatio;
    });
    tester.view
      ..physicalSize = Size(240, DesignTokens.componentRemoteNavigationHeight)
      ..devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: _Subject()));

    expect(find.byType(IconButton), findsNWidgets(3));
    final edgePadding = (240 - DesignTokens.componentIconButtonSize * 3) / 4;
    expect(
      [
        tester.getCenter(find.byType(IconButton).at(0)).dx,
        tester.getCenter(find.byType(IconButton).at(1)).dx,
        tester.getCenter(find.byType(IconButton).at(2)).dx,
      ],
      orderedEquals([
        edgePadding + DesignTokens.componentIconButtonSize / 2,
        120,
        240 - edgePadding - DesignTokens.componentIconButtonSize / 2,
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws the back key as a closed, stroked outline', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Subject()));
    final glyph = find.descendant(
      of: find.byTooltip('返回'),
      matching: find.byType(CustomPaint),
    );
    final painter = tester.widget<CustomPaint>(glyph).painter!;
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, tester.getSize(glyph));
    final draw = canvas.invocations
        .map((entry) => entry.invocation)
        .singleWhere((call) => call.memberName == #drawPath);
    final path = draw.positionalArguments[0] as Path;
    final paint = draw.positionalArguments[1] as Paint;
    expect(path.computeMetrics().single.isClosed, isTrue);
    expect(paint.style, PaintingStyle.stroke);
    expect(paint.strokeJoin, StrokeJoin.round);
  });
}

class _Subject extends StatelessWidget {
  const _Subject();

  @override
  Widget build(BuildContext context) => RemoteNavigationBar(
    enabled: true,
    onBack: _noop,
    onHome: _noop,
    onRecent: _noop,
  );

  static void _noop() {}
}
