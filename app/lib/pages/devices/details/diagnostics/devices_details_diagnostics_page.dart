import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/connection_content.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '连接诊断',
    child: ConnectionContent(
      child: CommandView(
        controller: controller,
        command: 'device.diagnose',
        params: {'deviceId': device['id']},
        emptyTitle: '暂时无法完成诊断',
        builder: (context, data, refresh) {
          final current = data['device'] is Map<Object?, Object?>
              ? jsonObject(data['device'])
              : device;
          final connected = data['connected'];
          final unauthorized = current['status'] == 'unauthorized';
          final usb = current['transport'] == 'usb';
          final reachable = data['tcpReachable'];
          final identity = data['identityPresent'];
          final checks = <Json>[
            {
              'name': connected == true
                  ? '设备连接正常'
                  : unauthorized
                  ? '需要重新授权'
                  : connected == false
                  ? '设备尚未连接'
                  : '连接状态尚未确认',
              'ok': connected == true,
              'message': connected == true
                  ? '连接已建立。'
                  : unauthorized
                  ? '请在手机上重新授权，再检查连接。'
                  : '检查网络或 USB 状态，再连接手机。',
            },
            if (usb)
              {
                'name': data['usbBackendAvailable'] == false
                    ? '当前平台无法使用 USB'
                    : connected == true
                    ? 'USB 连接已建立'
                    : 'USB 连接需要检查',
                'ok': connected == true,
                'message': data['usbBackendAvailable'] == false
                    ? '改用无线连接，并在手机上完成配对。'
                    : '检查主机角色与数据线；本机允许 USB 访问，手机允许调试。',
              }
            else
              {
                'name': reachable == true
                    ? '网络地址可达'
                    : reachable == false
                    ? '无法访问设备地址'
                    : '网络路径尚未检查',
                'ok': reachable == true,
                'message': reachable == true
                    ? '地址可达，仍需确认授权与连接。'
                    : reachable == false
                    ? '核对手机地址、连接端口和网络；跨网需已有 VPN 等可达路径。'
                    : '核对地址和连接端口后重新检查。',
              },
            {
              'name': identity == true
                  ? '本机授权身份已就绪'
                  : identity == false
                  ? '本机授权身份不可用'
                  : '本机授权身份尚未确认',
              'ok': identity == true,
              'message': identity == true
                  ? '以手机实际授权结果为准。'
                  : '检查本机授权身份，并在手机上确认授权。',
            },
          ];
          final details = <Widget>[
            if (!usb && value(current, 'address').isNotEmpty)
              StateNote(
                '当前地址：${value(current, 'address')} · 连接端口：${value(current, 'port', '未记录')}',
              ),
            SettingsGroup(
              children: [
                for (final check in checks)
                  ListTile(
                    leading: ListIconBadge(
                      icon: check['ok'] == true
                          ? LucideIcons.circleCheck
                          : LucideIcons.circleAlert,
                      backgroundColor: check['ok'] == true
                          ? DesignTokens.colorListIconMint
                          : DesignTokens.colorListIconAmber,
                    ),
                    title: Text(
                      value(check, 'name'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: check['ok'] == true
                        ? null
                        : Text(
                            value(check, 'message'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                  ),
              ],
            ),
            if (value(current, 'reason').isNotEmpty)
              StateNote(value(current, 'reason')),
          ];
          final actions = <Widget>[
            const SizedBox(height: DesignTokens.spacingMd),
            FilledButton(onPressed: refresh, child: const Text('重新检查')),
          ];
          return GroupedListView.builder(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            itemCount: details.length + actions.length,
            itemBuilder: (context, index) {
              if (index < details.length) return details[index];
              index -= details.length;
              return actions[index];
            },
          );
        },
      ),
    ),
  );
}
