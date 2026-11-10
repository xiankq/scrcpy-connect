import 'dart:async';

import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/styles/system_visual_preferences.dart';
import 'package:scrcpy_connect/app.dart';

import 'support/test_controller.dart';

const _device = {'id': 'phone-a', 'name': '来源手机'};

void main() {
  testWidgets(
    'system font changes update both themes without accepting old reads',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      const methods = MethodChannel('dev.scrcpyconnect/system_typography');
      const events = MethodChannel(
        'dev.scrcpyconnect/system_typography/events',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      final initial = Completer<Object?>();
      var reads = 0;
      var cancelled = false;
      messenger.setMockMethodCallHandler(methods, (_) async {
        if (++reads == 1) return initial.future;
        return {'revision': 3, 'fontFamily': 'Resume Font'};
      });
      messenger.setMockMethodCallHandler(events, (call) async {
        if (call.method == 'cancel') cancelled = true;
        return null;
      });
      final controller = createTestController(
        (_, [params = const {}]) async => {},
      );
      addTearDown(() {
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(methods, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await tester.pumpWidget(
        TestProviderScope(controller: controller, child: const ConnectApp()),
      );
      void expectFamily(String family) {
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        for (final theme in [app.theme!, app.darkTheme!]) {
          expect(theme.textTheme.bodyLarge?.fontFamily, family);
          expect(theme.textTheme.displaySmall?.fontFamily, family);
          expect(theme.listTileTheme.titleTextStyle?.fontFamily, family);
          expect(
            theme.filledButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
            family,
          );
        }
      }

      tester.binding.channelBuffers.push(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'revision': 2,
          'fontFamily': 'Desktop Font',
        }),
        (_) {},
      );
      await tester.pump();
      expectFamily('Desktop Font');
      initial.complete({'revision': 1, 'fontFamily': 'Old Font'});
      await tester.pump();
      expectFamily('Desktop Font');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(reads, 2);
      expectFamily('Resume Font');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(cancelled, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(reads, 2);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final apple = ConnectTokens.theme(Brightness.light);
      expect(apple.textTheme.titleLarge?.fontFamily, 'CupertinoSystemText');
      expect(
        apple.textTheme.displaySmall?.fontFamily,
        'CupertinoSystemDisplay',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        ConnectTokens.theme(Brightness.light).textTheme.bodyLarge?.fontFamily,
        'sans-serif',
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('system transparency rejects late reads and rechecks on resume', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const methods = MethodChannel('dev.scrcpyconnect/visual_preferences');
    const events = MethodChannel('dev.scrcpyconnect/visual_preferences/events');
    final messenger = tester.binding.defaultBinaryMessenger;
    final initial = Completer<Object?>();
    var reads = 0;
    var cancelled = false;
    messenger.setMockMethodCallHandler(methods, (_) async {
      if (++reads == 1) return initial.future;
      return {'revision': 3, 'reduceTransparency': false};
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      if (call.method == 'cancel') cancelled = true;
      return null;
    });
    final preferences = SystemVisualPreferences()..start();
    var disposed = false;
    var changes = 0;
    preferences.addListener(() => changes++);
    addTearDown(() {
      if (!disposed) preferences.dispose();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    await tester.pump();
    tester.binding.channelBuffers.push(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'revision': 2,
        'reduceTransparency': true,
      }),
      (_) {},
    );
    await tester.pump();
    expect(preferences.reduceTransparency, isTrue);
    expect(changes, 1);
    initial.complete({'revision': 1, 'reduceTransparency': false});
    await tester.pump();
    expect(preferences.reduceTransparency, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 2);
    expect(preferences.reduceTransparency, isFalse);
    expect(changes, 2);
    preferences.dispose();
    disposed = true;
    await tester.pump();
    expect(cancelled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'verified call card scrolls at 2x without unsupported audio controls',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final actions = <Json>[];
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'calls.action') actions.add(params);
        return command == 'calls.list'
            ? {
                'status': 'available',
                'live': true,
                'calls': [
                  {
                    'id': 'call-a',
                    'name': '这是来自手机的当前真实通话，较长的来电名称仍应完整呈现',
                    'state': 'active',
                    'canSetRoute': true,
                    'routes': [
                      {'id': 'speaker', 'name': '扬声器'},
                    ],
                  },
                ],
              }
            : {};
      });
      try {
        controller.loading = false;
        await tester.pumpWidget(
          TestProviderScope(
            controller: controller,
            child: MaterialApp(
              theme: ConnectTokens.theme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: WorkspaceCallCard(
                    controller: controller,
                    device: const {..._device, 'status': 'connected'},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('声音仍在手机').hitTestable(),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('来源手机'), findsOneWidget);
        expect(find.textContaining('声音仍在手机'), findsOneWidget);
        expect(find.text('声音路由'), findsNothing);
        expect(find.text('在此接听'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(actions, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
}
