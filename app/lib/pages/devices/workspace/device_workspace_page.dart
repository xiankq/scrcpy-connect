import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/section_title.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceWorkspacePage extends ConsumerWidget {
  const DeviceWorkspacePage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).devices;
    final settingsOwner = ref.watch(settingsManagementProvider);
    final settings = ref.watch(
      preferencesProvider.select((state) => state.values),
    );
    final audioError = ref.watch(audioErrorProvider);
    final current =
        devices.where((item) => item.id == device.id).firstOrNull ?? device;
    final id = current.id;
    final online = current.status == DeviceConnectionStatus.connected;
    final canStop = hasDeviceConnectionIntent(current);
    final preferences =
        settings.deviceSettings[id] ?? const DevicePreferences();
    Future<void> saveClipboard(bool next) async {
      try {
        if (next &&
            !await confirm(
              context,
              '开启自动剪贴板同步？',
              '在当前可见且获焦的手机画面中，新复制的文字会在两端传送，可能包含密码、验证码或其他敏感内容。系统可能请求粘贴访问；开启只建立基线，不覆盖本机已有内容。',
              action: '开启同步',
            )) {
          return;
        }
        if (!context.mounted ||
            !identical(ref.read(settingsManagementProvider), settingsOwner)) {
          return;
        }
        await ref
            .read(preferencesProvider.notifier)
            .updateDevice(id, DevicePreferences(clipboardSync: next));
      } catch (error) {
        if (context.mounted) feedback(context, '$error');
      }
    }

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
                  DeviceHero(device: current),
                  WorkspaceCallCard(device: current),
                  if (audioError != null)
                    StateNote(audioError, icon: LucideIcons.volumeX),
                  const SectionTitle('快捷操作'),
                  ContentShortcuts(
                    deviceId: id,
                    enabled: online,
                    onUnavailable: () =>
                        offerDeviceConnection(context, ref, current),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingMd,
            ),
            sliver: RunningApps(key: ValueKey('$id:$online'), device: current),
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
                          final management = ref.read(deviceManagementProvider);
                          final name = await askText(
                            context,
                            title: '设备名称',
                            initial: deviceName(current),
                            label: '仅更改本机列表名称',
                          );
                          if (name == null ||
                              !context.mounted ||
                              !identical(
                                management,
                                ref.read(deviceManagementProvider),
                              )) {
                            return;
                          }
                          try {
                            await management.renameDevice(id, name);
                          } catch (error) {
                            if (context.mounted) feedback(context, '$error');
                          }
                          if (context.mounted &&
                              identical(
                                management,
                                ref.read(deviceManagementProvider),
                              )) {
                            await ref
                                .read(deviceListProvider.notifier)
                                .refresh();
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
                      ConnectSwitchRow(
                        title: const Text('自动同步剪贴板'),
                        icon: LucideIcons.clipboard,
                        value: preferences.clipboardSync ?? false,
                        onChanged: saveClipboard,
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
                      ActionRow(
                        icon: LucideIcons.unplug,
                        title: online ? '断开设备连接' : '停止连接',
                        enabled: canStop,
                        onTap: !canStop
                            ? null
                            : () => stopDeviceConnection(context, ref, current),
                      ),
                      ActionRow(
                        icon: LucideIcons.trash2,
                        title: '移除此设备',
                        destructive: true,
                        onTap: () async {
                          if (await removeSavedDevice(context, ref, current) &&
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
