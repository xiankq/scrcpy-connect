import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

void main() {
  testWidgets('text dialog owns its controller through a slow closing route', (
    tester,
  ) async {
    final originalDilation = timeDilation;
    timeDilation = 10;
    addTearDown(() => timeDilation = originalDilation);
    addTearDown(tester.view.resetViewInsets);
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await askText(context, title: '自定义比例');
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2:3');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    timeDilation = originalDilation;
    expect(result, '2:3');
    expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    final liveController = tester
        .widget<TextField>(find.byType(TextField, skipOffstage: false))
        .controller!;
    void listener() {}
    expect(() => liveController.addListener(listener), returnsNormally);
    liveController.removeListener(listener);
    tester.view.viewInsets = const FakeViewPadding(bottom: 80);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
