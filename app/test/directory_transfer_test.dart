import 'support/test_controller.dart';

import 'package:scrcpy_connect/pages/devices/workspace/files/index/devices_workspace_files_index_page.dart';
import 'package:scrcpy_connect/services/app_controller.dart';

import 'support/router_test_app.dart';

import 'package:design_system/design_system.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DirectoryPicker extends FilePickerPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => '/tmp/Documents';
}

void main() {
  testWidgets(
    'desktop folder selection sends its exact destination root as one batch',
    (tester) async {
      final picker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = DirectoryPicker();
      addTearDown(() => FilePickerPlatform.instance = picker);
      Json? pushed;
      final controller = createTestController((
        command, [
        params = const {},
      ]) async {
        if (command == 'files.list') return {'entries': <Json>[]};
        if (command == 'files.push') pushed = params;
        return {};
      });
      await tester.pumpWidget(
        RouterTestApp(
          controller: controller,
          theme: ConnectTokens.theme(Brightness.light),
          home: FilesPage(
            controller: controller,
            device: const {'id': 'phone'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送本机文件夹'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('发送整个文件夹？'), findsOneWidget);
      await tester.tap(find.text('发送文件夹'));
      await tester.pumpAndSettle();
      expect(pushed, {
        'deviceId': 'phone',
        'items': [
          {'source': '/tmp/Documents', 'destination': '/sdcard/Documents'},
        ],
        'conflict': 'ask',
      });
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
