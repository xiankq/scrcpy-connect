import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
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
    final searchField = TextField(
      controller: query,
      decoration: InputDecoration(
        hintText: '搜索设备名称或型号',
        prefixIcon: const Icon(
          AppIcons.search,
          size: DesignTokens.componentIconActionSize,
        ),
        suffixIcon: query.text.isEmpty
            ? null
            : GlassActionIcon(
                tooltip: '清除搜索',
                onPressed: query.clear,
                icon: const Icon(
                  AppIcons.close,
                  size: DesignTokens.componentIconActionSize,
                ),
              ),
      ),
    );
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
    ) => LayoutBuilder(
      builder: (context, constraints) {
        const contentPadding = EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
        );
        final compactHeader =
            constraints.maxHeight < DesignTokens.componentWorkspaceSplitHeight;
        return PageFrame(
          root: initialDevice == null,
          pane: split,
          title: '设备',
          titleContent:
              showSearch &&
                  compactHeader &&
                  liquid.GlassVerticalBar.maybeOf(context) == null
              ? Row(
                  children: [
                    Text('设备', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(child: searchField),
                  ],
                )
              : null,
          actions: showWelcome || useSideToolbar ? null : [addButton],
          child: RefreshIndicator(
            onRefresh: ref.read(deviceListProvider.notifier).refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const PageChromeSliver(),
                if (showWelcome)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        DesignTokens.spacingLg,
                        compactHeader
                            ? DesignTokens.spacingLg
                            : DesignTokens.componentEmptyDeviceIntroPadding,
                        DesignTokens.spacingLg,
                        DesignTokens.spacingLg,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth:
                                DesignTokens.componentEmptyDeviceIntroWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width:
                                    DesignTokens.componentDeviceIdentityWidth,
                                height:
                                    DesignTokens.componentDeviceIdentityHeight,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? DesignTokens.colorDevicePanelDark
                                      : DesignTokens
                                            .componentDeviceIdentityBackgroundColor,
                                  borderRadius: BorderRadius.circular(
                                    DesignTokens.componentDeviceIdentityRounded,
                                  ),
                                ),
                                child: const Icon(
                                  LucideIcons.smartphone,
                                  size: DesignTokens.componentIconFeatureSize,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacingMd),
                              Text(
                                '添加第一台设备',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: DesignTokens.spacingXl),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(
                                          DesignTokens
                                              .componentButtonPrimaryRounded,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onPressed: () => const AddDeviceRoute()
                                      .push<void>(context),
                                  child: const Text('添加设备'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!showWelcome) ...[
                  SliverPadding(
                    padding: contentPadding,
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showSearch &&
                              (!compactHeader ||
                                  liquid.GlassVerticalBar.maybeOf(context) !=
                                      null)) ...[
                            const SizedBox(height: DesignTokens.spacingSm),
                            searchField,
                          ],
                          if (appLoading && !initialLoad)
                            const Padding(
                              padding: EdgeInsets.only(
                                top: DesignTokens.spacingMd,
                              ),
                              child: ContentLoadingIndicator(),
                            ),
                          if (appDeviceError != null)
                            StateNote(
                              appDeviceError,
                              icon: LucideIcons.circleAlert,
                            ),
                          const SizedBox(height: DesignTokens.spacingMd),
                        ],
                      ),
                    ),
                  ),
                  if (devices.isEmpty && !appLoading && appDeviceError == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: math.max(
                            DesignTokens.spacingXl,
                            MediaQuery.paddingOf(context).bottom +
                                DesignTokens.spacingMd,
                          ),
                        ),
                        child: EmptyContent(
                          icon: AppIcons.search,
                          title: '没有找到设备',
                          message: '试试其他名称或型号。',
                          action: TextButton(
                            onPressed: query.clear,
                            child: const Text('清除搜索'),
                          ),
                        ),
                      ),
                    ),
                  if (initialLoad)
                    SliverPadding(
                      padding: contentPadding,
                      sliver: SliverToBoxAdapter(
                        child: SkeletonRows(
                          height: compactHeader
                              ? DesignTokens
                                    .componentDeviceListItemCompactHeight
                              : DesignTokens.componentDeviceListItemHeight,
                          leadingSize:
                              DesignTokens.componentDeviceIdentityWidth,
                          leadingHeight: compactHeader
                              ? DesignTokens
                                    .componentDeviceIdentityCompactHeight
                              : DesignTokens.componentDeviceIdentityHeight,
                          trailing: true,
                          cardRadius:
                              DesignTokens.componentDeviceListItemRounded,
                          gap: DesignTokens.spacingMd,
                        ),
                      ),
                    )
                  else if (devices.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        DesignTokens.spacingMd,
                        DesignTokens.spacingZero,
                        DesignTokens.spacingMd,
                        DesignTokens.spacingZero,
                      ),
                      sliver: SliverList.separated(
                        itemCount: devices.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: DesignTokens.spacingMd),
                        itemBuilder: (context, index) => DeviceCard(
                          device: devices[index],
                          compact: compactHeader,
                          selected: split && devices[index].id == currentId,
                          onOpen: split
                              ? () => selection.value = devices[index].id
                              : null,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: DesignTokens.spacingLg),
                  ),
                ],
                const PageChromeBottomSliver(),
              ],
            ),
          ),
        );
      },
    );
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
      hasContent: devices.isNotEmpty || selected != null,
      builder: (context, split, useSideToolbar) {
        final detail = selected ?? (split ? devices.firstOrNull : null);
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
            if (useSideToolbar) ...[if (!showWelcome) addButton, ?manageButton],
          ],
        );
      },
    );
  }
}
