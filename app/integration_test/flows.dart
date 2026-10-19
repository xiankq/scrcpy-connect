import 'package:scrcpy_connect/pages/devices/workspace/index/devices_workspace_index_page.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> returnFromFiles(WidgetTester tester) async {
  final files = find.byType(FilesPage);
  final route = ModalRoute.of(tester.element(files));
  final enteringDeadline = DateTime.now().add(const Duration(seconds: 5));
  while (route?.animation?.status != AnimationStatus.completed &&
      DateTime.now().isBefore(enteringDeadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(route?.animation?.status, AnimationStatus.completed);
  final back = find.descendant(
    of: files,
    matching: find.byTooltip(
      MaterialLocalizations.of(tester.element(files)).backButtonTooltip,
    ),
  );
  expect(back, findsOneWidget);
  await tester.tap(back);
  // The old workspace can coexist with the entering file route during its
  // transition. Scope the action and wait for the popped route to disappear.
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (files.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(files, findsNothing);
  expect(find.byType(DeviceWorkspacePage), findsOneWidget);
  await tester.scrollUntilVisible(
    find.text('打开手机屏幕'),
    -250,
    scrollable: find
        .descendant(
          of: find.byType(DeviceWorkspacePage),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 12,
  );
  await tester.pump(const Duration(milliseconds: 100));
}
