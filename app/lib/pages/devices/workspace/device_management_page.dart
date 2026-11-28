import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/errors/failure_message.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/devices/device_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/settings_capabilities_provider.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:scrcpy_connect/core/settings/preferences_notifier.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/devices/device_access.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/devices/device_status.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_icon_badge.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class DeviceManagementPage extends ConsumerWidget {
  const DeviceManagementPage({super.key, required this.device});

  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).devices;
    final current =
        devices.where((item) => item.id == device.id).firstOrNull ?? device;
    final id = current.id;
    final online = current.status == DeviceConnectionStatus.connected;
    final canStop = hasDeviceConnectionIntent(current);
    final settingsOwner = ref.watch(settingsManagementProvider);
    final preferences =
        ref.watch(
          preferencesProvider.select(
            (state) => state.values.deviceSettings[id],
          ),
        ) ??
        const DevicePreferences();
    Future<void> saveClipboard(bool next) async {
      try {
        if (next &&
            !await confirm(
              context,
              '开启自动剪贴板同步？',
              '操作手机画面时，两端会同步新复制的文字，包括验证码和密码。',
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
        if (context.mounted) {
          feedback(context, failureMessage(error, fallback: '无法更改剪贴板同步。请重试。'));
        }
      }
    }

    // 设备管理（Ardot H12 2:553）：设备信息与诊断、画面与剪贴板、危险动作三组，组间 24。
    return PageFrame(
      title: '设备管理',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.componentPagePadding),
        children: [
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.pencil,
                color: FunctionTone.device,
                title: '设备名称',
                value: deviceName(current),
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
                    if (context.mounted) {
                      feedback(
                        context,
                        failureMessage(error, fallback: '无法保存设备名称。请重试。'),
                      );
                    }
                  }
                  if (context.mounted &&
                      identical(
                        management,
                        ref.read(deviceManagementProvider),
                      )) {
                    await ref.read(deviceListProvider.notifier).refresh();
                  }
                },
              ),
              ActionRow(
                icon: LucideIcons.link,
                color: FunctionTone.connection,
                title: '连接配置',
                value: current.transport == null
                    ? null
                    : deviceTransportLabel(current),
                onTap: () =>
                    DeviceConnectionRoute(deviceId: id).push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.gauge,
                title: '连接诊断',
                onTap: () => DiagnosticsRoute(deviceId: id).push<void>(context),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.componentListSectionGap),
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.monitor,
                color: FunctionTone.media,
                title: '画面与控制',
                onTap: () => QualityRoute(deviceId: id).push<void>(context),
              ),
              ConnectSwitchRow(
                title: const Text('自动同步剪贴板'),
                subtitle: const Text('连接时同步两端复制的文字'),
                icon: LucideIcons.clipboard,
                iconColor: FunctionTone.transfer,
                value: preferences.clipboardSync ?? false,
                onChanged: saveClipboard,
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.componentListSectionGap),
          SettingsGroup(
            children: [
              AppListRow(
                title: Text(online ? '断开设备连接' : '停止连接'),
                destructive: true,
                enabled: canStop,
                onTap: !canStop
                    ? null
                    : () => stopDeviceConnection(context, ref, current),
              ),
              AppListRow(
                title: const Text('移除设备'),
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
        ],
      ),
    );
  }
}
