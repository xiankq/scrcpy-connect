import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';

class DeviceFunctionChecks extends StatelessWidget {
  const DeviceFunctionChecks({
    super.key,
    required this.controller,
    required this.device,
    this.refreshKey,
  });
  final AppController controller;
  final Json device;
  final Object? refreshKey;
  @override
  Widget build(BuildContext context) => CommandView(
    controller: controller,
    command: 'device.capabilities',
    params: {'deviceId': device['id']},
    refreshKey: refreshKey,
    emptyTitle: '暂时无法检查功能',
    builder: (context, data, refresh) {
      final capabilities = objects(data['capabilities']);
      const names = {
        'shell': '设备授权',
        'files': '文件',
        'wirelessPairing': '无线连接',
        'screen': '手机画面',
        'clipboard': '文字剪贴板',
        'apps': '手机应用',
        'audio': '设备声音',
        'notifications': '实时通知',
        'calls': '电话',
        'background': '后台保持',
      };
      return SettingsGroup(
        children: [
          if (capabilities.isEmpty) const StateNote('尚未检查这台设备的功能，请连接后重新检查。'),
          for (final cap in capabilities)
            if (names.containsKey(value(cap, 'id', value(cap, 'key'))))
              ListTile(
                leading: ListIconBadge(
                  icon: cap['status'] == 'available'
                      ? LucideIcons.circleCheck
                      : LucideIcons.circleAlert,
                  backgroundColor: cap['status'] == 'available'
                      ? DesignTokens.colorListIconMint
                      : DesignTokens.colorListIconAmber,
                ),
                title: Text(
                  '${names[value(cap, 'id', value(cap, 'key'))]} · ${statusText(value(cap, 'status'))}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                subtitle: value(cap, 'reason').isEmpty
                    ? null
                    : Text(
                        value(cap, 'reason'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              ),
        ],
      );
    },
  );
}
