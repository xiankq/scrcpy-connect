import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/choice_row.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/devices/workspace/files/directory_picker/devices_workspace_files_directory_picker_page.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  testWidgets('list surfaces add no height around their rows', (tester) async {
    for (final count in [1, 3]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConnectTokens.theme(Brightness.light),
          home: Scaffold(
            body: GroupedListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (var index = 0; index < count; index++)
                  ActionRow(
                    icon: LucideIcons.folder,
                    title: '目录 $index',
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      );
      final panel = tester.getRect(find.byType(ContentPanel));
      final rows = find.byType(ActionRow);
      expect(panel.height, 56 * count);
      expect(tester.getRect(rows.first).top, panel.top);
      expect(tester.getRect(rows.last).bottom, panel.bottom);
      expect(tester.getTopLeft(find.text('目录 0')).dx, panel.left + 50);
      expect(find.text('目录 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'directory selection uses inset rows and a reachable flowing action',
    (tester) async {
      tester.view.physicalSize = const Size(280, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final count in [1, 30]) {
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          if (command == 'files.list') {
            return {
              'entries': [
                for (var index = 0; index < count; index++)
                  {
                    'name': '目录 $index',
                    'path': '/sdcard/$index',
                    'isDirectory': true,
                  },
              ],
            };
          }
          return {};
        });
        await tester.pumpWidget(
          RouterTestApp(
            key: ValueKey('directory-$count'),
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: ShareDirectoryPickerPage(
              controller: controller,
              device: const {'id': 'phone', 'name': '手机'},
              initialPath: '/sdcard',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(ContentPanel).first).dx, 16);
        if (count == 1) {
          expect(tester.getTopLeft(find.text('使用这个目录')).dy, lessThan(400));
        }
        await tester.scrollUntilVisible(find.text('使用这个目录'), 200);
        await tester.pumpAndSettle();
        expect(find.text('使用这个目录').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets('content and option labels share alignment and row height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConnectTokens.theme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: GroupedListView(
              children: [
                ActionRow(icon: LucideIcons.folder, title: '文件', onTap: () {}),
                const SizedBox(height: 16),
                ChoiceRow<int>(
                  value: 0,
                  groupValue: 0,
                  leading: const Icon(LucideIcons.sun, size: 22),
                  title: const Text('浅色'),
                  onChanged: (_) {},
                ),
                ChoiceRow<int>(
                  value: 1,
                  groupValue: 0,
                  leading: const Icon(LucideIcons.moon, size: 22),
                  title: const Text('深色'),
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ActionRow)).height, 56);
    expect(tester.getSize(find.byType(ChoiceRow<int>).first).height, 56);
    expect(tester.getTopLeft(find.text('文件')).dx, 50);
    expect(tester.getTopLeft(find.text('浅色')).dx, 50);
  });

  testWidgets(
    'switch rows grow for large text while preserving control target',
    (tester) async {
      for (final scale in [1.0, 2.0]) {
        var toggles = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ConnectTokens.theme(Brightness.light),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: SizedBox(
                    width: 200,
                    child: ConnectSwitchRow(
                      title: Text(scale == 1 ? '后台保持' : '很长的后台保持开关标题'),
                      value: false,
                      onChanged: (_) => toggles++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final rowHeight = tester.getSize(find.byType(ConnectSwitchRow)).height;
        expect(rowHeight, scale == 1 ? 56 : greaterThan(56));
        expect(tester.getSize(find.byType(ConnectSwitch)), const Size(44, 44));
        await tester.tap(find.byType(ConnectSwitch));
        expect(toggles, 1);
        await tester.tap(find.text(scale == 1 ? '后台保持' : '很长的后台保持开关标题'));
        expect(toggles, 2);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
