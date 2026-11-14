import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';

void main() {
  testWidgets('desktop zero-height chrome has no gradient layer', (
    tester,
  ) async {
    const key = ValueKey('zero-height-chrome');
    await tester.pumpWidget(
      const MaterialApp(
        home: PageChromeProtection(
          key: key,
          height: 0,
          backgroundColor: Color(0xfff2f2f7),
        ),
      ),
    );

    expect(find.byKey(key), findsOneWidget);
    expect(find.byType(DecoratedBox), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
