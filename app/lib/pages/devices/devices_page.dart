import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:foldable/foldable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as liquid;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_list_notifier.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/device_labels.dart';
import 'package:scrcpy_connect/widgets/glass/glass_overlays.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:scrcpy_connect/widgets/adaptive_window.dart';

class DevicesPage extends HookConsumerWidget {
  const DevicesPage({super.key});
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
          LucideIcons.search,
          size: DesignTokens.componentIconActionSize,
        ),
        suffixIcon: query.text.isEmpty
            ? null
            : GlassActionIcon(
                tooltip: '清除搜索',
                onPressed: query.clear,
                icon: const Icon(
                  LucideIcons.x,
                  size: DesignTokens.componentIconActionSize,
                ),
              ),
      ),
    );
    final addButton = IconButton(
      onPressed: () => AddDeviceRoute().push<void>(context),
      tooltip: '添加设备',
      style: IconButton.styleFrom(
        minimumSize: const Size.square(DesignTokens.componentIconButtonSize),
        maximumSize: const Size.square(DesignTokens.componentIconButtonSize),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      icon: const Icon(LucideIcons.plus),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final fold = DuoMediaQuery.maybeOf(context);
        final verticalBar = liquid.GlassVerticalBar.maybeOf(context);
        final barInset = verticalBar == null
            ? DesignTokens.spacingZero
            : verticalBar.width + DesignTokens.spacingSm;
        final leadingInset =
            verticalBar?.edge == liquid.GlassVerticalBarEdge.leading
            ? barInset
            : DesignTokens.spacingZero;
        final trailingInset =
            verticalBar?.edge == liquid.GlassVerticalBarEdge.trailing
            ? barInset
            : DesignTokens.spacingZero;
        final contentPadding = EdgeInsets.fromLTRB(
          DesignTokens.spacingMd + leadingInset,
          DesignTokens.spacingZero,
          DesignTokens.spacingMd + trailingInset,
          DesignTokens.spacingZero,
        );
        final compactHeader =
            constraints.maxHeight < DesignTokens.componentSheetShortHeight;
        return PageFrame(
          root: true,
          title: '设备',
          titleContent: compactHeader
              ? Row(
                  children: [
                    Text('设备', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: DesignTokens.spacingSm),
                    Expanded(child: searchField),
                  ],
                )
              : null,
          trailingAction: addButton,
          child: RefreshIndicator(
            onRefresh: ref.read(deviceListProvider.notifier).refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const PageChromeSliver(),
                SliverPadding(
                  padding: contentPadding,
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!compactHeader) ...[
                          const SizedBox(height: DesignTokens.spacingSm),
                          searchField,
                        ],
                        if (appLoading)
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
                if (devices.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: leadingInset,
                        right: trailingInset,
                        bottom: math.max(
                          DesignTokens.spacingXl,
                          MediaQuery.paddingOf(context).bottom +
                              DesignTokens.spacingMd,
                        ),
                      ),
                      child: EmptyContent(
                        icon: query.text.isEmpty
                            ? LucideIcons.smartphone
                            : LucideIcons.search,
                        title: query.text.isNotEmpty
                            ? '没有找到设备'
                            : appLoading
                            ? '正在检查设备'
                            : '添加你的第一台设备',
                        message: query.text.isNotEmpty
                            ? '试试其他名称或型号。'
                            : '被控手机无需安装应用。使用无线调试或 USB 数据线，完成授权后连接。',
                        action: query.text.isNotEmpty
                            ? TextButton(
                                onPressed: query.clear,
                                child: const Text('清除搜索'),
                              )
                            : FilledButton.icon(
                                onPressed: () =>
                                    AddDeviceRoute().push<void>(context),
                                icon: const Icon(
                                  LucideIcons.plus,
                                  size: DesignTokens.componentIconActionSize,
                                ),
                                label: const Text('添加设备'),
                              ),
                      ),
                    ),
                  )
                else if (WindowEnvironment.sizeClassFor(constraints.maxWidth) ==
                        WindowSizeClass.expanded ||
                    fold?.isFoldable == true &&
                        fold?.horizontalSizeClass == SizeClass.regular &&
                        fold?.isFullyOpen == true)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      DesignTokens.spacingMd + leadingInset,
                      DesignTokens.spacingZero,
                      DesignTokens.spacingMd + trailingInset,
                      DesignTokens.spacingZero,
                    ),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: DesignTokens.spacingMd,
                            crossAxisSpacing: DesignTokens.spacingMd,
                            childAspectRatio: 2.35,
                          ),
                      itemCount: devices.length,
                      itemBuilder: (context, index) => DeviceCard(
                        device: devices[index],
                        compact: compactHeader,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      DesignTokens.spacingMd + leadingInset,
                      DesignTokens.spacingZero,
                      DesignTokens.spacingMd + trailingInset,
                      DesignTokens.spacingZero,
                    ),
                    sliver: SliverList.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: DesignTokens.spacingMd),
                      itemBuilder: (context, index) => DeviceCard(
                        device: devices[index],
                        compact: compactHeader,
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: DesignTokens.spacingLg),
                ),
                const PageChromeBottomSliver(),
              ],
            ),
          ),
        );
      },
    );
  }
}
