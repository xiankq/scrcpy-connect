import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/widgets/content_arrival.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/pages/devices/widgets/first_device_illustration.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/router/remote_windows.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/styles/theme.dart';
import 'package:scrcpy_connect/widgets/buttons.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/widgets/list_row.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/workspace_panes.dart';
import 'package:scrcpy_connect/pages/devices/workspace/device_workspace_page.dart';

class DevicesPage extends HookConsumerWidget {
  const DevicesPage({super.key, this.initialDevice});

  final DeviceSnapshot? initialDevice;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDevices = ref.watch(
      deviceListProvider.select((state) => state.devices),
    );
    final appLoading = ref.watch(
      deviceListProvider.select((state) => state.loading),
    );
    final appDeviceError = ref.watch(
      deviceListProvider.select((state) => state.error),
    );
    final selection = useState(initialDevice?.id);
    final initialLoad = appDevices.isEmpty && appLoading;
    final showSearch = appDevices.isNotEmpty || initialLoad;
    final showWelcome =
        appDevices.isEmpty && !appLoading && appDeviceError == null;
    final query = useTextEditingController();
    useListenable(query);
    final devices = appDevices
        .where(
          (d) => '${deviceName(d)} ${(d.model ?? '')}'.toLowerCase().contains(
            query.text.toLowerCase(),
          ),
        )
        .toList();
    final addButton = GlassActionIcon(
      onPressed: () => AddDeviceRoute().push<void>(context),
      tooltip: '添加设备',
      icon: const Icon(AppIcons.add),
    );
    Widget buildList(
      BuildContext context,
      bool split,
      String? currentId,
      bool useSideToolbar,
    ) {
      const contentPadding = EdgeInsets.symmetric(
        horizontal: DesignTokens.componentPagePadding,
      );
      return PageFrame(
        root: initialDevice == null,
        pane: split,
        title: '设备',
        search: showSearch ? (controller: query, hint: '搜索设备名称或型号') : null,
        actions: useSideToolbar
            ? null
            : [
                if (RemoteWindows.hasWindows(context))
                  const RemoteWindowsButton(),
                if (!showWelcome) addButton,
              ],
        child: RefreshIndicator(
          onRefresh: ref.read(deviceListProvider.notifier).refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const PageChromeSliver(),
              ContentArrival(
                sliver: true,
                state: (initialLoad, showWelcome),
                waiting: initialLoad,
                child: SliverMainAxisGroup(
                  slivers: [
                    if (showWelcome)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _FirstDevice(),
                      ),
                    if (!showWelcome) ...[
                      if (appDeviceError != null)
                        SliverPadding(
                          padding: contentPadding,
                          sliver: SliverToBoxAdapter(
                            child: StateNote(
                              appDeviceError,
                              icon: LucideIcons.circleAlert,
                            ),
                          ),
                        ),
                      if (devices.isEmpty &&
                          !initialLoad &&
                          appDeviceError == null)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyContent(
                            icon: AppIcons.search,
                            title: '没有找到设备',
                            message: '试试其他名称或型号。',
                            action: AppButton(
                              label: '清除搜索',
                              role: AppButtonRole.secondaryOnPage,
                              size: AppButtonSize.section,
                              onPressed: query.clear,
                            ),
                          ),
                        ),
                      if (initialLoad)
                        const SliverPadding(
                          padding: contentPadding,
                          sliver: SliverToBoxAdapter(
                            child: SettingsGroup(
                              children: [
                                SkeletonRows(
                                  height:
                                      DesignTokens.componentDeviceTileSize +
                                      2 * DesignTokens.spacingMd,
                                  leadingSize:
                                      DesignTokens.componentDeviceTileSize,
                                  trailing: true,
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (devices.isNotEmpty)
                        SliverPadding(
                          padding: contentPadding,
                          sliver: SliverToBoxAdapter(
                            child: SettingsGroup(
                              separatorIndent: deviceRowSeparatorIndent,
                              children: [
                                for (final device in devices)
                                  DeviceCard(
                                    key: ValueKey(device.id),
                                    device: device,
                                    selected: split && device.id == currentId,
                                    onOpen: split
                                        ? () => selection.value = device.id
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: DesignTokens.spacingLg),
                      ),
                    ],
                  ],
                ),
              ),
              const PageChromeBottomSliver(),
            ],
          ),
        ),
      );
    }

    final selected =
        appDevices.where((d) => d.id == selection.value).firstOrNull ??
        initialDevice;
    void closeDetail() {
      if (initialDevice != null) {
        closePage<void>(context);
      } else {
        selection.value = null;
      }
    }

    return WorkspacePanes(
      onCloseDetail: selected == null ? null : closeDetail,
      hasContent: appDevices.isNotEmpty || selected != null,
      builder: (context, split, useSideToolbar) {
        final detail = selected ?? (split ? appDevices.firstOrNull : null);
        final manageButton = detail == null
            ? null
            : GlassActionIcon(
                tooltip: '设备管理',
                icon: const Icon(AppIcons.deviceManagement),
                onPressed: () =>
                    DeviceManagementRoute(deviceId: detail.id)
                        .push<void>(context),
              );
        return (
          list: buildList(context, split, detail?.id, useSideToolbar),
          detail: detail == null
              ? const SizedBox.shrink()
              : DeviceWorkspacePage(
                  key: ValueKey(detail.id),
                  device: detail,
                  pane: split,
                  onBack: split ? null : closeDetail,
                  manageButton: useSideToolbar ? null : manageButton,
                ),
          sideActions: [
            if (useSideToolbar) ...[
              if (RemoteWindows.hasWindows(context))
                const RemoteWindowsButton(),
              if (!showWelcome) addButton,
              ?manageButton,
            ],
          ],
        );
      },
    );
  }
}

/// 首次添加（Ardot「首次添加」37:2797）：纵向 40% 处，最宽 320、左右 24；
/// 160 插图下 16 为 `headline` 标题，8 为 `subheadline` 说明，24 为主按钮。
class _FirstDevice extends StatelessWidget {
  const _FirstDevice();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final type = AppTypography.of(context);
    return Align(
      // 纵向 40%：与共用空态同一落点（design.md「空态」）。
      alignment: const Alignment(0, -.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingXxl,
          vertical: DesignTokens.componentEmptyStatePadding,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.componentEmptyStateWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FirstDeviceIllustration(),
              const SizedBox(height: DesignTokens.spacingLg),
              Text(
                '添加第一台设备',
                style: type.headline,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Text(
                '用配对码、扫码、USB 或 IP 连接手机。',
                style: type.subheadline.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spacingXxl),
              AppButton(
                label: '添加设备',
                icon: AppIcons.add,
                role: AppButtonRole.primary,
                onPressed: () => const AddDeviceRoute().push<void>(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
