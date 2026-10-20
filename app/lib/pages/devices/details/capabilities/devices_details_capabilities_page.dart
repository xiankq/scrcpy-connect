import 'package:scrcpy_connect/widgets/grouped_list.dart';
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
    child: CommandView(
      controller: controller,
      command: 'device.capabilities',
      params: {'deviceId': device['id']},
      emptyTitle: '尚未获得功能支持状态',
      builder: (context, data, refresh) {
        final capabilities = objects(data['capabilities']);
        final footer = <Widget>[
          if (capabilities.isEmpty) const StateNote('尚未检查这台设备的功能。请连接后重新检查。'),
          const SizedBox(height: DesignTokens.spacingMd),
          OutlinedButton.icon(
            onPressed: refresh,
            icon: const Icon(
              LucideIcons.refreshCw,
              size: DesignTokens.componentIconActionSize,
            ),
            label: const Text('重新检查'),
          ),
        ];
        return GroupedListView.builder(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          itemCount: 1 + capabilities.length + footer.length,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const StateNote('已连接不代表每项功能都可用。支持状态以这台设备的实际检查结果为准。');
            }
            final item = index - 1;
            if (item >= capabilities.length) {
              return footer[item - capabilities.length];
            }
            final cap = capabilities[item];
            return Padding(
              key: ValueKey((
                'capability',
                value(device, 'id'),
                value(cap, 'id', value(cap, 'key')),
                item,
              )),
              padding: const EdgeInsets.only(bottom: DesignTokens.spacingSm),
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
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
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spacingXs,
                        ),
                        child: Text(value(cap, 'reason')),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
