import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CapabilitiesPage extends StatelessWidget {
  const CapabilitiesPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '功能支持状态',
    subtitle: deviceName(device),
    child: CommandView(
      controller: controller,
      command: 'device.capabilities',
      params: {'deviceId': device['id']},
      emptyTitle: '尚未获得功能支持状态',
      builder: (context, data, refresh) {
        final capabilities = objects(data['capabilities']);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const StateNote('已连接不代表每项功能都可用。支持状态以这台设备的实际检查结果为准。'),
            for (final cap in capabilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              value(cap, 'name', value(cap, 'id')),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            statusText(value(cap, 'status')),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (value(cap, 'reason').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(value(cap, 'reason')),
                        ),
                    ],
                  ),
                ),
              ),
            if (capabilities.isEmpty) const StateNote('尚未检查这台设备的功能。请连接后重新检查。'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('重新检查'),
            ),
          ],
        );
      },
    ),
  );
}
