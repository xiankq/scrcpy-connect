import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceDetailsPage extends HookConsumerWidget {
  const DeviceDetailsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appControllerProvider.select((state) => state.devices));
    final settings = ref.watch(
      appControllerProvider.select((state) => state.settings),
    );
    final current = controller.currentDevice(device);
    final deviceId = value(current, 'id');
    final allPreferences = jsonObject(settings['deviceSettings']);
    final preferences = jsonObject(allPreferences[deviceId]);
    Future<void> save(String key, bool next) async {
      try {
        await controller.updateDeviceSetting(deviceId, key, next);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      }
    }

    return PageFrame(
      title: '设备详情',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          Row(
            children: [
              const FeatureIcon(
                LucideIcons.smartphone,
                color: ConnectTokens.blue,
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName(current),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: DesignTokens.spacingXxs),
                    Text(
                      statusText(value(current, 'status')),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          CommandView(
            controller: controller,
            command: 'device.info',
            params: {'deviceId': current['id']},
            emptyTitle: '暂时无法更新设备信息',
            builder: (context, info, refresh) => Column(
              children: [
                for (final pair in [
                  ('型号', value(info, 'model', value(current, 'model', '未获取'))),
                  ('Android 版本', value(info, 'androidVersion', '未获取')),
                  (
                    '连接方式',
                    value(
                      info,
                      'transport',
                      value(current, 'transport', '尚未连接'),
                    ),
                  ),
                  (
                    '地址',
                    value(info, 'address', value(current, 'address', '未记录')),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: DesignTokens.spacingSm,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            pair.$1,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: DesignTokens.spacingMd),
                        Expanded(
                          child: Text(pair.$2, textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
                if (current['status'] != 'connected')
                  const StateNote('当前离线，信息来自本机记录，可能尚未更新。'),
              ],
            ),
          ),
          const SectionTitle('设备设置'),
          ConnectSwitchRow(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动同步剪贴板'),

            value: preferences['clipboardSync'] == true,
            onChanged: (next) => save('clipboardSync', next),
          ),
          ConnectSwitchRow(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示底部导航'),

            value: preferences['showNavigationBar'] != false,
            onChanged: (next) => save('showNavigationBar', next),
          ),
          const SectionTitle('连接与能力'),
          ActionRow(
            icon: LucideIcons.network,
            title: '连接偏好',

            onTap: () =>
                DeviceConnectionRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.shieldCheck,
            title: '功能支持状态',
            onTap: () =>
                CapabilitiesRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.stethoscope,
            title: '连接诊断',
            onTap: () =>
                DiagnosticsRoute(deviceId: value(current, 'id'))
                    .push<void>(context),
          ),
          const SectionTitle('设备管理'),
          ActionRow(
            icon: LucideIcons.pencil,
            title: '设备名称',
            onTap: () async {
              final name = await askText(
                context,
                title: '设备名称',
                initial: deviceName(current),
                label: '仅更改本机列表名称',
              );
              if (name != null && context.mounted) {
                await perform(context, controller, 'devices.rename', {
                  'deviceId': current['id'],
                  'name': name,
                });
                await controller.refreshDevices();
              }
            },
          ),

          ActionRow(
            icon: LucideIcons.unplug,
            title: '断开设备连接',

            color: ConnectTokens.secondary,
            onTap: () async {
              if (await confirm(
                    context,
                    '断开 ${deviceName(current)}？',
                    '该设备的控制会话会停止，未完成传输可能中断。已保存文件和本机设备记录会保留。',
                    action: '断开连接',
                  ) &&
                  context.mounted) {
                final result = await perform(
                  context,
                  controller,
                  'devices.disconnect',
                  {'deviceId': current['id']},
                );
                await controller.refreshDevices();
                if (result != null && context.mounted) closePage<void>(context);
              }
            },
          ),
          ActionRow(
            icon: LucideIcons.trash2,
            title: '移除此设备',

            color: ConnectTokens.danger,
            onTap: () async {
              if (await confirm(
                    context,
                    '移除 ${deviceName(current)}？',
                    '将断开连接并删除本机设备记录与偏好。已完成文件不受影响。如需撤销授权，请在被控手机的调试设置中操作。',
                    action: '移除设备',
                    danger: true,
                  ) &&
                  context.mounted) {
                final result = await perform(
                  context,
                  controller,
                  'devices.forget',
                  {'deviceId': current['id']},
                );
                await controller.refreshDevices();
                if (result != null && context.mounted) {
                  goDevices(context);
                }
              }
            },
          ),
          const SizedBox(height: DesignTokens.spacingMd),
        ],
      ),
    );
  }
}
