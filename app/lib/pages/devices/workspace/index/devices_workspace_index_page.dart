import 'package:scrcpy_connect/services/display_labels.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_access.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/index/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/stores/app_controller.dart';
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
    final canStop = hasDeviceConnectionIntent(current);
    final preferences = jsonObject(jsonObject(settings['deviceSettings'])[id]);
    Future<void> save(String key, bool next) async {
      try {
        if (key == 'clipboardSync' &&
            next &&
            !await confirm(
              context,
              '开启自动剪贴板同步？',
              '在当前可见且获焦的手机画面中，新复制的文字会在两端传送，可能包含密码、验证码或其他敏感内容。系统可能请求粘贴访问；开启只建立基线，不覆盖本机已有内容。',
              action: '开启同步',
            )) {
          return;
        }
        if (!context.mounted) return;
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
                  WorkspaceCallCard(controller: controller, device: current),
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
                        icon: LucideIcons.slidersHorizontal,
                        title: '画面与控制',
                        onTap: () =>
                            QualityRoute(deviceId: id).push<void>(context),
                      ),
                      toggle('自动同步剪贴板', LucideIcons.clipboard, 'clipboardSync'),
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
                      ActionRow(
                        icon: LucideIcons.unplug,
                        title: online ? '断开设备连接' : '停止连接',
                        enabled: canStop,
                        onTap: !canStop
                            ? null
                            : () => stopDeviceConnection(
                                context,
                                controller,
                                current,
                              ),
                      ),
                      ActionRow(
                        icon: LucideIcons.trash2,
                        title: '移除此设备',
                        destructive: true,
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
