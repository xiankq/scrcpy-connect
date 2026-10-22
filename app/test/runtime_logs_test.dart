import 'dart:convert';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interop_bridge/interop_bridge.dart';
import 'package:scrcpy_connect/pages/settings/runtime_logs/settings_runtime_logs_page.dart';

import 'support/test_controller.dart';

import 'package:scrcpy_connect/services/app_controller.dart';

void main() {
  late AppController controller;
  late Directory directory;
  late DiagnosticLog log;
  setUp(() async {
    controller = createTestController((_, [params = const {}]) async => {});
    directory = await Directory.systemTemp.createTemp('connect-log-ui-');
    log = await DiagnosticLog.open(directory);
    log.record(
      DiagnosticArea.video,
      'decoder.selected',
      fields: {'decoder': 'FFmpeg', 'acceleration': 'software'},
    );
    log.record(DiagnosticArea.app, 'bootstrap.failed', level: LogLevel.error);
    await log.flush();
  });
  tearDown(() async {
    controller.dispose();
    await log.close();
    await directory.delete(recursive: true);
  });

  testWidgets('filtering does not restrict export; cancelled export is quiet', (
    tester,
  ) async {
    String? exported;
    await tester.pumpWidget(
      TestProviderScope(
        controller: controller,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: RuntimeLogsPage(
            log: log,
            save: (bytes) async {
              exported = utf8.decode(bytes);
              return false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pumpAndSettle();
    expect(find.text('初始化失败'), findsOneWidget);
    expect(find.textContaining('已选用解码器'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('导出日志'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(exported, contains('FFmpeg'));
    expect(exported, contains('bootstrap.failed'));
    expect(find.text('运行日志已导出'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear requires confirmation and new events still appear', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestProviderScope(
        controller: controller,
        child: MaterialApp(
          theme: ConnectTokens.theme(Brightness.dark),
          home: RuntimeLogsPage(log: log),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();
    expect(log.recent, hasLength(2));
    await tester.runAsync(() async {
      await tester.tap(find.text('清空日志').last);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    for (var turn = 0; turn < 40 && log.recent.isNotEmpty; turn++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
    expect(log.recent, isEmpty);
    expect(find.text('暂无符合条件的日志'), findsOneWidget);
    await tester.runAsync(() async {
      log.record(DiagnosticArea.app, 'bootstrap.ready');
      await log.flush();
    });
    await tester.pumpAndSettle();
    expect(find.text('初始化完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Drain IO outside the widget binding's fake async zone.
    await tester.runAsync(log.close);
  });

  testWidgets('narrow screen and large text keep filters and actions usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          home: RuntimeLogsPage(log: log),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '错误'));
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('初始化失败'), 200);
    expect(find.byTooltip('导出日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(log.close);
  });
}
