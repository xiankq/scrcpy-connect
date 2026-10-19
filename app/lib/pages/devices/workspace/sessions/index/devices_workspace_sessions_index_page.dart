import 'package:scrcpy_connect/widgets/grouped_list.dart';
import 'package:scrcpy_connect/router/app_router.dart';
import 'package:scrcpy_connect/router/navigation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/widgets/action_row.dart';
import 'package:scrcpy_connect/widgets/command_view.dart';
import 'package:scrcpy_connect/widgets/dialogs.dart';
import 'package:scrcpy_connect/widgets/page_frame.dart';
import 'package:scrcpy_connect/widgets/state_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:design_system/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SessionsPage extends HookWidget {
  const SessionsPage({
    super.key,
    required this.controller,
    required this.device,
  });
  final AppController controller;
  final Json device;
  @override
  Widget build(BuildContext context) {
    final stream = useMemoized(
      () => controller.eventStream().where(
        (event) =>
            (value(event, 'type').startsWith('session.') &&
                event['type'] != 'session.frame') ||
            value(event, 'type').startsWith('state.'),
      ),
      [controller],
    );
    final event = useStream(stream);
    return PageFrame(
      title: '控制会话',
      child: CommandView(
        controller: controller,
        command: 'session.list',
        params: {'deviceId': device['id']},
        refreshKey: event.data,
        emptyTitle: '暂时无法读取会话',
        builder: (context, data, refresh) {
          final sessions = objects(data['sessions'])
              .where(
                (item) =>
                    item['deviceId'] == device['id'] &&
                    item['status'] != 'stopped',
              )
              .toList();
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
          return GroupedListView(
            padding: const EdgeInsets.all(DesignTokens.spacingMd),
            children: [
              const StateNote('返回工作台会保留窗口并暂停不可见画面。关闭窗口会把应用任务交回手机，不会强制停止应用。'),
              for (final session in sessions)
                ContentPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ActionRow(
                        key: ValueKey(
                          'open-session:${value(session, 'sessionId', value(session, 'id'))}',
                        ),
                        icon: LucideIcons.appWindow,
                        title: value(session, 'name', '手机屏幕'),
                        trailing: Text(
                          sessionStatusText(value(session, 'status')),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),

                        onTap: () async {
                          await openRemoteRoute(
                            context,
                            deviceId: value(device, 'id'),
                            sessionId: value(
                              session,
                              'sessionId',
                              value(session, 'id'),
                            ),
                          );
                          if (context.mounted) refresh();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: '窗口工具',
                              color: Theme.of(context).colorScheme.onSurface,
                              key: ValueKey(
                                'tools-session:${value(session, 'sessionId', value(session, 'id'))}',
                              ),
                              icon: const Icon(LucideIcons.slidersHorizontal),
                              onPressed: () => SessionToolsRoute(
                                deviceId: value(device, 'id'),
                                sessionId: value(
                                  session,
                                  'sessionId',
                                  value(session, 'id'),
                                ),
                              ).push<void>(context),
                            ),
                            IconButton(
                              tooltip: '关闭窗口',
                              color: Theme.of(context).colorScheme.onSurface,
                              key: ValueKey(
                                'close-session:${value(session, 'sessionId', value(session, 'id'))}',
                              ),
                              icon: const Icon(LucideIcons.x),
                              onPressed: () async {
                                final result = await perform(
                                  context,
                                  controller,
                                  'session.stop',
                                  {
                                    'sessionId': value(
                                      session,
                                      'sessionId',
                                      value(session, 'id'),
                                    ),
                                    'keepTask': true,
                                  },
                                );
                                if (context.mounted && result != null) {
                                  refresh();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
