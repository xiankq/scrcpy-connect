import 'package:scrcpy_connect/widgets/page_chrome.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/pages/devices/workspace/widgets/phone_app.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AppsPage extends HookWidget {
  const AppsPage({super.key, required this.controller, required this.device});
  final AppController controller;
  final Json device;

  @override
  Widget build(BuildContext context) {
    final query = useTextEditingController();
    useListenable(query);
    return PageFrame(
      title: '全部应用',
      child: CommandView(
        controller: controller,
        command: 'apps.list',
        params: {'deviceId': device['id']},
        emptyTitle: '暂时无法读取应用',
        alternative: TextButton(
          onPressed: () =>
              openRemoteRoute(context, deviceId: value(device, 'id')),
          child: const Text('在手机上继续处理'),
        ),
        builder: (context, data, refresh) {
          final apps = objects(data['apps'])
              .where(
                (app) => '${value(app, 'name')} ${value(app, 'packageName')}'
                    .toLowerCase()
                    .contains(query.text.toLowerCase()),
              )
              .toList();
          return CustomScrollView(
            slivers: [
              const PageChromeSliver(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(DesignTokens.spacingMd),
                  child: TextField(
                    controller: query,
                    decoration: const InputDecoration(
                      hintText: '搜索应用',
                      prefixIcon: Icon(
                        LucideIcons.search,
                        size: DesignTokens.componentIconActionSize,
                      ),
                    ),
                  ),
                ),
              ),
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
                  ),
                  sliver: SliverList.builder(
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        leading: PhoneAppIcon(
                          controller: controller,
                          deviceId: value(device, 'id'),
                          packageName: value(app, 'packageName'),
                        ),
                        title: Text(
                          value(app, 'name', value(app, 'packageName')),
                        ),
                        onTap: () => openPhoneApp(context, device, app),
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
