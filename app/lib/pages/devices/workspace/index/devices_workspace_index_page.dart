import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

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
    final audioError = ref.watch(
      appControllerProvider.select((state) => state.audioError),
    );
    final current = {...device, ...controller.currentDevice(device)};
    final id = value(current, 'id');
    final online = current['status'] == 'connected';
    final preferences = jsonObject(jsonObject(settings['deviceSettings'])[id]);
    final quality = {
      ...settings,
      ...jsonObject(jsonObject(settings['deviceQuality'])[id]),
    };
    final qualityLabel = switch (quality['qualityPreset']) {
      'smooth' => '流畅',
      'balanced' => '均衡',
      'clear' => '清晰',
      null || '' => '未获取',
      _ => '自定义',
    };
    Future<void> save(String key, bool next) async {
      try {
        await controller.updateDeviceSetting(id, key, next);
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      }
    }

    Widget toggle(
      String title,
      IconData icon,
      String key, {
      bool defaultValue = false,
    }) => ConnectSwitchRow(
      title: Text(title),
      icon: icon,
      value: preferences[key] as bool? ?? defaultValue,
      onChanged: (next) => save(key, next),
    );
    return PageFrame(
      title: deviceName(current),
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacingMd,
              DesignTokens.spacingMd,
              DesignTokens.spacingMd,
              DesignTokens.spacingZero,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  DeviceHero(controller: controller, device: current),
                  if (audioError != null)
                    StateNote(audioError, icon: LucideIcons.volumeX),
                  const SectionTitle('快捷操作'),
                  ContentShortcuts(
                    deviceId: id,
                    enabled: online,
                    onUnavailable: () =>
                        offerDeviceConnection(context, controller, current),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
            ),
            sliver: RunningApps(
              key: ValueKey('$id:$online'),
              controller: controller,
              device: current,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('设备设置'),
                  SettingsGroup(
                    children: [
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
                            await perform(
                              context,
                              controller,
                              'devices.rename',
                              {'deviceId': id, 'name': name},
                            );
                            await controller.refreshDevices();
                          }
                        },
                      ),
                      ActionRow(
                        icon: LucideIcons.network,
                        title: '连接配置',
                        onTap: () =>
                            DeviceConnectionRoute(deviceId: id)
                                .push<void>(context),
                      ),
                      ActionRow(
                        icon: LucideIcons.radio,
                        title: '转为 IP 连接',
                        onTap: () =>
                            DeviceIpRoute(deviceId: id).push<void>(context),
                      ),
                      ActionRow(
                        icon: LucideIcons.slidersHorizontal,
                        title: '画面设置',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              qualityLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: DesignTokens.spacingXs),
                            const Icon(
                              LucideIcons.chevronRight,
                              size: DesignTokens.componentIconSmallSize,
                            ),
                          ],
                        ),
                        onTap: () =>
                            QualityRoute(deviceId: id).push<void>(context),
                      ),
                      toggle('自动同步剪贴板', LucideIcons.clipboard, 'clipboardSync'),
                      toggle(
                        '显示导航键',
                        LucideIcons.navigation,
                        'showNavigationBar',
                        defaultValue: true,
                      ),
                      toggle('新画面启动时点亮屏幕', LucideIcons.sun, 'wakeOnConnect'),
                      toggle('关闭最后画面时锁屏', LucideIcons.moon, 'lockOnClose'),
                      toggle('保持手机唤醒', LucideIcons.alarmClock, 'stayAwake'),
                    ],
                  ),
                  const SectionTitle('连接能力'),
                  SettingsGroup(
                    children: [
                      ActionRow(
                        icon: LucideIcons.shieldCheck,
                        title: '功能支持状态',
                        onTap: () =>
                            CapabilitiesRoute(deviceId: id).push<void>(context),
                      ),
                      ActionRow(
                        icon: LucideIcons.stethoscope,
                        title: '连接诊断',
                        onTap: () =>
                            DiagnosticsRoute(deviceId: id).push<void>(context),
                      ),
                      ActionRow(
                        icon: LucideIcons.activity,
                        title: '当前活动',
                        onTap: () =>
                            DeviceActivitiesRoute(deviceId: id)
                                .push<void>(context),
                      ),
                    ],
                  ),
                  const SectionTitle('设备管理'),
                  SettingsGroup(
                    children: [
                      ActionRow(
                        icon: LucideIcons.unplug,
                        title: '断开设备连接',
                        enabled: online,
                        onTap: !online
                            ? null
                            : () async {
                                if (await confirm(
                                      context,
                                      '断开 ${deviceName(current)}？',
                                      '该设备的画面会关闭，未完成传输可能中断。本机设备记录和已保存文件会保留。',
                                      action: '断开连接',
                                    ) &&
                                    context.mounted) {
                                  await perform(
                                    context,
                                    controller,
                                    'devices.disconnect',
                                    {'deviceId': id},
                                  );
                                  await controller.refreshDevices();
                                }
                              },
                      ),
                      ActionRow(
                        icon: LucideIcons.trash2,
                        title: '移除此设备',
                        onTap: () async {
                          if (await removeSavedDevice(
                                context,
                                controller,
                                current,
                              ) &&
                              context.mounted) {
                            goDevices(context);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                ],
              ),
            ),
          ),
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
