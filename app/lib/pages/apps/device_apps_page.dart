import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:scrcpy_connect/core/devices/device_query_provider.dart';
import 'package:scrcpy_connect/core/devices/models/device_snapshot.dart';
import 'package:scrcpy_connect/pages/apps/phone_app_launcher.dart';
import 'package:scrcpy_connect/pages/apps/widgets/phone_app_icon.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/styles/generated/design_tokens.g.dart';
import 'package:scrcpy_connect/widgets/async_content.dart';
import 'package:scrcpy_connect/widgets/content.dart';
import 'package:scrcpy_connect/widgets/loading_skeleton.dart';
import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

class DeviceAppsPage extends HookConsumerWidget {
  const DeviceAppsPage({super.key, required this.device});
  final DeviceSnapshot device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useTextEditingController();
    useListenable(query);
    final provider = installedDeviceAppsProvider(device.id);
    final result = ref.watch(provider);
    void refresh() => ref.invalidate(provider);
    return PageFrame(
      title: '全部应用',
      search: (controller: query, hint: '搜索应用'),
      child: AsyncContent(
        loading: result.isLoading,
        data: result.value,
        loadingPlaceholder: CustomScrollView(
          slivers: [
            const PageChromeSliver(),
            const SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
                vertical: DesignTokens.spacingXs,
              ),
              sliver: SliverToBoxAdapter(
                child: SkeletonRows(
                  height:
                      DesignTokens.componentRowHeight + DesignTokens.spacingXxs,
                  lines: 1,
                  trailing: true,
                ),
              ),
            ),
            const PageChromeBottomSliver(),
          ],
        ),
        error: result.error,
        onRefresh: refresh,
        emptyTitle: '暂时无法读取应用',
        alternative: TextButton(
          onPressed: () => openRemoteRoute(context, deviceId: device.id),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data) {
          final apps = data
              .where(
                (app) => '${app.name} ${app.packageName}'
                    .toLowerCase()
                    .contains(query.text.toLowerCase()),
              )
              .toList();
          return CustomScrollView(
            slivers: [
              const PageChromeSliver(),
              if (apps.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyContent(
                    icon: LucideIcons.layoutGrid,
                    title: query.text.isEmpty ? '没有可显示的应用' : '未找到应用',
                    message: query.text.isEmpty
                        ? '连接设备后重新获取应用列表。'
                        : '试试应用名称或包名。',
                    action: TextButton(
                      onPressed: query.text.isEmpty ? refresh : query.clear,
                      child: Text(query.text.isEmpty ? '重新检查' : '清除搜索'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacingMd,
                    vertical: DesignTokens.spacingXs,
                  ),
                  sliver: SliverList.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: DesignTokens.spacingXxs,
                        ),
                        child: ListTile(
                          minTileHeight: DesignTokens.componentRowHeight,
                          minLeadingWidth: DesignTokens.componentListIconSize,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: DesignTokens.spacingMd,
                            vertical: DesignTokens.spacingXs,
                          ),
                          leading: PhoneAppIcon(
                            size: DesignTokens.componentListIconSize,
                            deviceId: device.id,
                            packageName: app.packageName,
                          ),
                          title: Text(app.name),
                          onTap: () => openPhoneApp(context, ref, device, app),
                        ),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: DesignTokens.spacingMd),
              ),
              const PageChromeBottomSliver(),
            ],
          );
        },
      ),
    );
  }
}
