import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DeviceWorkspacePage extends ConsumerWidget {
  const DeviceWorkspacePage({
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
    final appAudioError = ref.watch(
      appControllerProvider.select((state) => state.audioError),
    );
    final current = {...device, ...controller.currentDevice(device)};
    final deviceId = value(current, 'id');
    final online = current['status'] == 'connected';
    final preferences = jsonObject(
      jsonObject(settings['deviceSettings'])[deviceId],
    );
    Future<void> save(String key, bool next) async {
      try {
        await controller.updateDeviceSetting(deviceId, key, next);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      }
    }

    return PageFrame(
      title: deviceName(current),
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          DeviceHero(controller: controller, device: current),
          if (appAudioError != null)
            StateNote(appAudioError, icon: LucideIcons.volumeX),
          RunningApps(
            key: ValueKey('$deviceId:$online'),
            controller: controller,
            device: current,
          ),
          const SectionTitle('内容与通信'),
          ContentShortcuts(
            deviceId: deviceId,
            enabled: online,
            onUnavailable: () =>
                offerDeviceConnection(context, controller, current),
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          ActionRow(
            icon: LucideIcons.panelsTopLeft,
            title: '控制窗口',
            onTap: online
                ? () => SessionsRoute(deviceId: deviceId).push<void>(context)
                : () => offerDeviceConnection(context, controller, current),
          ),
          const SectionTitle('设备设置'),
          ConnectSwitchRow(
            title: const Text('自动同步剪贴板'),

            value: preferences['clipboardSync'] == true,
            onChanged: (next) => save('clipboardSync', next),
          ),
          ConnectSwitchRow(
            title: const Text('显示导航键'),

            value: preferences['showNavigationBar'] != false,
            onChanged: (next) => save('showNavigationBar', next),
          ),
          const SectionTitle('连接与能力'),
          ActionRow(
            icon: LucideIcons.radio,
            title: '转为 IP 连接',
            onTap: () => DeviceIpRoute(deviceId: deviceId).push<void>(context),
          ),
          ActionRow(
            icon: LucideIcons.activity,
            title: '当前活动',
            onTap: () =>
                DeviceActivitiesRoute(deviceId: deviceId).push<void>(context),
          ),
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

          if (online)
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
                  if (result != null && context.mounted) {
                    feedback(context, '已断开连接');
                  }
                }
              },
            ),
          ActionRow(
            icon: LucideIcons.trash2,
            title: '移除此设备',

            color: ConnectTokens.danger,
            onTap: () async {
              if (await removeSavedDevice(context, controller, current) &&
                  context.mounted) {
                goDevices(context);
              }
            },
          ),
          const SizedBox(height: DesignTokens.spacingLg),
        ],
      ),
    );
  }
}
