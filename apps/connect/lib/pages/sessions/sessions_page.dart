import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';

import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SessionsPage extends StatelessWidget {
  const SessionsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '控制会话',
    subtitle: deviceName(device),
    child: CommandView(
      controller: controller,
      command: 'session.list',
      params: {'deviceId': device['id']},
      emptyTitle: '暂时无法读取会话',
      builder: (context, data, refresh) {
        final sessions = objects(data['sessions']);
        if (sessions.isEmpty) {
          return EmptyContent(
            icon: LucideIcons.panelsTopLeft,
            title: '没有打开的控制会话',
            message: '从手机屏幕或应用入口接续真实任务。',
            action: FilledButton(
              onPressed: () =>
                  openRemoteRoute(context, deviceId: value(device, 'id')),
              child: const Text('打开手机屏幕'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final session in sessions)
              ActionRow(
                icon: LucideIcons.appWindow,
                title: value(session, 'name', '手机屏幕'),
                subtitle: statusText(value(session, 'status')),
                onTap: () => openRemoteRoute(
                  context,
                  deviceId: value(device, 'id'),
                  sessionId: value(session, 'sessionId', value(session, 'id')),
                ),
              ),
          ],
        );
      },
    ),
  );
}
