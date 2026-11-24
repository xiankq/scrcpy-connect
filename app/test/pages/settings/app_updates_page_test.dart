import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scrcpy_connect/core/platform/app_info.dart';
import 'package:scrcpy_connect/core/platform/app_release.dart';
import 'package:scrcpy_connect/core/platform/app_update_provider.dart';
import 'package:scrcpy_connect/core/platform/platform_capabilities_provider.dart';
import 'package:scrcpy_connect/core/recovery/models/recovery_state.dart';
import 'package:scrcpy_connect/core/recovery/recovery_state_notifier.dart';
import 'package:scrcpy_connect/pages/settings/app_updates_page.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';

void main() {
  testWidgets('宽矮窗口仍能读到真实的当前版本、更新内容和历史', (tester) async {
    final response = Completer<List<AppRelease>>();
    await _showUpdates(
      tester,
      size: const Size(1120, 430),
      readReleases: () => response.future,
    );
    expect(find.text('当前版本'), findsOneWidget);
    expect(find.text('0.1.0'), findsOneWidget);
    expect(find.text('构建 5'), findsOneWidget);
    final versionRow = tester.getRect(find.widgetWithText(ListTile, '当前版本'));
    final checkRow = tester.getRect(find.widgetWithText(ListTile, '检查更新'));
    final historyRow = tester.getRect(find.widgetWithText(ListTile, '更新记录'));
    expect(checkRow.top, versionRow.bottom);
    expect(historyRow.top, checkRow.bottom);
    expect(
      tester.getTopRight(find.text('0.1.0')).dx,
      versionRow.right - DesignTokens.spacingMd,
    );
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(find.text('正在检查…'), findsOneWidget);
    response.complete([
      AppRelease(
        version: '0.2.0',
        build: 1,
        publishedAt: DateTime(2026, 11),
        notes: ['新增平板工作区与设备管理'],
        url: Uri.parse('https://example.com/releases/0.2.0'),
      ),
      AppRelease(
        version: '0.1.0',
        build: 5,
        publishedAt: DateTime(2026, 10),
        notes: ['此构建已安装'],
        url: Uri.parse('https://example.com/releases/0.1.0'),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('新增平板工作区与设备管理'), findsOneWidget);
    expect(find.text('前往发布渠道'), findsOneWidget);
    final summary = tester.getRect(find.text('发现新版本'));
    final notes = tester.getRect(find.text('新增平板工作区与设备管理'));
    final action = tester.getRect(find.widgetWithText(FilledButton, '前往发布渠道'));
    expect(summary.right, lessThan(notes.left));
    expect(action.left, notes.left);
    expect(action.top, greaterThan(notes.bottom));
    await tester.tap(find.text('查看更新记录'));
    await tester.pumpAndSettle();
    expect(find.text('已安装'), findsOneWidget);
    expect(find.text('此构建已安装'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏双倍字号下当前版本和构建号随行增高', (tester) async {
    await _showUpdates(
      tester,
      size: const Size(320, 700),
      brightness: Brightness.dark,
      textScale: 2,
    );
    final row = tester.getRect(find.widgetWithText(ListTile, '当前版本'));
    expect(row.contains(tester.getCenter(find.text('0.1.0'))), isTrue);
    expect(row.bottom, greaterThan(tester.getBottomLeft(find.text('构建 5')).dy));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showUpdates(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Future<List<AppRelease>> Function()? readReleases,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appInfoReaderProvider.overrideWithValue(
          () async => const AppInfo(
            appName: '邻接',
            packageName: 'dev.scrcpyconnect.scrcpyConnect',
            version: '0.1.0',
            buildNumber: '5',
          ),
        ),
        recoveryStateProvider.overrideWith(_Recovery.new),
        appUpdateReaderProvider.overrideWithValue(readReleases),
      ],
      child: MaterialApp(
        theme: ConnectTokens.theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AppUpdatesPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Recovery extends RecoveryStateNotifier {
  @override
  RecoveryState build() => RecoveryState();
}
