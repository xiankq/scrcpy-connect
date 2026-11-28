import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_opening_view.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_recovery_panel.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_surface.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/page_loader.dart';

void main() {
  testWidgets('等待首帧时延迟显示加载，失败时给出原因、重试和关闭，减弱动效时形状静止', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 550)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final presentation = RemotePresentation()..deferStart();
    final inputs = _Inputs();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Future<void> show({bool reduceMotion = false}) => tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            reduceMotion: reduceMotion,
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 28, bottom: 24),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: RemoteStage(
            presentation: presentation,
            inputs: inputs,
            onViewport: (_) {},
            deviceLabel: '测试手机',
            independent: false,
            recovery: RemoteRecoveryPanel(
              presentation: presentation,
              independent: false,
              waitingForFirstFrame: true,
              onManageActivities: () {},
              onContinueOnPhoneScreen: () {},
              onCloseUnknownAppLaunch: () {},
              onRetry: () {},
            ),
            ime: false,
            sensitive: false,
            needsWake: false,
            screenOff: false,
            inputFocus: focus,
            onWake: null,
            onClose: () {},
            controls: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    List<List<Object?>> drawCalls(Symbol method) {
      final finder = find.descendant(
        of: find.byType(RemoteOpeningView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is LoaderShapesPainter,
        ),
      );
      if (finder.evaluate().isEmpty) return const [];
      final field = tester.widget<CustomPaint>(finder.first);
      final canvas = TestRecordingCanvas();
      field.painter!.paint(canvas, tester.getSize(finder.first));
      return [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == method)
            call.invocation.positionalArguments.take(2).toList(),
      ];
    }

    await show();
    // 等待不足 400 毫秒时不闪出加载形状。
    expect(drawCalls(#drawPath), isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(drawCalls(#drawPath), hasLength(3));

    presentation.failOperation('未收到手机画面。');
    await show();
    expect(find.text('未收到手机画面。'), findsOneWidget);
    expect(find.text('未能启动画面服务'), findsOneWidget);
    expect(find.text('重试').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote-first-frame-close')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(RemoteRecoveryPanel),
        matching: find.byType(RemoteOpeningFailureMark),
      ),
      findsOneWidget,
    );
    expect(drawCalls(#drawPath), isEmpty);

    presentation.beginStart();
    await show();
    expect(drawCalls(#drawPath), hasLength(3));
    expect(find.byType(RemoteOpeningFailureMark), findsNothing);

    await show(reduceMotion: true);
    final still = drawCalls(#translate);
    await tester.pump(const Duration(seconds: 1));
    expect(drawCalls(#translate), still);
  });
}

class _Inputs implements RemoteInputOwner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
