import 'package:scrcpy_connect/widgets/root_page_header.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/devices/index/widgets/device_card.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/recovery_status.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DevicesPage extends HookConsumerWidget {
  const DevicesPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appDevices = ref.watch(
      appControllerProvider.select((state) => state.devices),
    );
    final appLoading = ref.watch(
      appControllerProvider.select((state) => state.loading),
    );
    final appDeviceError = ref.watch(
      appControllerProvider.select((state) => state.deviceError),
    );
    final query = useTextEditingController();
    useListenable(query);
    final devices = appDevices
        .where(
          (d) => '${deviceName(d)} ${value(d, 'model')}'.toLowerCase().contains(
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
            : IconButton(
                tooltip: '清除搜索',
                onPressed: query.clear,
                icon: const Icon(
                  LucideIcons.x,
                  size: DesignTokens.componentIconActionSize,
                ),
              ),
      ),
    );
    final addButton = GlassIconButton(
      onPressed: () => AddDeviceRoute().push<void>(context),
      tooltip: '添加设备',
      icon: const Icon(LucideIcons.plus),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeader =
            constraints.maxHeight < DesignTokens.componentSheetShortHeight;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.componentPageContentMaxWidth,
              ),
              child: RefreshIndicator(
                onRefresh: controller.refreshDevices,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: RecoveryStatus()),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spacingMd,
                        DesignTokens.spacingZero,
                        DesignTokens.spacingMd,
                        DesignTokens.spacingZero,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (compactHeader)
                              Row(
                                children: [
                                  Text(
                                    '设备',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(width: DesignTokens.spacingSm),
                                  Expanded(child: searchField),
                                  const SizedBox(width: DesignTokens.spacingXs),
                                  addButton,
                                ],
                              )
                            else ...[
                              RootPageHeader(title: '设备', action: addButton),
                              const SizedBox(height: DesignTokens.spacingSm),
                              searchField,
                            ],
                            if (appLoading)
                              const Padding(
                                padding: EdgeInsets.only(
                                  top: DesignTokens.spacingMd,
                                ),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            if (appDeviceError != null)
                              StateNote(
                                appDeviceError,
                                icon: LucideIcons.circleAlert,
                              ),
                            if (!appLoading &&
                                appDevices.isNotEmpty &&
                                appDevices.every(
                                  (d) => d['status'] != 'connected',
                                ))
                              const StateNote(
                                '设备当前均不在线。连接后即可继续使用应用和内容。',
                                icon: LucideIcons.wifiOff,
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
                          padding: const EdgeInsets.only(bottom: 100),
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
                                      size:
                                          DesignTokens.componentIconActionSize,
                                    ),
                                    label: const Text('添加设备'),
                                  ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        sliver: SliverList.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: DesignTokens.spacingMd),
                          itemBuilder: (context, index) => DeviceCard(
                            controller: controller,
                            device: devices[index],
                            compact: compactHeader,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
