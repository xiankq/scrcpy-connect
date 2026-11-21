import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/favorite_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceWorkspacePage extends ConsumerWidget {
  const DeviceWorkspacePage({
    super.key,
    required this.device,
    this.pane = false,
    this.onBack,
  });
  final bool pane;
  final VoidCallback? onBack;
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider).devices;
    final audioError = ref.watch(audioErrorProvider);
    final current =
        devices.where((item) => item.id == device.id).firstOrNull ?? device;
    final id = current.id;
    final online = current.status == DeviceConnectionStatus.connected;
    return PageFrame(
      pane: pane,
      onBack: onBack,
      title: '设备工作台',
      actions: [
        GlassActionIcon(
          tooltip: '设备管理',
          icon: const Icon(LucideIcons.settings),
          onPressed: () =>
              DeviceManagementRoute(deviceId: id).push<void>(context),
        ),
      ],
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
                  DeviceHero(device: current, pane: pane),
                  WorkspaceCallCard(device: current),
                  if (audioError != null)
                    StateNote(audioError, icon: LucideIcons.volumeX),
                  const SizedBox(height: DesignTokens.spacingMd),
                  ContentShortcuts(
                    deviceId: id,
                    enabled: online,
                    onUnavailable: () => feedback(
                      context,
                      deviceConnectionInProgress(current)
                          ? '无法打开，设备正在连接。'
                          : '无法打开，请先连接设备。',
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  FavoriteApps(key: ValueKey(id), device: current),
                  const SizedBox(height: DesignTokens.spacingMd),
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
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
