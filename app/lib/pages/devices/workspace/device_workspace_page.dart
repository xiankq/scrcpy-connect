import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/core/media/audio_error_notifier.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/content_shortcuts.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/device_hero.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/favorite_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/running_apps.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/workspace_call_card.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';

class DeviceWorkspacePage extends ConsumerWidget {
  const DeviceWorkspacePage({
    super.key,
    required this.device,
    required this.manageButton,
    this.pane = false,
    this.onBack,
  });
  final bool pane;
  final VoidCallback? onBack;
  final DeviceSnapshot device;
  final Widget? manageButton;

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
      titleContent: const SizedBox.shrink(),
      actions: [
        if (!pane && RemoteWindows.hasWindows(context))
          const RemoteWindowsButton(),
        ?manageButton,
      ],
      child: CustomScrollView(
        slivers: [
          const PageChromeSliver(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spacingMd,
              DesignTokens.spacingXxs,
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
                  const SizedBox(
                    height: DesignTokens.componentWorkspaceSectionGap,
                  ),
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
                  const SizedBox(
                    height: DesignTokens.componentWorkspaceSectionGap,
                  ),
                  FavoriteApps(key: ValueKey(id), device: current),
                  const SizedBox(
                    height: DesignTokens.componentWorkspaceSectionGap,
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
          const PageChromeBottomSliver(),
        ],
      ),
    );
  }
}
