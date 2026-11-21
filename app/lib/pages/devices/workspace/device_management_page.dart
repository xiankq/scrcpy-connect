import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import 'package:scrcpy_connect/widgets/grouped_list.dart';
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
      title: '设备管理',
      child: GroupedListView(
        padding: const EdgeInsets.all(DesignTokens.spacingMd),
        children: [
          SettingsGroup(
            children: [
              ActionRow(
                icon: LucideIcons.squarePen,
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
                    await ref.read(deviceListProvider.notifier).refresh();
                  }
                },
              ),
              ActionRow(
                icon: LucideIcons.network,
                title: '连接配置',
                onTap: () =>
                    DeviceConnectionRoute(deviceId: id).push<void>(context),
              ),
              ActionRow(
                icon: LucideIcons.slidersHorizontal,
                title: '画面与控制',
                onTap: () => QualityRoute(deviceId: id).push<void>(context),
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
                onTap: () => DiagnosticsRoute(deviceId: id).push<void>(context),
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
                title: '移除设备',
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
