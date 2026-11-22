import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/pages/control/remote_input_owner.dart';
import 'package:scrcpy_connect/pages/control/remote_presentation.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_recovery_panel.dart';
import 'package:scrcpy_connect/pages/control/widgets/remote_surface.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/ambient_loading_field.dart';

void main() {
  testWidgets('首帧前球体绕行缩放，失败冻结渐变，重试继续', (tester) async {
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
        of: find.byType(AmbientLoadingField),
        matching: find.byType(CustomPaint),
      );
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
    final initial = drawCalls(#drawCircle);
    final initialGradient = drawCalls(#translate);
    expect(initial, hasLength(3));

    await tester.pump(const Duration(milliseconds: 800));
    final moving = drawCalls(#drawCircle);
    expect(
      moving.map((orb) => orb.first),
      isNot(initial.map((orb) => orb.first)),
    );
    expect(
      moving.map((orb) => orb.last),
      isNot(initial.map((orb) => orb.last)),
    );
    final movingGradient = drawCalls(#translate);
    expect(movingGradient, isNot(initialGradient));

    presentation.failOperation('未收到手机画面。');
    await show();
    expect(find.text('未收到手机画面。'), findsOneWidget);
    expect(find.text('重试').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote-first-frame-close')).hitTestable(),
      findsOneWidget,
    );
    expect(drawCalls(#drawCircle), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(drawCalls(#translate), movingGradient);

    presentation.beginStart();
    await show();
    expect(drawCalls(#drawCircle), moving);
    await tester.pump(const Duration(milliseconds: 800));
    expect(drawCalls(#translate), isNot(movingGradient));

    await show(reduceMotion: true);
    final still = drawCalls(#drawCircle);
    final stillGradient = drawCalls(#translate);
    await tester.pump(const Duration(seconds: 1));
    expect(still, hasLength(3));
    expect(drawCalls(#drawCircle), still);
    expect(drawCalls(#translate), stillGradient);
  });
}

class _Inputs implements RemoteInputOwner {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
