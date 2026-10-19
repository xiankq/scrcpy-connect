import 'package:flutter/rendering.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';

void main() {
  testWidgets(
    'text prompt keeps keyboard submit and trimmed result at large text',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await askText(
                    context,
                    title: '重命名一个较长的文件名称',
                    initial: 'old.txt',
                    label: '仅更改本机列表名称',
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(Glass), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      final explanation = find.text('仅更改本机列表名称');
      expect(explanation, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(explanation);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.widget<Text>(explanation).maxLines, isNull);
      expect(
        tester.getSemantics(find.byType(TextField)).getSemanticsData().label,
        '仅更改本机列表名称',
      );
      semantics.dispose();

      await tester.enterText(find.byType(TextField), '  new.txt  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'new.txt');
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('confirmation preserves dismissal and explicit acceptance', (
    tester,
  ) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                results.add(
                  await confirm(
                    context,
                    '删除文件？',
                    '将删除手机上的文件。',
                    action: '删除',
                    danger: true,
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(results, [false]);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(results, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating feedback uses glass with the receiving theme foreground',
    (tester) async {
      for (final brightness in Brightness.values) {
        final theme = ConnectTokens.theme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(brightness),
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => feedback(context, '保存完成'),
                  child: const Text('提示'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('提示'));
        await tester.pumpAndSettle();
        expect(find.byType(Glass), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('保存完成')).style?.color,
          theme.colorScheme.onSurface,
        );
        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, Colors.transparent);
        expect(bar.behavior, SnackBarBehavior.floating);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
