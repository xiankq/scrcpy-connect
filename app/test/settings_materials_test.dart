import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/pages/devices/details/capabilities/devices_details_capabilities_page.dart';
import 'package:scrcpy_connect/pages/settings/appearance/settings_appearance_page.dart';
import 'package:scrcpy_connect/pages/settings/data_preferences/settings_data_preferences_page.dart';
import 'package:scrcpy_connect/pages/settings/index/settings_index_page.dart';
import 'package:scrcpy_connect/pages/settings/media_cache/settings_media_cache_page.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';

import 'support/router_test_app.dart';
import 'support/test_controller.dart';

void main() {
  for (final name in [
    'settings',
    'appearance',
    'records',
    'cache',
    'capabilities',
  ]) {
    testWidgets(
      '$name fixed options remain grouped and readable at large text',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = createTestController((
          command, [
          params = const {},
        ]) async {
          return switch (command) {
            'device.capabilities' => {
              'capabilities': [
                for (final id in ['screen', 'audio', 'files'])
                  {
                    'id': id,
                    'name': '较长的功能名称 $id',
                    'status': 'limited',
                    'reason': '功能取决于这台设备的实际授权与系统权限，重新连接后可以再次检查。',
                  },
              ],
            },
            'media.cache.status' => {
              'usedBytes': 2048,
              'budgetBytes': 4096,
              'protectedBytes': 1024,
              'reclaimableBytes': 1024,
              'reservedBytes': 512,
            },
            _ => <String, dynamic>{},
          };
        });
        final Widget page = switch (name) {
          'settings' => SettingsPage(controller: controller),
          'appearance' => AppearancePage(controller: controller),
          'records' => DataPreferencesPage(controller: controller),
          'cache' => MediaCachePage(controller: controller),
          _ => CapabilitiesPage(
            controller: controller,
            device: const {'id': 'test'},
          ),
        };
        await tester.pumpWidget(
          RouterTestApp(
            controller: controller,
            theme: ConnectTokens.theme(Brightness.light),
            home: page,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SettingsGroup), findsWidgets);
        expect(find.byType(ListIconBadge), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
