import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/app.dart';
import 'package:scrcpy_connect/main.dart' as app;
import 'package:scrcpy_connect/pages/devices/workspace/remote/devices_workspace_remote_page.dart';
import 'package:scrcpy_connect/stores/app_store.dart';

/// 保留真实启动与状态核验；测试随后通过正式控件或公开请求执行场景。
Future<AppStore> startProductionApp(WidgetTester tester) async {
  await app.main();
  await waitFor(
    tester,
    () =>
        find.byType(ConnectApp).evaluate().isNotEmpty &&
        find.byType(Scaffold).evaluate().isNotEmpty,
    reason: 'The production application must initialize its UI and bridge.',
  );
  final controller = ProviderScope.containerOf(
    tester.element(find.byType(ConnectApp)),
  ).read(appStoreProvider.notifier);
  await waitFor(
    tester,
    () =>
        !controller.snapshot().loading &&
        !controller.snapshot().reconciliationPending,
    reason: 'The initial production state must finish reconciliation.',
  );
  return controller;
}

void expectHealthyRemote() {
  final remote = find.byType(RemotePage);
  expect(
    find.descendant(of: remote, matching: find.byType(SnackBar)),
    findsNothing,
    reason: 'Feedback from another page must not cover the remote device.',
  );
  expect(
    find.descendant(of: remote, matching: find.text('画面已暂停')),
    findsNothing,
  );
  expect(
    find.descendant(of: remote, matching: find.text('暂时无法打开实时画面')),
    findsNothing,
  );
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 35),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(ready(), isTrue, reason: reason);
}

Future<void> tapPageAction(
  WidgetTester tester,
  Finder page,
  Finder action, {
  double delta = 250,
}) async {
  final route = ModalRoute.of(tester.element(page));
  await waitFor(
    tester,
    () => route?.animation?.status == AnimationStatus.completed,
    timeout: const Duration(seconds: 5),
    reason: 'Wait for the actual page transition before scrolling.',
  );
  await tester.scrollUntilVisible(
    action,
    delta,
    scrollable: find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 12,
  );
  await Scrollable.ensureVisible(tester.element(action), alignment: .5);
  await tester.pump(const Duration(milliseconds: 300));
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action.hitTestable());
}
