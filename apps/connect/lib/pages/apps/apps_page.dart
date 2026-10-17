import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
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
      title: '手机应用',
      subtitle: deviceName(device),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              controller: query,
              decoration: const InputDecoration(
                hintText: '搜索应用',
                prefixIcon: Icon(LucideIcons.search, size: 18),
              ),
            ),
          ),
          Expanded(
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
                      (a) => '${value(a, 'name')} ${value(a, 'packageName')}'
                          .toLowerCase()
                          .contains(query.text.toLowerCase()),
                    )
                    .toList();
                if (apps.isEmpty) {
                  return EmptyContent(
                    icon: LucideIcons.layoutGrid,
                    title: query.text.isEmpty ? '没有可显示的应用' : '未找到应用',
                    message: query.text.isEmpty
                        ? '连接设备后重新获取应用列表。'
                        : '试试应用名称或包名。',
                    action: TextButton(
                      onPressed: query.text.isEmpty ? refresh : query.clear,
                      child: const Text('重新检查'),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: apps.length,
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    return ActionRow(
                      icon: LucideIcons.appWindow,
                      title: value(app, 'name', value(app, 'packageName')),
                      subtitle: value(app, 'packageName'),
                      onTap: () async {
                        final accepted = await confirm(
                          context,
                          '继续“${value(app, 'name', value(app, 'packageName'))}”？',
                          '将接续 ${deviceName(device)} 上的真实应用与登录状态。应用仅支持一个实例时，现有任务可能迁移至此；返回工作台会保留窗口；关闭窗口后任务交回手机。',
                          action: '打开应用',
                        );
                        if (accepted && context.mounted) {
                          openRemoteRoute(
                            context,
                            deviceId: value(device, 'id'),
                            packageName: value(app, 'packageName'),
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
