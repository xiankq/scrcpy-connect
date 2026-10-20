import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';

void main() {
  testWidgets(
    'long open lists build only nearby rows and keep the end reachable',
    (tester) async {
      final built = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GroupedListView.builder(
              itemCount: 10000,
              itemBuilder: (context, index) {
                built.add(index);
                return SizedBox(height: 56, child: Text('row $index'));
              },
            ),
          ),
        ),
      );
      expect(built.length, lessThan(100));
      expect(built, isNot(contains(9999)));
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(56.0 * 9999);
      await tester.pumpAndSettle();
      expect(find.text('row 9999'), findsOneWidget);
      expect(find.byType(ContentPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switch rows grow for large text while preserving control target',
    (tester) async {
      for (final scale in [1.0, 2.0]) {
        var toggles = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 200,
                    child: ConnectSwitchRow(
                      title: Text(scale == 1 ? '后台保持' : '很长的后台保持开关标题'),
                      value: false,
                      onChanged: (_) => toggles++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final rowHeight = tester.getSize(find.byType(ConnectSwitchRow)).height;
        expect(rowHeight, scale == 1 ? 56 : greaterThan(56));
        expect(tester.getSize(find.byType(ConnectSwitch)), const Size(44, 44));
        await tester.tap(find.byType(ConnectSwitch));
        expect(toggles, 1);
        await tester.tap(find.text(scale == 1 ? '后台保持' : '很长的后台保持开关标题'));
        expect(toggles, 2);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
