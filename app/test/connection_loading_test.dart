import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/connection/form/widgets/connection_ambient_loading.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

void main() {
  testWidgets(
    'connection ambience has no center status copy and stays cancellable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: ConnectionAmbientLoading(
              cancelling: false,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('正在连接设备'), findsOneWidget);
      expect(find.text('正在连接'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('取消本次尝试'), findsOneWidget);

      await tester.tap(find.text('取消本次尝试'));
      expect(cancelled, isTrue);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );

  testWidgets('the ambient field drifts only when motion is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: const Scaffold(body: AmbientLoadingField(semanticsLabel: '正在等待')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AmbientLoadingField(semanticsLabel: '正在等待')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('connection ambience freezes when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ConnectionAmbientLoading(cancelling: true, onCancel: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('正在取消…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
