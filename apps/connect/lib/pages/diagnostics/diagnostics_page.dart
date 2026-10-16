import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
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
    subtitle: deviceName(device),
    child: CommandView(
      controller: controller,
      command: 'device.diagnose',
      params: {'deviceId': device['id']},
      emptyTitle: '暂时无法完成诊断',
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (final check in objects(data['checks']))
            ActionRow(
              icon: check['ok'] == true
                  ? LucideIcons.circleCheck
                  : LucideIcons.circleAlert,
              title: value(check, 'name'),
              subtitle: value(check, 'message', value(check, 'reason')),
              color: check['ok'] == true
                  ? ConnectTokens.mint
                  : ConnectTokens.amber,
            ),
          if (data['message'] != null) StateNote(value(data, 'message')),
          const SizedBox(height: 20),
          FilledButton(onPressed: refresh, child: const Text('重新检查')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => ConnectionFormRoute(
              address: value(device, 'address'),
              deviceId: value(device, 'id'),
            ).push<void>(context),
            child: const Text('编辑地址与端口'),
          ),
          TextButton(
            onPressed: () => UsbGuideRoute().push<void>(context),
            child: const Text('改用 USB'),
          ),
        ],
      ),
    ),
  );
}
