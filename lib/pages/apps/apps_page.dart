import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
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
      title: '手机应用',
      child: Column(
        children: [
          Padding(
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
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spacingMd,
                    0,
                    DesignTokens.spacingMd,
                    DesignTokens.spacingMd,
                  ),
                  itemCount: apps.length,
                  itemBuilder: (context, i) {
                    final app = apps[i];
                    return GroupedItem(
                      index: i,
                      count: apps.length,
                      child: ActionRow(
                        icon: LucideIcons.appWindow,
                        title: value(app, 'name', value(app, 'packageName')),

                        onTap: () async {
                          final api = int.tryParse(value(device, 'apiLevel'));
                          final mode = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: Colors.transparent,
                            isScrollControlled: true,
                            builder: (context) => SafeArea(
                              child: Glass(
                                padding: const EdgeInsets.all(
                                  DesignTokens.spacingMd,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '打开“${value(app, 'name', value(app, 'packageName'))}”',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(
                                        height: DesignTokens.spacingSm,
                                      ),
                                      Text(
                                        '继续 ${deviceName(device)} 上的真实应用与登录状态。',
                                      ),
                                      const SizedBox(
                                        height: DesignTokens.spacingSm,
                                      ),
                                      Text(
                                        api != null && api < 29
                                            ? '这台手机不支持独立应用窗口，可在手机屏幕继续使用。'
                                            : '独立窗口可能迁移应用现有的单实例任务；返回会保留窗口，关闭窗口会保留真实任务。',
                                      ),
                                      const SizedBox(
                                        height: DesignTokens.spacingMd,
                                      ),
                                      if (api == null || api >= 29)
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, 'window'),
                                          child: const Text('在独立窗口打开'),
                                        ),
                                      OutlinedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, 'phone'),
                                        child: const Text('在手机屏幕打开'),
                                      ),
                                      const SizedBox(
                                        height: DesignTokens.spacingXs,
                                      ),
                                      const Text('在手机屏幕打开会切换手机当前的前台应用。'),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('取消'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                          if (mode != null && context.mounted) {
                            openRemoteRoute(
                              context,
                              deviceId: value(device, 'id'),
                              packageName: value(app, 'packageName'),
                              onPhoneScreen: mode == 'phone',
                            );
                          }
                        },
                      ),
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
