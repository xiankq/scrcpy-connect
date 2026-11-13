import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_navigation_bar.dart';

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
      ..physicalSize = const Size(402, 100)
      ..devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: _Subject()));

    final positions = [
      tester.getCenter(find.byType(IconButton).at(0)).dx,
      tester.getCenter(find.byType(IconButton).at(1)).dx,
      tester.getCenter(find.byType(IconButton).at(2)).dx,
    ];

    expect(find.byType(IconButton), findsNWidgets(3));
    expect(positions, orderedEquals([89.5, 201, 312.5]));
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
      ..physicalSize = const Size(240, 100)
      ..devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: _Subject()));

    expect(find.byType(IconButton), findsNWidgets(3));
    expect(tester.takeException(), isNull);
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
