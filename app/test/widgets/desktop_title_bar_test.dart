import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/desktop_window.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/desktop_title_bar.dart';
import 'package:scrcpy_connect/widgets/desktop_window_frame.dart';

final class _FakeControls implements DesktopWindowControls {
  final calls = <String>[];

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> toggleMaximized() async => calls.add('toggleMaximized');

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> startMove() async => calls.add('startMove');
}

Finder _button(DesktopWindowGlyph g) => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is DesktopWindowGlyphPainter &&
      (widget.painter! as DesktopWindowGlyphPainter).glyph == g,
);

void main() {
  Future<_FakeControls> pumpBar(
    WidgetTester tester, {
    bool maximized = false,
  }) async {
    final controls = _FakeControls();
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Align(
          alignment: Alignment.topCenter,
          child: DesktopTitleBar(
            title: '邻接',
            maximized: maximized,
            controls: controls,
          ),
        ),
      ),
    );
    return controls;
  }

  testWidgets('keys and blank area drive the window controls', (tester) async {
    final controls = await pumpBar(tester);

    await tester.tap(_button(DesktopWindowGlyph.minimize));
    await tester.tap(_button(DesktopWindowGlyph.maximize));
    await tester.tap(_button(DesktopWindowGlyph.close));
    expect(controls.calls, ['minimize', 'toggleMaximized', 'close']);
    controls.calls.clear();

    await tester.drag(find.text('邻接'), const Offset(60, 0));
    await tester.pump(kDoubleTapTimeout);
    expect(controls.calls, ['startMove']);
    controls.calls.clear();

    final blank = tester.getCenter(find.byType(DesktopTitleBar));
    await tester.tapAt(blank);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(blank);
    await tester.pumpAndSettle();
    expect(controls.calls, ['toggleMaximized']);
  });

  // 标题栏挂在页面导航之上，没有 Material 祖先时标题曾带调试用的黄色下划线。
  testWidgets('title outside any page keeps the normal text style', (
    tester,
  ) async {
    await pumpBar(tester);
    final title = tester.widget<RichText>(
      find.descendant(
        of: find.byType(DesktopTitleBar),
        matching: find.byType(RichText),
      ),
    );
    expect(title.text.style?.decoration, anyOf(isNull, TextDecoration.none));
  });

  testWidgets('maximized window shows the restore key', (tester) async {
    await pumpBar(tester);
    expect(find.bySemanticsLabel('最大化'), findsOneWidget);
    expect(find.bySemanticsLabel('还原'), findsNothing);

    final controls = await pumpBar(tester, maximized: true);
    expect(_button(DesktopWindowGlyph.maximize), findsNothing);
    expect(_button(DesktopWindowGlyph.restore), findsOneWidget);
    expect(find.bySemanticsLabel('还原'), findsOneWidget);
    await tester.tap(_button(DesktopWindowGlyph.restore));
    expect(controls.calls, ['toggleMaximized']);
  });

  group('DesktopWindowFrame', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(
      () => messenger.setMockMethodCallHandler(DesktopWindow.channel, null),
    );

    testWidgets('draws the title bar only when the runner asks for it', (
      tester,
    ) async {
      var layout = <String, Object>{'left': 0, 'right': 0, 'top': 0};
      messenger.setMockMethodCallHandler(
        DesktopWindow.channel,
        (call) async => layout,
      );
      const content = ValueKey('content');
      Widget app() => MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        builder: (context, child) =>
            DesktopWindowFrame(title: '邻接', child: child!),
        home: Builder(
          builder: (context) => SizedBox.expand(
            key: content,
            child: Text('${MediaQuery.sizeOf(context).height}'),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(DesktopTitleBar), findsNothing);
      expect(tester.getRect(find.byKey(content)).top, 0);

      layout = {...layout, 'titleBar': true, 'maximized': false};
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(
        tester.getRect(find.byKey(content)).top,
        DesktopTitleBarMetrics.height,
      );
      expect(find.text('${600 - DesktopTitleBarMetrics.height}'), findsOne);
      expect(_button(DesktopWindowGlyph.maximize), findsOneWidget);

      await messenger.handlePlatformMessage(
        DesktopWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('layoutChanged', {
            'left': 0,
            'right': 0,
            'top': 0,
            'titleBar': true,
            'maximized': true,
          }),
        ),
        (_) {},
      );
      await tester.pump();
      expect(_button(DesktopWindowGlyph.restore), findsOneWidget);
    });

    testWidgets('platform controls call the window channel', (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(DesktopWindow.channel, (call) async {
        calls.add(call.method);
        return null;
      });
      const controls = PlatformDesktopWindowControls();
      await controls.minimize();
      await controls.toggleMaximized();
      await controls.close();
      await controls.startMove();
      expect(calls, ['minimize', 'toggleMaximized', 'close', 'move']);
    });
  });
}
