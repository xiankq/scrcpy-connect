import 'package:scrcpy_connect/router/app_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrcpy_connect/pages/devices/widgets/device_card.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
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
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.refreshDevices,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '设备',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => AddDeviceRoute().push<void>(context),
                          tooltip: '添加设备',
                          icon: const Icon(LucideIcons.plus),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appLoading
                          ? '正在检查连接…'
                          : appDevices.isEmpty
                          ? '让手边的屏幕，接续另一台手机。'
                          : '${appDevices.where((d) => d['status'] == 'connected').length} 台已连接 · ${appDevices.length} 台设备',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: query,
                      decoration: InputDecoration(
                        hintText: '搜索设备名称或型号',
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        suffixIcon: query.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清除搜索',
                                onPressed: query.clear,
                                icon: const Icon(LucideIcons.x, size: 18),
                              ),
                      ),
                    ),
                    if (appLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (appDeviceError != null)
                      StateNote(appDeviceError, icon: LucideIcons.circleAlert),
                    if (!appLoading &&
                        appDevices.isNotEmpty &&
                        appDevices.every((d) => d['status'] != 'connected'))
                      const StateNote(
                        '设备当前均不在线。连接后即可继续使用应用和内容。',
                        icon: LucideIcons.wifiOff,
                      ),
                    const SizedBox(height: 20),
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
                            icon: const Icon(LucideIcons.plus, size: 18),
                            label: const Text('添加设备'),
                          ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => DeviceCard(
                    controller: controller,
                    device: devices[index],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
